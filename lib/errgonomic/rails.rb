require_relative 'option'
require_relative 'rails/active_record_optional'
require_relative 'rails/active_record_delegate_optional'

module Errgonomic
  # Rails specific functionality to integrate Errgonomic with minimum fuss.
  module Rails
    # We provide helper class methods, like `delegate_optional`,
    # which need to be included into ActiveRecord::Base before any models are
    # evaluated.
    def self.setup_before
      ActiveRecord::Base.include(Errgonomic::Rails::ActiveRecordDelegateOptional)
    end

    # Wrapping optional associations requires that we include the module after
    # the class is first evaluated, so that it can define its associations for
    # later reflection.
    def self.setup_after
      ActiveRecord::Base.descendants.each do |model|
        model.include Errgonomic::Rails::ActiveRecordOptional if model.table_name
      end
    end
  end
end

# TODO: Implement a Railtie to hook in the setup_before and setup_after at the
# appropriate times for the Rails application lifecycle, in dev and prod.
#
# if defined?(Rails::Railtie)
#   module Errgonomic::Rails
#     class Railtie < Rails::Railtie
#       initializer 'errgonomic.rails.setup_before' do
#         Errgonomic::Rails.setup_before
#       end
#       initializer 'errgonomic.rails.setup_after' do
#         Errgonomic::Rails.setup_after
#       end
#     end
#   end
# end
