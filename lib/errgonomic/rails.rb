require_relative 'option'
require_relative 'rails/active_record_optional'
require_relative 'rails/active_record_delegate_optional'

module Errgonomic
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

  # Hook into Rails with a Railtie
  class Railtie < ::Rails::Railtie
    initializer 'errgonomic.setup_before' do
      puts "errgonomic railtie initializer to_prepare setup_before"
      Errgonomic::Rails.setup_before
    end
    config.to_prepare do
      puts "errgonomic railtie config.to_prepare setup_after"
      Errgonomic::Rails.setup_after
    end
  end
end
