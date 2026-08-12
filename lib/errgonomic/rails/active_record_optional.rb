# frozen_string_literal: true

module Errgonomic
  module Rails
    # Concern to make ActiveRecord optional attributes and associations return an Option.
    #
    # Five pragmatic compromises below satisfy ActiveRecord's assumptions
    # about how accessors behave. They are deliberate exceptions to "Option
    # behaves like Rust's Option", and the set is closed: a sixth would be a
    # signal that ActiveRecord is pushing back somewhere unmapped, deserving
    # a design discussion rather than a quiet patch.
    #
    # 1. None#nil? answers true, so AR internals and ordinary nil checks
    #    treat an absent value as absent. Equality does not follow suit:
    #    None() == nil stays false.
    # 2. Some delegates persisted?, marked_for_destruction?, and touch_later
    #    to its record, so a Some can stand in for it during persistence.
    # 3. Quoting and predicate-building prepends unwrap Options at the SQL
    #    boundary, so an Option can be passed to where/quote.
    # 4. SomeValidator provides a presence-style validation for Option
    #    attributes.
    # 5. Readers that ActiveRecord's own machinery reads raw are never
    #    wrapped: an attribute declared with encrypts, whose length validator
    #    sits outside Model.validators and calls to_s on the value, and a
    #    singular association with nested attributes, which are assigned
    #    through the reader and ask the value whether it is a new record.
    #
    # errgonomic_optional_except is not on the list: it is configuration, an
    # escape hatch for whatever conflict shows up next, not a semantic
    # exception.
    module ActiveRecordOptional
      extend ActiveSupport::Concern

      included do
        reflect_on_all_associations(:belongs_to)
          .select { |r| r.options[:optional] }
          .each { |r| errgonomic_wrap_optional(r.name) }
        reflect_on_all_associations(:has_one)
          .reject { |r| r.options[:required] }
          .each { |r| errgonomic_wrap_optional(r.name) }
      end

      class_methods do
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
            Array(encrypted_attributes).map(&:to_s) |
            Array(try(:errgonomic_optional_exceptions)).map(&:to_s) |
            errgonomic_nested_attribute_associations
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

        # Encryption surrounds an attribute with machinery that reads the raw
        # value, including a length validator that calls to_s on it, so a
        # wrapped encrypted attribute cannot be saved. Declaring encrypts
        # after the include is the ordinary spelling, and the exclusion is read
        # from ActiveRecord's own register when a reader is about to be
        # wrapped, so this only has to take back a reader already wrapped.
        def encrypts(*names, **options)
          super.tap { errgonomic_unwrap_optionals(*names) }
        end

        def errgonomic_unwrap_optionals(*names)
          names.map(&:to_s).each do |name|
            next unless errgonomic_optional_names.delete(name)

            remove_method(name)
          end
        end

        # The reader guards against re-entering itself with a flag on the
        # record. Bookkeeping shared across records would have to build a key
        # per read, and this reader is on the hot path of every wrapped
        # attribute. A record read from two threads at once is out of scope,
        # as it is for ActiveRecord itself.
        def errgonomic_wrap_optional(name)
          name = name.to_s
          return if errgonomic_optional_off?
          return if errgonomic_optional_exclusions.include?(name) || errgonomic_optional?(name)

          errgonomic_optional_names << name
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{name}
              if @__errgonomic_reading_#{name}
                raise Errgonomic::RecursiveOptionalReadError, <<~MSG
                  \#{self.class}##{name} re-entered itself; something beneath this reader reads it again.
                  If this read was not recursive, the record may have been read from two threads at once,
                  which this guard cannot tell apart. Please report that at
                  https://github.com/omc/errgonomic/issues
                MSG
              end

              @__errgonomic_reading_#{name} = true
              begin
                val = super
              ensure
                @__errgonomic_reading_#{name} = false
              end
              val.nil? ? Errgonomic::Option::None.new : Errgonomic::Option::Some.new(val)
            end
          RUBY
        end
      end
    end
  end
end

# Validates that an Option attribute is Some, analogous to a presence
# validation on a plain attribute.
class SomeValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, 'is invalid') unless value.some?
  end
end

module Errgonomic
  module Option
    # Delegate ActiveRecord lifecycle checks to the wrapped record, so a Some
    # can stand in for its record during persistence.
    class Some
      delegate :marked_for_destruction?, to: :value
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
  module Rails
    # Teach ActiveRecord SQL quoting to unwrap Options, quoting a None as
    # SQL NULL.
    module ActiveRecordQuoting
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

    # Unwrap Options in a query condition, reaching one level into an array
    # so a list of Options binds like a list of values.
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
  end
end

ActiveRecord::PredicateBuilder.prepend(Errgonomic::Rails::ActiveRecordPredicateBuilder)
