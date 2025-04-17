# frozen_string_literal: true

module Errgonomic
  module Rails
    # Concern to make ActiveRecord optional attributes and associations return an Option.
    #
    module ActiveRecordOptional
      extend ActiveSupport::Concern
      included do
        # ::Rails.logger.debug('ActiveRecordOptional')
        optional_associations = reflect_on_all_associations(:belongs_to)
                                .select { |r| r.options[:optional] }
                                .map(&:name)
        optional_attributes = column_names
                              .select { |n| column_for_attribute(n).null }
        (optional_attributes + optional_associations).each do |name|
          # Rails.logger.debug("#{self.name}: #{name}: optional")
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{name}
          raise "stack too deep" if caller.length > 1024
          val = super
          val.nil? ? Errgonomic::Option::None.new : Errgonomic::Option::Some.new(val)
        end
          RUBY
        end
      end
    end
  end
end

# do we need this since we alias present below?
class SomeValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, 'is invalid') unless value.some?
  end
end

module Errgonomic
  module Option
    class Any
      alias some? present?
      alias none? blank?
    end

    class Some
      delegate :marked_for_destruction?, to: :value
      delegate :persisted?, to: :value
      delegate :touch_later, to: :value

      def to_s
        raise "Attempted to convert Some to String, please use Option API to safely work with internal value -- #{value}"
      end
    end

    class None
      def nil?
        true
      end

      def to_s
        raise 'Cannot convert None to String - please use Option API to safely work with internal value'
      end
    end
  end
end

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

class NilClass
  def to_option
    None()
  end
end

class Object
  def to_option
    Some(self)
  end
end
