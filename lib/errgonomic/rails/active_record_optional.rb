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
    #    None() == nil stays false. Nor does Array#compact, the common
    #    collection idiom for dropping absent members: it tests for the
    #    nil object, so it keeps a None where reject(&:none?) drops it.
    # 2. Some delegates persisted? and touch_later to its record, so a Some
    #    can stand in for it where ActiveRecord reads an association back
    #    through its public reader.
    # 3. Boundaries into ActiveRecord unwrap Options where a value enters,
    #    above the column type in every case: quoting and predicate building
    #    at the SQL boundary, attribute and singular association writers on
    #    assignment, the ids and conditions find, find_by and a bulk write
    #    are given, and an attribute default where it is declared.
    # 4. SomeValidator asks whether a value is there at all, where presence
    #    asks whether it amounts to anything: Some("") passes some: true and
    #    fails presence. It lifts what it is handed, so it asks the same
    #    question of any model, converted or not.
    # 5. Where the framework's own machinery reads a value raw, it gets one.
    #    Validation unwraps at read_attribute_for_validation, the seam every
    #    EachValidator fetches an attribute through; serialization at
    #    read_attribute_for_serialization, the seam every attribute in a
    #    payload is fetched through; and a form helper at ActionView's tag
    #    value, the seam every field reads its record through. So a standard
    #    validator weighs the value, a payload carries it and a form renders
    #    it, rather than the wrapper. A singular association with nested
    #    attributes goes further and keeps its plain reader: nested attributes
    #    are assigned through the reader, and ActiveRecord asks whatever it
    #    finds there whether it is a new record. So does a reader a framework
    #    macro declares and then reads for itself: the associations behind
    #    has_rich_text and has_one_attached, and the digest column
    #    has_secure_password hands to BCrypt.
    #
    # errgonomic_optional_except and errgonomic_serialize_none are not on the
    # list: they are configuration, an escape hatch for whatever conflict
    # shows up next and a choice of how an absent value is written, not
    # semantic exceptions.
    module ActiveRecordOptional
      extend ActiveSupport::Concern

      # The singular associations ActionText and ActiveStorage declare for a
      # model and then read through code of their own. Recognized by the name
      # a reflection was given rather than by the class, so nothing has to be
      # loaded for a model to be asked.
      FRAMEWORK_ASSOCIATION_CLASSES = %w[
        ActionText::RichText
        ActionText::EncryptedRichText
        ActiveStorage::Attachment
        ActiveStorage::Blob
      ].freeze

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

      # YARD does not see through a concern's class_methods block, so the
      # method it documents is declared rather than read.
      #
      # @!method errgonomic_optionals
      #   @!scope class
      #   The readers a model wrapped, which is how a conversion is checked.
      #   @example a reader the framework reads for itself is left alone
      #     Dispatch.errgonomic_optionals.include?('rich_text_body') # => false
      #     Dispatch.errgonomic_optionals.include?('title') # => true
      #   @example a subclass reports the readers it inherited
      #     Briefing.errgonomic_optionals # => ['title', 'summary']
      #     Briefing.errgonomic_optional_names # => []
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
        # asking loads it. A subclass responds to every reader an ancestor
        # wrapped, so the report names those too.
        def errgonomic_optionals
          load_schema
          errgonomic_inherited_optional_names | errgonomic_optional_names
        end

        # Wrapping walks the chain from the top down, so loading this class's
        # schema has already wrapped an ancestor's columns and reading the
        # names is enough. An abstract ancestor is never asked for a table it
        # has not got.
        def errgonomic_inherited_optional_names
          return [] unless superclass.respond_to?(:errgonomic_optional_names)

          superclass.errgonomic_inherited_optional_names | superclass.errgonomic_optional_names
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
            errgonomic_nested_attribute_associations |
            errgonomic_framework_readers
        end

        # Readers the framework reads for itself, whatever the model asked
        # for. ActionText and ActiveStorage reach their records through the
        # associations their macros declare, and has_secure_password hands
        # the digest column to BCrypt, none of them through anything that has
        # heard of an Option: a wrapper there breaks assignment, attachment
        # and authentication alike.
        def errgonomic_framework_readers
          errgonomic_framework_associations + errgonomic_secure_password_digests
        end

        def errgonomic_framework_associations
          reflect_on_all_associations(:has_one)
            .select { |r| FRAMEWORK_ASSOCIATION_CLASSES.include?(r.class_name) }
            .map { |r| r.name.to_s }
        end

        # has_secure_password includes a module of its own per attribute, and
        # the authenticate_ reader in it names the attribute whose digest is
        # read. Asking the macro what it declared costs no schema, which a
        # column scan would load while a class body is still running.
        def errgonomic_secure_password_digests
          return [] unless defined?(ActiveModel::SecurePassword::InstanceMethodsOnActivation)

          ancestors.grep(ActiveModel::SecurePassword::InstanceMethodsOnActivation)
                   .flat_map { |mod| mod.instance_methods(false).grep(/\Aauthenticate_/) }
                   .map { |name| "#{name.to_s.delete_prefix('authenticate_')}_digest" }
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

        # A digest column is ordinarily wrapped after this declaration, and
        # the exclusion is enough there. A model whose schema has already
        # loaded has to be handed its reader back. has_rich_text and
        # has_one_attached need no such override: they declare their
        # associations through has_one, which reads the exclusion after the
        # reflection exists.
        def has_secure_password(attribute = :password, **options)
          super.tap { errgonomic_unwrap_optionals("#{attribute}_digest") }
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

      # ActiveSupport's Object#try asks respond_to?, which an Option answers
      # false for anything it does not define, so try on a wrapper would be a
      # quiet nil for every method. Send it to the value instead: a Some
      # tries what it holds, a None is absent and answers nil, and a method
      # the value does not have is nil as it is for any other receiver.
      #
      # @example
      #   Some("bob").try(:upcase) # => "BOB"
      #   Some("bob").try(:no_such_method) # => nil
      #   None().try(:upcase) # => nil
      #   Some(2).try { |pages| pages * 3 } # => 6
      #   None().try { |pages| pages * 3 } # => nil
      def try(...)
        return nil if none?

        value.try(...)
      end

      # Rails' strict variant: absence is still nil, a method the value does
      # not have raises.
      #
      # @example
      #   Some("bob").try!(:upcase) # => "BOB"
      #   None().try!(:upcase) # => nil
      #   begin
      #     Some("bob").try!(:no_such_method)
      #   rescue NoMethodError => e
      #     e.class
      #   end # => NoMethodError
      def try!(...)
        return nil if none?

        value.try!(...)
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
      when Errgonomic::Option::Any, Errgonomic::VariantName
        unwrap_option(value)
      when Array
        value.any? { |v| unwrapped_at_boundary?(v) } ? value.map { |v| unwrap_options(v) } : value
      else
        value
      end
    end

    # Take the value inside an Option, and a None as nil, where the boundary
    # takes one value: an attribute is a single typed field, so a collection
    # that happens to hold an Option is that collection. A bare variant name
    # is refused here, since a boolean column would cast it to true.
    #
    # @example
    #   Errgonomic::Rails.unwrap_option(Some(1)) # => 1
    #   Errgonomic::Rails.unwrap_option(None()) # => nil
    #   Errgonomic::Rails.unwrap_option([Some(1)]) # => [Some(1)]
    #   Errgonomic::Rails.unwrap_option(None) # => raise Errgonomic::SerializeError, "bare None names a variant for a pattern, not a value; build one with parentheses"
    def self.unwrap_option(value)
      value.refuse! if value.is_a?(Errgonomic::VariantName)
      value.is_a?(Errgonomic::Option::Any) ? value.unwrap_or(nil) : value
    end

    # Unwrap each value of a hash one layer, where the boundary takes a row
    # or a set of conditions rather than a single value. A nested structure
    # is the caller's own, and is left as it is. A hash holding no Option is
    # handed back rather than copied: every write passes here, and most carry
    # none.
    #
    # @example
    #   Errgonomic::Rails.unwrap_option_values(title: Some('x'), body: None()) # => { title: 'x', body: nil }
    #   plain = { title: 'x' }
    #   Errgonomic::Rails.unwrap_option_values(plain).equal?(plain) # => true
    def self.unwrap_option_values(hash)
      return hash unless hash.each_value.any? { |value| unwrapped_at_boundary?(value) }

      hash.transform_values { |value| unwrap_option(value) }
    end

    # Unwrap each value of each row, where the boundary takes a list of rows.
    # A list holding no Option is handed back rather than copied.
    #
    # @example
    #   Errgonomic::Rails.unwrap_option_rows([{ title: Some('x') }]) # => [{ title: 'x' }]
    #   plain = [{ title: 'x' }]
    #   Errgonomic::Rails.unwrap_option_rows(plain).equal?(plain) # => true
    def self.unwrap_option_rows(rows)
      return rows unless rows.any? { |row| row.is_a?(Hash) && row.each_value.any? { |v| unwrapped_at_boundary?(v) } }

      rows.map { |row| row.is_a?(Hash) ? unwrap_option_values(row) : row }
    end

    # An Option, or a bare variant name, which a boundary refuses rather than
    # let a column type cast it.
    def self.unwrapped_at_boundary?(value)
      value.is_a?(Errgonomic::Option::Any) || value.is_a?(Errgonomic::VariantName)
    end

    # A declared default that is a Proc is not a value yet: ActiveModel calls
    # it with no arguments each time a record is built. Wrap it rather than
    # unwrap it, so what it returns meets the type where a literal default
    # already does.
    #
    # @example
    #   Errgonomic::Rails.unwrap_option_default(Some(1)) # => 1
    #   Errgonomic::Rails.unwrap_option_default(-> { Some(1) }).call # => 1
    def self.unwrap_option_default(default)
      return unwrap_option(default) unless default.is_a?(Proc)

      -> { unwrap_option(default.call) }
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

      # A list of ids is a list of values, so it unwraps one level in: find
      # casts each id it was handed after the query has run, and a wrapper
      # reaching a string primary key's type raises there.
      #
      # @example
      #   first = Note.create!(title: 'Supernova Era')
      #   second = Note.create!(title: 'Ball Lightning')
      #   Note.find([Some(second.id), Some(first.id)]) == [second, first] # => true
      def find(*ids, &block)
        super(*ids.map { |id| Errgonomic::Rails.unwrap_options(id) }, &block)
      end
    end

    # A relation and an association reach find without passing the class
    # method, so the same list has to be unwrapped there as well.
    module ActiveRecordRelationFind
      # @example
      #   note = Note.create!(title: 'Death\'s End')
      #   Note.where.not(title: nil).find([Some(note.id)]) == [note] # => true
      def find(*ids, &block)
        super(*ids.map { |id| Errgonomic::Rails.unwrap_options(id) }, &block)
      end
    end
  end
end

ActiveRecord::Core::ClassMethods.prepend(Errgonomic::Rails::ActiveRecordFind)
ActiveRecord::Relation.prepend(Errgonomic::Rails::ActiveRecordRelationFind)

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
    module ActiveModelAttributeDefault
      # @example
      #   DefaultedNote.new.rank # => 0
      #   DefaultedNote.new.title # => nil
      #   ProcDefaultedNote.new.title # => 'Wanderer'
      def attribute(name, type = nil, **options)
        options[:default] = Errgonomic::Rails.unwrap_option_default(options[:default]) if options.key?(:default)
        super(name, type, **options)
      end
    end
  end
end

ActiveModel::AttributeRegistration::ClassMethods.prepend(Errgonomic::Rails::ActiveModelAttributeDefault)

module Errgonomic
  module Rails
    # A form helper reads its value off the record through the public reader
    # whenever the value did not come from user input, which is every record
    # an edit form loads from the database. Each tag then weighs what it finds
    # its own way: a check box asks it for to_i, a datetime field for
    # strftime, and a text field renders it into the markup. Unwrapping at the
    # one seam they all read through is what lets a converted model render the
    # form an unconverted one renders.
    module ActionViewTagValue
      private

      def value
        Errgonomic::Rails.unwrap_option(super)
      end
    end
  end
end

# ActionView may be loaded before this file, after it, or not at all, and the
# load hook answers for all three.
ActiveSupport.on_load(:action_view) do
  ActionView::Helpers::Tags::Base.prepend(Errgonomic::Rails::ActionViewTagValue)
end
