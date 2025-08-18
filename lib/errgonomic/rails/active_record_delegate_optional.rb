module Errgonomic
  module Rails
    module ActiveRecordDelegateOptional
      extend ActiveSupport::Concern

      class_methods do
        def delegate_optional(*methods, to: nil, prefix: nil, private: nil)
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
