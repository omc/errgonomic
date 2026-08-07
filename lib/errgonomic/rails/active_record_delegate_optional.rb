# frozen_string_literal: true

module Errgonomic
  module Rails
    # Adds a `delegate_optional` class method in the spirit of Rails'
    # `delegate`, returning an Option instead of nil or NoMethodError when
    # the delegation target is absent.
    module ActiveRecordDelegateOptional
      extend ActiveSupport::Concern

      class_methods do
        # Names attributes that ActiveRecordOptional must leave alone. It has
        # to be callable before the include, which is what computes the
        # wrapped set, so it lives here rather than in the concern itself.
        def errgonomic_optional_except(*names)
          @errgonomic_optional_exceptions = errgonomic_optional_exceptions + names.map(&:to_s)
        end

        def errgonomic_optional_exceptions
          @errgonomic_optional_exceptions ||= []
        end

        def delegate_optional(*methods, to: nil, prefix: nil, private: nil)
          return if to.nil?

          methods.each do |method_name|
            prefixed_method_name = prefix == true ? "#{to}_#{method_name}" : method_name
            class_eval <<-RUBY, __FILE__, __LINE__ + 1
              def #{prefixed_method_name}
                #{to}.map { |obj| obj.send(:#{method_name}) }
              end
            RUBY
            send(:private, prefixed_method_name) if private
          end
        end
      end
    end
  end
end
