# Errgonomic

Errgonomic provides some lightweight, opinionated ergonomics for error handling in Ruby. These semantics are a blend of Rails `present?` conventions, and Rust `Option` and `Result` type combinators. Without going full Option and Result. Probably.

The `present_or` method takes what you might ordinarily write as `foo || default` with a possible nil or falsey value, and brings that to any other object that may be `blank?`.

```ruby
nil.present_or("default")
# => "default"

[].present_or(["default"])
# => ["default"]
```

We don't have static type checking here in Ruby, so the library is also _annoyingly_ pedantic about matching classes for the supplied default value.

```ruby
[].present_or("uh-oh")
# => Type mismatch: default value is a String but original was a Array (Errgonomic::TypeMismatchError)
```

When constructing that fallback object may be expensive, you can provide a block instead:

```ruby
[].present_or_else { ["default"] }
# => ["default"]
```

And when all else fails, you can control the failure, by raising an exception for blank objects. This can be preferable to sending a blank object to some other downstream code that may be expecting a value, causing an ambiguous failure.

```ruby
irb(main):007> [].present_or_raise("foo")
# => foo (Errgonomic::NotPresentError)
```

## Installation

TODO: Replace `errgonomic` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add errgonomic
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install errgonomic
```

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/omc/errgonomic. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/nz/errgonomic/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Errgonomic project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/nz/errgonomic/blob/main/CODE_OF_CONDUCT.md).
