# Errgonomic

Errgonomic provides some lightweight, opinionated ergonomics for error handling in Ruby. These semantics are a blend of Rails `present?` conventions, and Rust `Option` and `Result` type combinators. Without going full Option and Result. Probably.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add errgonomic
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install errgonomic
```

Errgonomic requires Ruby >= 3.0.

## Usage

### Presence helpers

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
[].present_or_raise!("foo")
# => foo (Errgonomic::NotPresentError)
```

Each helper has a `blank_or*` counterpart for when you expect the object to be blank: `blank_or`, `blank_or_else`, `blank_or_raise!`.

### Type assertions

The same pattern applies to runtime type expectations:

```ruby
"hello".type_or_raise!(String)
# => "hello"

123.type_or_raise!(String)
# => Expected String but got Integer (Errgonomic::TypeMismatchError)

123.type_or(String, "default")
# => "default"

123.type_or_else(String) { "default" }
# => "default"

"hello".not_type_or_raise!(Integer)
# => "hello"
```

### Option

`Some(value)` and `None()` wrap a value that may or may not be there, with most of the Rust `Option` combinators:

```ruby
Some(1).unwrap!                  # => 1
None().unwrap!                   # => raises Errgonomic::UnwrapError
None().unwrap_or(2)              # => 2
None().unwrap_or_else { 2 }      # => 2
Some(1).expect!("must be set")   # => 1

Some(1).map { |x| x + 1 }        # => Some(2)
Some(2).and_then { |x| Some(x + 1) } # => Some(3)
None().or(Some(1))               # => Some(1)
Some(:left).xor(None())          # => Some(:left)
Some(1).zip(Some(2))             # => Some([1, 2])
Some(1).ok_or("nope")            # => Ok(1)
None().ok_or("nope")             # => Err("nope")
```

Options support pattern matching:

```ruby
case measurement
in Errgonomic::Option::Some, value
  "Measurement is #{value}"
in Errgonomic::Option::None
  "Measurement is not available"
end
```

An unhandled Option refuses to leak into your output: `to_s` and `to_json` raise `Errgonomic::SerializeError`, so you handle the inner value deliberately rather than shipping `#<Errgonomic::Option::Some...>` to a user.

### Result

`Ok(value)` and `Err(error)` express an operation that may fail, again with the Rust combinators:

```ruby
Ok(1).unwrap!                        # => 1
Err(:nope).unwrap!                   # => raises Errgonomic::UnwrapError
Err(:nope).unwrap_or(2)              # => 2

Ok(1).map { |x| x + 1 }              # => Ok(2)
Err(:bob).map_err { |e| e.capitalize } # => Err(:Bob)
Ok(1).and_then { |x| Ok(x + 1) }     # => Ok(2)
Err(:e).or_else { |e| Ok(1) }        # => Ok(1)

Ok(1).ok_and?(&:odd?)                # => true
Err(:a).err_and? { |_| true }        # => true
```

Results also pattern match, including against the kind of inner value:

```ruby
case result
in Errgonomic::Result::Ok, value
  "Measurement is #{value}"
in Errgonomic::Result::Err, String => msg
  "Measurement failed with a message: #{msg}"
in Errgonomic::Result::Err, Exception => e
  "Measurement produced an exception -- #{e.class}: #{e}"
end
```

Like Options, unwrapped Results refuse `to_s` and `to_json`. And `Object#result?` / `Object#assert_result!` help enforce at runtime that a value is a Result.

### Pedantic runtime checks

Combinators that accept a block (`and_then`, `or_else`, ...) check at runtime that the block returned an Option or Result, raising `Errgonomic::ArgumentError` otherwise. That beats an ambiguous `undefined method` error somewhere downstream. If you would rather have the ambiguous downstream errors, you can opt out — but not quietly:

```ruby
Errgonomic.with_ambiguous_downstream_errors do
  # anything goes in here
end
```

### Rails integration

When `Rails::Railtie` is defined, Errgonomic installs a Railtie with two opt-in integrations for ActiveRecord:

- `include Errgonomic::Rails::ActiveRecordOptional` in a model makes its nullable attributes and `optional: true` associations return `Some(value)` or `None()` instead of a value-or-nil.
- `delegate_optional :name, to: :association` (available on all models) delegates through an optional association, returning an Option instead of raising on nil.

`Object#to_option` is also available in Rails to lift any value into an Option (`nil.to_option # => None()`).

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment. The repository is a self-contained Nix flake; with direnv, `direnv allow` puts the right toolchain on your path.

This project encourages **red, green, refactor** when making changes. First, add or change a test that captures the desired behavior; next, run the tests to observe the failure message, confirming the test is useful; next, make the smallest code change(s) to make the test pass. Once tests pass, review your diff and look for opportunities to simplify or improve abstractions; make changes and iterate, running tests on each change to guard against regressions.

Most of the behavior above is specified as YARD doctests, so the examples in the code documentation are the test suite. Run them with:

```bash
nix develop -c rake yard:doctest
```

Run the full suite (unit tests plus doctests) with:

```bash
nix develop -c rake
```

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/omc/errgonomic. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/omc/errgonomic/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Errgonomic project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/omc/errgonomic/blob/main/CODE_OF_CONDUCT.md).
