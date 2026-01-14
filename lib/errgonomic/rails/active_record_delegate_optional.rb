# frozen_string_literal: true

module Errgonomic
  module Rails
    # A Rails Concern to introduce the +delegate_optional+ class method helper
    module ActiveRecordDelegateOptional
      extend ActiveSupport::Concern

      class_methods do
        # Like delegate, but for an optional attribute, using the Option #map
        # method to return a Some or None as appropriate.
        def delegate_optional(*methods, to: nil, prefix: nil, _private: nil)
          return if to.nil?

          methods.each do |method_name|
            prefixed_method_name = prefix == true ? "#{to}_#{method_name}" : method_name
            class_eval <<-RUBY, __FILE__, __LINE__ + 1
              def #{prefixed_method_name}
                #{to}.map { |obj| obj.send(:#{method_name}) }
              end
            RUBY
          end
        end
      end
    end
  end
end
