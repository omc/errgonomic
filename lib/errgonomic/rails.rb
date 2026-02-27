require_relative 'option'
require_relative 'rails/active_record_optional'
require_relative 'rails/active_record_delegate_optional'

require 'rails/railtie'

module Errgonomic
  # Slightly more convenient access to the setup functions:
  # Errgonomic::Rails.setup_before and Errgonomic::Rails.setup_after
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
      # todo
    end
  end

  # Hook into Rails with a Railtie
  class Railtie < ::Rails::Railtie
    initializer 'errgonomic.setup_before' do
      Errgonomic::Rails.setup_before
    end
    config.after_initialize do
      ActiveSupport.on_load(:after_initialize) do
        Errgonomic::Rails.setup_after
      end
    end
    config.to_prepare do
      Errgonomic::Rails.setup_after
    end
  end
end
