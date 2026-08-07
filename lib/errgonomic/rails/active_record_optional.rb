# frozen_string_literal: true

module Errgonomic
  module Rails
    # Concern to make ActiveRecord optional attributes and associations return an Option.
    #
    # Four pragmatic compromises below satisfy ActiveRecord's assumptions
    # about how accessors behave. They are deliberate exceptions to "Option
    # behaves like Rust's Option", and the set is closed: a fifth would be a
    # signal that ActiveRecord is pushing back somewhere unmapped, deserving
    # a design discussion rather than a quiet patch.
    #
    # 1. None#nil? answers true, so AR internals and ordinary nil checks
    #    treat an absent value as absent. Equality does not follow suit:
    #    None() == nil stays false.
    # 2. Some delegates persisted?, marked_for_destruction?, and touch_later
    #    to its record, so a Some can stand in for it during persistence.
    # 3. Two quoting prepends unwrap Options at the SQL boundary, so an
    #    Option can be passed to where/quote.
    # 4. SomeValidator provides a presence-style validation for Option
    #    attributes.
    module ActiveRecordOptional
      extend ActiveSupport::Concern

      included do
        # ::Rails.logger.debug('ActiveRecordOptional')
        optional_associations = reflect_on_all_associations(:belongs_to)
                                .select { |r| r.options[:optional] }
                                .map(&:name)
        excluded = Array(encrypted_attributes).map(&:to_s)
        optional_attributes = column_names
                              .select { |n| column_for_attribute(n).null }
                              .reject { |n| excluded.include?(n) }
        @errgonomic_optionals = (optional_attributes + optional_associations)
        @errgonomic_optionals.each do |name|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
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
              val.nil? ? Errgonomic::Option::None.new : Errgonomic::Option::Some.new(val)
            end
          RUBY
        end
      end

      class_methods do
        def errgonomic_optionals
          @errgonomic_optionals
        end

        # Encryption surrounds an attribute with machinery that reads the raw
        # value, including a length validator that calls to_s on it, so a
        # wrapped encrypted attribute cannot be saved. Declaring encrypts
        # after the include is the ordinary spelling, so catch it here too and
        # give the attribute its plain reader back.
        def encrypts(*names, **options)
          super.tap { errgonomic_unwrap_optionals(*names) }
        end

        def errgonomic_unwrap_optionals(*names)
          names.map(&:to_s).each do |name|
            next unless @errgonomic_optionals&.delete(name)

            remove_method(name)
          end
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
