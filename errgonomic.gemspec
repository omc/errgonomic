# frozen_string_literal: true

require_relative "lib/errgonomic/version"

Gem::Specification.new do |spec|
  spec.name = "errgonomic"
  spec.version = Errgonomic::VERSION
  spec.authors = ["Nick Zadrozny"]
  spec.email = ["nick@onemorecloud.com"]

  spec.summary = "Opinionated, ergonomic error handling for Ruby, inspired by Rails and Rust."
  spec.description = "Let's blend the Rails 'present' and 'blank' conventions with a few patterns from Rust Option types."
  spec.homepage = "https://omc.io/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/omc/errgonomic"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  spec.add_dependency "concurrent-ruby", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
