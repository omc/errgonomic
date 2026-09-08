# frozen_string_literal: true

module Errgonomic
  module Rails
    # Concern to make ActiveRecord optional attributes and associations return an Option.
    #
    # The reader is the boundary and the storage stays nullable: the
    # attribute, dirty tracking and the raw readers all see nil, where Rails
    # already draws the line for a reader override. Rust would expect the
    # Option all the way down; ActiveRecord reads the attribute in too many
    # places for that.
    #
    # Five compromises below are where the Rust idiom gives way to
    # ActiveRecord machinery, each forced by something ActiveRecord does with
    # an accessor rather than chosen. The set is closed: a sixth would be a
    # signal that ActiveRecord is pushing back somewhere unmapped, deserving
    # a design discussion rather than a quiet patch.
    #
    # 1. None#nil? answers true, so AR internals and ordinary nil checks
    #    treat an absent value as absent. Equality does not follow suit:
    #    None() == nil stays false.
    # 2. Some delegates persisted? and touch_later to its record, so a Some
    #    can stand in for it where ActiveRecord reads an association back
    #    through its public reader.
    # 3. Boundaries into ActiveRecord unwrap Options where a value enters,
    #    above the column type in every case: quoting and predicate building
    #    at the SQL boundary, attribute and singular association writers on
    #    assignment, the query attribute a bind is built from, the rows a
    #    bulk write takes, and an attribute default where it is declared.
    # 4. SomeValidator asks whether a value is there at all, where presence
    #    asks whether it amounts to anything: Some("") passes some: true and
    #    fails presence. It lifts what it is handed, so it asks the same
    #    question of any model, converted or not.
    # 5. Where ActiveRecord's own machinery reads a value raw, it gets one.
    #    Validation unwraps at read_attribute_for_validation, the seam every
    #    EachValidator fetches an attribute through, and serialization at
    #    read_attribute_for_serialization, the seam every attribute in a
    #    payload is fetched through, so a standard validator weighs the value
    #    and a payload carries it rather than the wrapper. A singular
    #    association with nested attributes goes further and keeps its plain
    #    reader: nested attributes are assigned through the reader, and
    #    ActiveRecord asks whatever it finds there whether it is a new record.
    #
    # errgonomic_optional_except and errgonomic_serialize_none are not on the
    # list: they are configuration, an escape hatch for whatever conflict
    # shows up next and a choice of how an absent value is written, not
    # semantic exceptions.
    module ActiveRecordOptional
      extend ActiveSupport::Concern

      included do
        errgonomic_optional_readers
        reflect_on_all_associations(:belongs_to)
          .select { |r| r.options[:optional] }
          .each { |r| errgonomic_wrap_optional(r.name) }
        reflect_on_all_associations(:has_one)
          .reject { |r| r.options[:required] }
          .each { |r| errgonomic_wrap_optional(r.name) }
      end

      # Every EachValidator fetches the attribute through here, so unwrapping
      # once at this seam is what lets the standard validators weigh the value
      # rather than the wrapper around it.
      #
      # @example presence weighs the value; some: asks only whether it is there
      #   Memo.new(title: Some(''), body: Some('')).tap(&:valid?).errors[:title] # => ["can't be blank"]
      #   Memo.new(title: Some(''), body: Some('')).tap(&:valid?).errors[:body] # => []
      def read_attribute_for_validation(key)
        Errgonomic::Rails.unwrap_option(super)
      end

      # Every attribute in a serialized payload is fetched through here, so a
      # converted model's as_json, to_json and serializable_hash say what the
      # unconverted one says. Rails writes an absent value as null, and so
      # does serde unless a field asks otherwise, so a None does too.
      #
      # @example
      #   note = Note.create!(title: Some('The Dark Forest'))
      #   Note.find(note.id).as_json['title'] # => 'The Dark Forest'
      #   Note.find(note.id).as_json.fetch('body') # => nil
      def read_attribute_for_serialization(key)
        Errgonomic::Rails.unwrap_option(super)
      end

      # A method named in methods: is read off the record rather than through
      # the attribute seam, so a wrapped reader named there arrives wrapped.
      #
      # @example
      #   Note.new(title: Some('Wanderer')).serializable_hash(only: [], methods: :title) # => { 'title' => 'Wanderer' }
      def serializable_hash(options = nil)
        hash = super
        Array(options.to_h[:methods]).each do |name|
          key = name.to_s
          hash[key] = Errgonomic::Rails.unwrap_option(hash[key]) if hash.key?(key)
        end
        errgonomic_omit_absent_keys(hash)
      end

      class_methods do
        # Wrapped readers live in a module of their own, the way ActiveRecord
        # keeps its attribute methods, so a model's own def of the same name
        # coexists with the wrapper instead of one silently replacing the
        # other. Included rather than prepended: the model's def wins, and
        # its super reads the Option.
        def errgonomic_optional_readers
          return @errgonomic_optional_readers if defined?(@errgonomic_optional_readers)

          @errgonomic_optional_readers = const_set(:ErrgonomicOptionalReaders, Module.new)
          private_constant :ErrgonomicOptionalReaders
          include @errgonomic_optional_readers
          @errgonomic_optional_readers
        end

        # Every class gets its module before its body runs, so where a reader
        # sits in the ancestor chain never depends on when the schema loads
        # or where the include was written.
        def inherited(subclass)
          super
          subclass.errgonomic_optional_readers
        end

        # What a model wrapped is the signal that a conversion did what it
        # meant to, and the columns are not wrapped until the schema loads, so
        # asking loads it.
        def errgonomic_optionals
          load_schema
          errgonomic_optional_names
        end

        # The set as it stands, for the wrapping itself: reaching for the
        # schema from here would ask the schema to load while it is loading.
        def errgonomic_optional_names
          @errgonomic_optional_names ||= []
        end

        # Read when a reader is about to be wrapped rather than snapshotted at
        # include time, so an exclusion works on either side of the include.
        # That is what an include on a base class needs: there is no "before"
        # for a model to declare anything in.
        def errgonomic_optional_exclusions
          inherited = if superclass.respond_to?(:errgonomic_optional_exclusions)
                        superclass.errgonomic_optional_exclusions
                      else
                        []
                      end

          inherited |
            Array(try(:errgonomic_optional_exceptions)).map(&:to_s) |
            errgonomic_nested_attribute_associations
        end

        # A wrapped reader whose absent value the declaration in force asks
        # to be left out of a payload rather than written as null.
        def errgonomic_serialize_none_omit?(name)
          declaration = errgonomic_serialize_none_declaration
          return false unless declaration && declaration[:mode] == :omit
          return declaration[:only].include?(name) if declaration[:only]
          return declaration[:except].exclude?(name) if declaration[:except]

          true
        end

        # A model that keeps value-or-nil throughout, for whatever the
        # application knows about it that the concern does not. Where the
        # concern is included on a base class, this is how a model leaves.
        def errgonomic_optional_off
          @errgonomic_optional_off = true
          errgonomic_unwrap_optionals(*errgonomic_optional_names.dup)
        end

        def errgonomic_optional_off?
          return true if defined?(@errgonomic_optional_off) && @errgonomic_optional_off

          superclass.respond_to?(:errgonomic_optional_off?) && superclass.errgonomic_optional_off?
        end

        # A reader wrapped by an ancestor is already an Option; a subclass
        # that wrapped it again would nest it.
        def errgonomic_optional?(name)
          return true if errgonomic_optional_names.include?(name)

          superclass.respond_to?(:errgonomic_optional?) && superclass.errgonomic_optional?(name)
        end

        # ActiveRecord defines its attribute methods the first time a model
        # needs its schema, not when the class body runs. Wrapping nullable
        # columns from the same seam keeps a database out of class loading.
        def load_schema!
          super
          errgonomic_wrap_nullable_columns
        end

        # A subclass loads its own schema, so whichever of the two is touched
        # first wraps the shared columns first, and a subclass that got there
        # first would wrap its parent's readers a second time. Walk the chain
        # from the top down instead, so an ancestor's readers always exist
        # before a subclass considers the same name.
        def errgonomic_wrap_nullable_columns
          superclass.errgonomic_wrap_nullable_columns if superclass.respond_to?(:errgonomic_wrap_nullable_columns)
          # An abstract class has no table, and asking one for its columns
          # raises. The concern belongs on an abstract class all the same: that
          # is where an application puts behaviour every model should have.
          return if abstract_class? || table_name.nil?

          column_names.each { |name| errgonomic_wrap_optional(name) if column_for_attribute(name).null }
        end

        # A concern belongs at the top of a model, above its associations, so
        # an optional belongs_to is routinely declared after the include.
        # Wrap it when it arrives, or the conversion is silently partial.
        def belongs_to(name, scope = nil, **options)
          super.tap { errgonomic_wrap_optional(name) if options[:optional] }
        end

        # A has_one is absent whenever no row points back at the record, so
        # its reader carries the same absence a nullable column does.
        # required: true is the exception: it asserts the record is there, and
        # absence is a validation failure rather than a value to handle.
        def has_one(name, scope = nil, **options)
          super.tap { errgonomic_wrap_optional(name) unless options[:required] }
        end

        # Nested attributes are assigned through the public reader, and
        # ActiveRecord asks whatever it finds there whether it is a new
        # record. An absent association has to arrive as nil for that, so a
        # singular association with nested attributes keeps its plain reader.
        def accepts_nested_attributes_for(*names, **options)
          super.tap { errgonomic_unwrap_optionals(*names) }
        end

        # ActiveRecord keeps its own register of these, so the exclusion can be
        # read from there rather than recorded as it goes past.
        def errgonomic_nested_attribute_associations
          return [] unless respond_to?(:nested_attributes_options)

          nested_attributes_options.keys.map(&:to_s).select do |name|
            %i[has_one belongs_to].include?(reflect_on_association(name)&.macro)
          end
        end

        def errgonomic_unwrap_optionals(*names)
          names.map(&:to_s).each do |name|
            next unless errgonomic_optional_names.delete(name)

            errgonomic_optional_readers.remove_method(name)
          end
        end

        def errgonomic_wrap_optional(name)
          name = name.to_s
          return if errgonomic_optional_off?
          return if errgonomic_optional_exclusions.include?(name) || errgonomic_optional?(name)

          errgonomic_optional_names << name
          errgonomic_optional_readers.module_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{name}
              reads = Thread.current[:errgonomic_optional_reads] ||= {}
              key = [object_id, :#{name}]
              if reads[key]
                raise Errgonomic::RecursiveOptionalReadError,
                      "\#{self.class}##{name} re-entered itself; something beneath this reader reads it again"
              end

              reads[key] = true
              begin
                val = super
              ensure
                reads.delete(key)
              end
              # One layer, always: an attribute or association is never an
              # optional of an optional, so an Option from beneath passes through.
              val.to_option
            end
          RUBY
        end
      end

      private

      # ActiveModel reads an included association off the record, so what it
      # yields is an Option. Take the record out of it, and leave an absent
      # one out of the payload, where a nil association is already left out.
      def serializable_add_includes(options = {})
        super do |association, records, opts|
          records = Errgonomic::Rails.unwrap_option(records)
          yield association, records, opts unless records.nil?
        end
      end

      # Deleting from the payload rather than from the attribute list is what
      # keeps the caller's own only: and except: in force. A wrapped reader
      # never holds Some(nil), so a nil here is the None it was declared for.
      def errgonomic_omit_absent_keys(hash)
        klass = self.class
        return hash unless klass.errgonomic_serialize_none_declaration&.fetch(:mode) == :omit

        hash.delete_if do |key, value|
          value.nil? && klass.errgonomic_optional?(key) && klass.errgonomic_serialize_none_omit?(key)
        end
      end
    end
  end
end

# Validates that an attribute is there at all, where presence asks whether it
# amounts to anything: an empty string is a value, nil and None are not.
# Lifting the value means the same question can be asked of a model the
# concern never converted.
class SomeValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, 'is invalid') unless value.to_option.some?
  end
end

module Errgonomic
  module Option
    # A belongs_to declared touch: true reads the associated record back
    # through the public reader after a save, then asks it to touch itself.
    class Some
      delegate :persisted?, to: :value
      delegate :touch_later, to: :value
    end

    # A None answers nil? like nil itself, so ActiveRecord internals that
    # check for nil treat an absent value as absent.
    class None
      def nil?
        true
      end
    end
  end
end

# Teach ActiveRecord type casting to unwrap Options: a Some casts as its
# inner value, a None casts as nil.
module ActiveRecordOptionShim
  def type_cast(value)
    case value
    when Errgonomic::Option::Some
      super(value.unwrap!)
    when Errgonomic::Option::None
      super(nil)
    else
      super
    end
  end
end

ActiveRecord::ConnectionAdapters::Quoting.prepend(ActiveRecordOptionShim)

# Lift nil into None.
class NilClass
  def to_option
    None()
  end
end

# Lift any other value into Some.
class Object
  def to_option
    Some(self)
  end
end

module Errgonomic
  module Option
    # An Option is already lifted. Lifting it again would nest it, and the
    # nesting is invisible until something reaches for the inner value.
    class Any
      def to_option
        self
      end
    end
  end
end

module Errgonomic
  module Rails
    # Teach ActiveRecord SQL quoting to unwrap Options, quoting a None as
    # SQL NULL.
    module ActiveRecordQuoting
      # @example
      #   ActiveRecord::Base.connection.quote(Some(1)) # => "1"
      #   ActiveRecord::Base.connection.quote(None()) # => "NULL"
      def quote(value)
        return super(value) unless value.is_a?(Errgonomic::Option::Any)

        value.map { |val| super(val) }
             .unwrap_or_else { super(nil) }
      end
    end
  end
end

ActiveRecord::ConnectionAdapters::Quoting.prepend(Errgonomic::Rails::ActiveRecordQuoting)

module Errgonomic
  module Rails
    # A hash condition never reaches the quoting layer as its raw value: the
    # predicate builder hands it to a bind attribute, which serializes it
    # through the column type and casts an unrecognized object to nil. Unwrap
    # one step earlier, where every hash condition passes, so a Some binds as
    # its inner value and a None as nil, which Arel renders as IS NULL.
    module ActiveRecordPredicateBuilder
      def build(attribute, value, *args)
        super(attribute, Errgonomic::Rails.unwrap_options(value), *args)
      end
    end

    # Take the value inside an Option at a boundary into ActiveRecord, and a
    # None as nil, reaching one level into an array so a list of Options
    # passes as a list of values.
    #
    # @example
    #   Errgonomic::Rails.unwrap_options(Some(1)) # => 1
    #   Errgonomic::Rails.unwrap_options(None()) # => nil
    #   Errgonomic::Rails.unwrap_options([Some(1), None()]) # => [1, nil]
    #   Errgonomic::Rails.unwrap_options(1) # => 1
    def self.unwrap_options(value)
      case value
      when Errgonomic::Option::Any
        value.unwrap_or(nil)
      when Array
        value.any? { |v| v.is_a?(Errgonomic::Option::Any) } ? value.map { |v| unwrap_options(v) } : value
      else
        value
      end
    end

    # Take the value inside an Option, and a None as nil, where the boundary
    # takes one value: an attribute is a single typed field, so a collection
    # that happens to hold an Option is that collection.
    #
    # @example
    #   Errgonomic::Rails.unwrap_option(Some(1)) # => 1
    #   Errgonomic::Rails.unwrap_option(None()) # => nil
    #   Errgonomic::Rails.unwrap_option([Some(1)]) # => [Some(1)]
    def self.unwrap_option(value)
      value.is_a?(Errgonomic::Option::Any) ? value.unwrap_or(nil) : value
    end

    # Unwrap each value of a hash one layer, where the boundary takes a row
    # or a set of conditions rather than a single value. A nested structure
    # is the caller's own, and is left as it is.
    #
    # @example
    #   Errgonomic::Rails.unwrap_option_values(title: Some('x'), body: None()) # => { title: 'x', body: nil }
    def self.unwrap_option_values(hash)
      hash.transform_values { |value| unwrap_option(value) }
    end

    # Unwrap each value of each row, where the boundary takes a list of rows.
    #
    # @example
    #   Errgonomic::Rails.unwrap_option_rows([{ title: Some('x') }]) # => [{ title: 'x' }]
    def self.unwrap_option_rows(rows)
      rows.map { |row| row.is_a?(Hash) ? unwrap_option_values(row) : row }
    end
  end
end

ActiveRecord::PredicateBuilder.prepend(Errgonomic::Rails::ActiveRecordPredicateBuilder)

module Errgonomic
  module Rails
    # A singular association writer is a setter, not a typed field, so it
    # takes what a wrapped reader hands back: Some(record) assigns the record,
    # None() clears the association. A Some of the wrong class still fails the
    # association's own type check, naming the class inside it.
    module ActiveRecordSingularAssociationWriter
      def writer(value)
        super(Errgonomic::Rails.unwrap_options(value))
      end
    end
  end
end

ActiveRecord::Associations::SingularAssociation.prepend(Errgonomic::Rails::ActiveRecordSingularAssociationWriter)

module Errgonomic
  module Rails
    # An attribute writer hands its value to a type cast that has never heard
    # of an Option, and each type fails its own way: a Some is truthy and not
    # one of ActiveModel's FALSE_VALUES, so a wrapped false cast to true.
    # Unwrap before the attribute is built rather than inside the cast, so the
    # value assigned, dirty tracking and the before-type-cast reader all agree
    # on what was assigned. Every writer passes here, as do new,
    # assign_attributes and update.
    module ActiveModelAttributeWrite
      # @example
      #   Note.new(pinned: Some(false)).pinned # => Some(false)
      #   Note.new(pinned: None()).pinned # => None()
      #   Note.new(title: Some('The Dark Forest')).title # => Some('The Dark Forest')
      #   Note.new(rank: Some(3)).rank # => Some(3)
      #   Note.new(due_on: Some(Date.new(2026, 7, 31))).due_on # => Some(Date.new(2026, 7, 31))
      #
      # @example A wrapper never reaches the attribute behind the reader
      #   Note.new(pinned: Some(false)).attributes['pinned'] # => false
      #   Note.new(pinned: Some(false)).read_attribute_before_type_cast('pinned') # => false
      def write_from_user(name, value)
        super(name, Errgonomic::Rails.unwrap_option(value))
      end
    end
  end
end

ActiveModel::AttributeSet.prepend(Errgonomic::Rails::ActiveModelAttributeWrite)

module Errgonomic
  module Rails
    # Every bind a query builds passes through a query attribute: the
    # predicate builder makes one per hash condition, and the statement
    # cache behind find, find_by and exists? substitutes its values into
    # one. Unwrapping at construction puts the Option ahead of the column
    # type, so a type that never calls super still sees a plain value.
    module ActiveRecordQueryAttribute
      # @example
      #   type = ActiveModel::Type::Integer.new
      #   ActiveRecord::Relation::QueryAttribute.new('rank', Some(3), type).value_before_type_cast # => 3
      #   ActiveRecord::Relation::QueryAttribute.new('rank', None(), type).value_before_type_cast # => nil
      def initialize(name, value_before_type_cast, *rest)
        super(name, Errgonomic::Rails.unwrap_option(value_before_type_cast), *rest)
      end
    end
  end
end

ActiveRecord::Relation::QueryAttribute.prepend(Errgonomic::Rails::ActiveRecordQueryAttribute)

module Errgonomic
  module Rails
    # find and find_by choose their path before any bind exists: an id or a
    # condition the statement cache cannot express is sent to the relation
    # instead. A None has to arrive as nil for that choice, so an absent
    # value asks for IS NULL rather than an equality that can never match.
    module ActiveRecordFind
      # A raw SQL condition is left alone, so an Option interpolated into one
      # still raises rather than binding quietly.
      #
      # @example
      #   note = Note.create!(body: 'Ball Lightning')
      #   Note.find_by(id: note.id, title: None()) == note # => true
      #   Note.find(Some(note.id)) == note # => true
      def find_by(*args)
        super(*args.map { |arg| arg.is_a?(Hash) ? Errgonomic::Rails.unwrap_option_values(arg) : arg })
      end

      def find(*ids, &block)
        super(*ids.map { |id| Errgonomic::Rails.unwrap_option(id) }, &block)
      end
    end
  end
end

ActiveRecord::Core::ClassMethods.prepend(Errgonomic::Rails::ActiveRecordFind)

module Errgonomic
  module Rails
    # A bulk write never passes an attribute writer: it casts and serializes
    # each value it was handed straight into the statement. Unwrapping the
    # row on the way in is what lets a Some cross that boundary whatever the
    # column type is. insert, insert! and upsert route through their plural
    # forms, so they are covered here too. A nested structure inside a value
    # is the caller's own and is left as it is.
    module ActiveRecordBulkWrite
      # @example
      #   Note.insert_all([{ title: Some('Wanderer'), rank: None() }])
      #   Note.where(title: 'Wanderer').update_all(rank: Some(3))
      #   Note.find_by(title: 'Wanderer').rank # => Some(3)
      def update_all(updates)
        super(updates.is_a?(Hash) ? Errgonomic::Rails.unwrap_option_values(updates) : updates)
      end

      def insert_all(attributes, **kwargs)
        super(Errgonomic::Rails.unwrap_option_rows(attributes), **kwargs)
      end

      def insert_all!(attributes, **kwargs)
        super(Errgonomic::Rails.unwrap_option_rows(attributes), **kwargs)
      end

      def upsert_all(attributes, **kwargs)
        super(Errgonomic::Rails.unwrap_option_rows(attributes), **kwargs)
      end
    end
  end
end

ActiveRecord::Relation.prepend(Errgonomic::Rails::ActiveRecordBulkWrite)

module Errgonomic
  module Rails
    # A declared default reaches the record's attribute without passing a
    # writer: it is held as given and cast the first time the attribute is
    # read. Unwrapping where it is declared is the only point above the type,
    # and it keeps the stored default a plain value, as an assigned one is.
    # A Proc default is left alone: what it returns is the application's.
    module ActiveModelAttributeDefault
      # @example
      #   DefaultedNote.new.rank # => 0
      #   DefaultedNote.new.title # => nil
      def attribute(name, type = nil, **options)
        options[:default] = Errgonomic::Rails.unwrap_option(options[:default]) if options.key?(:default)
        super(name, type, **options)
      end
    end
  end
end

ActiveModel::AttributeRegistration::ClassMethods.prepend(Errgonomic::Rails::ActiveModelAttributeDefault)
