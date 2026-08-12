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
  # Expand here: the pattern reaches yard through a shell whose ** means *,
  # which silently dropped every doctest under lib/errgonomic/*/.
  task.pattern = FileList['lib/**/*.rb'].join(' ')
end

task default: %i[test yard:doctest]

namespace :benchmark do
  desc 'Cost of a wrapped attribute read, against the plain reader it replaces'
  task :optional_reader do
    ruby '-Ilib benchmark/optional_reader.rb'
  end
end

namespace :gems4nix do
  desc 'Regenerate gem-groups.json after Gemfile/Gemfile.lock changes'
  task :groups do
    require 'json'
    locked = JSON.parse(`nix flake metadata --json`).dig('locks', 'nodes', 'gems4nix', 'locked')
    ref = "github:#{locked['owner']}/#{locked['repo']}/#{locked['rev']}"
    src = JSON.parse(`nix flake prefetch --json #{ref}`).fetch('storePath')
    sh "ruby #{src}/lib/gemfile-env/gem-groups.rb > gem-groups.json"
  end
end
