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

`unwrap!` and `expect!` are for tests and consoles, not application code: they raise on `None`, which is exactly the ambiguous failure the type exists to prevent. Application code should always have a combinator or pattern match that handles the `None` branch explicitly; if none fits, that is a gap worth an issue rather than a reason to unwrap.

Presence follows the discriminant, as in Rust: `Some` is `present?` and `None` is `blank?`, regardless of the wrapped value. So `Some(false).present?` and `Some(nil).present?` are both `true`. If you care about the inner value's own presence, unwrap it first.

Equality is between Options only: `Some(5) == Some(5)`, but `Some(5) == 5` and `None() == nil` are `false`. That is quiet, never an error, matching how every Ruby object compares across types. Rust rejects `Some(5) == 5` at compile time; Ruby cannot, so guard the idiom in review and tests: compare against a wrapped value (`opt == Some(5)`) or test the inner value (`opt.some_and? { |v| v == 5 }`).

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

### Optional collections

Hash and Array gain two additive lookups each, and nothing else changes about them. `fetch_option` follows presence the way Rust's `HashMap#get` and slice `get` do: a present key or index holding `nil` is `Some(nil)`, and only a missing one is `None()`.

```ruby
h = { color: :blue, shade: nil }
h.fetch_option(:color)  # => Some(:blue)
h.fetch_option(:shade)  # => Some(nil)
h.fetch_option(:smell)  # => None()

[:a, nil].fetch_option(1)  # => Some(nil)
[:a, nil].fetch_option(2)  # => None()
```

`into_optional` wraps the collection in `Errgonomic::OptionalHash` / `Errgonomic::OptionalArray`, a view whose lookups all return Options. The wrappers are deliberately small — `[]`, `[]=`, `dig`, presence checks, and (for arrays) `first`/`last` — and are composed around the plain collection rather than subclassing it, because a subclass sheds its custom semantics every time `select` or `transform_values` returns a plain Hash. `to_h` / `to_a` hand back a detached copy.

```ruby
h = { person: { name: 'Ada', middle_name: nil } }.into_optional
h.dig(:person, :name)         # => Some("Ada")
h.dig(:person, :middle_name)  # => Some(nil)   (present, holding nil)
h.dig(:person, :nickname)     # => None()      (absent)

[].into_optional.first        # => None()
```

`dig` checks presence at every step, so an absent path and a present `nil` stay distinguishable, which core `dig` conflates. Digging into a non-collection raises `Errgonomic::TypeMismatchError` rather than answering `None()`, in the gem's pedantic style.

### Booleans

Booleans lift into the containers, following Rust's `bool`: `then_some`, and `ok_or`/`ok_or_else` from nightly. Rust splits the lazy form into `then`, but that name is core Ruby (`Kernel#then`), which Errgonomic will not redefine; `then_some` takes either a value or a block instead. Rust's `ok_or` returns `Result<(), E>`; Ruby has no unit type, so `Ok` carries `true`.

```ruby
admin.then_some(:badge)       # => Some(:badge) when true, None() when false
admin.then_some { badge! }    # lazy variant
valid.ok_or("invalid input")  # => Ok(true) / Err("invalid input")
```

### Pedantic runtime checks

Combinators that accept a block (`and_then`, `or_else`, ...) check at runtime that the block returned an Option or Result, raising `Errgonomic::ArgumentError` otherwise. That beats an ambiguous `undefined method` error somewhere downstream. If you would rather have the ambiguous downstream errors, you can opt out — but not quietly:

```ruby
Errgonomic.with_ambiguous_downstream_errors do
  # anything goes in here
end
```

### Rails integration

When `Rails::Railtie` is defined, Errgonomic installs a Railtie with two opt-in integrations for ActiveRecord:

- `include Errgonomic::Rails::ActiveRecordOptional` in a model makes its nullable attributes and `optional: true` associations return `Some(value)` or `None()` instead of a value-or-nil. Every nullable column and optional association is wrapped, with no per-attribute opt-in. Two kinds of attribute stay unwrapped: those declared with `encrypts`, whose surrounding machinery reads the raw value, and those named by `errgonomic_optional_except`, which must appear before the include.

```ruby
class Credential < ApplicationRecord
  errgonomic_optional_except :legacy_token
  include Errgonomic::Rails::ActiveRecordOptional

  encrypts :access_secret   # also left unwrapped, declared either side of the include
end
```
- `delegate_optional :name, to: :association` (available on all models) delegates through an optional association, returning an Option instead of raising on nil.

`Object#to_option` is also available in Rails to lift any value into an Option (`nil.to_option # => None()`).

#### ActiveRecord compromises

ActiveRecord assumes things about accessors that a strict Rust Option cannot satisfy, so the integration carries five deliberate compromises. Everywhere else, treat a departure from Rust's `Option` semantics as a bug; these five are intended:

1. `None#nil?` answers `true`, so ActiveRecord internals and ordinary `.nil?` checks treat an absent value as absent. Equality does not follow suit: `None() == nil` is still `false`.
2. `Some` delegates `persisted?`, `marked_for_destruction?`, and `touch_later` to its record, so a `Some` can stand in for its record during persistence.
3. Quoting is patched so an `Option` passed into `where`/`quote` is unwrapped at the SQL boundary.
4. `SomeValidator` provides a presence-style validation for Option attributes.
5. Attributes declared with `encrypts` are never wrapped: ActiveRecord Encryption's own machinery (a length validator it registers outside `Model.validators`) reads the raw value and cannot survive an Option.

The set is closed. If a future integration appears to need a sixth compromise, that is a signal ActiveRecord is pushing back somewhere unmapped, and it warrants a design discussion rather than a quiet patch. `errgonomic_optional_except` is deliberately not on the list: it is configuration, an escape hatch that softens the all-or-nothing include for whatever conflict shows up next, rather than a semantic exception.

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
