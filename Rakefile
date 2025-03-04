# frozen_string_literal: true

require 'bundler/gem_tasks'

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

require 'yard/doctest/rake'
YARD::Doctest::RakeTask.new do |task|
  task.doctest_opts = %w[-v]
  task.pattern = 'lib/**/*.rb'
end

task default: %i[spec yard:doctest]
