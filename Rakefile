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

namespace :test do
  desc 'Run the Rails integration suite with strict equality on'
  task :strict do
    ruby '-Ilib -Itest test/support/strict_equality.rb'
  end
end

# yard:doctest ends the process when it finishes, so anything after it in
# the default list would never run.
task default: %i[test test:strict yard:doctest]

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
