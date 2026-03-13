# frozen_string_literal: true

require 'bundler/gem_tasks'

require 'rake/testtask'
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
end

require 'yard/doctest/rake'
YARD::Doctest::RakeTask.new do |task|
  task.doctest_opts = %w[-v]
  task.pattern = 'lib/**/*.rb'
end

task default: %i[test yard:doctest]
