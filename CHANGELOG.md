## [Unreleased]

## [0.10.0] - 2026-09-10

This release gives `deconstruct` the Rust shape and names the four variants at top level, so a pattern reads as `in Some(v)`.

### Upgrading from 0.9.3

`deconstruct` answers `[value]` for a `Some`, an `Ok` and an `Err` and `[]` for a `None`, so a pattern written against 0.9.x's `[self, value]` has to change shape: `in Errgonomic::Option::Some, v` becomes `in Some(v)`, `in Errgonomic::Result::Err, String => msg` becomes `in Err(String => msg)`, and `in Errgonomic::Option::None` stays as it is or becomes `in None`. `Some`, `None`, `Ok` and `Err` are now top-level constants for the four classes as well as constructors. An application that defines its own constant under one of those names has to rename it.

### Changes

- [Behavior change] `deconstruct` answers `[value]` for a `Some`, an `Ok` and an `Err` and `[]` for a `None`, the one-payload shape `Data.define(:value)` and Rust's tuple variants share, where 0.9.x answered `[self, value]` and `[None]`. `in Some(v)` binds the value, `in Ok(Some(v))` nests, a two-branch `case/in` with no `else` is exhaustive, and a wrong type reaches `NoMatchingPatternError`. There is no `deconstruct_keys`: a one-payload sum type has no named field, and a `Some` around a Hash nests as `in Some({ id: })` through the Hash's own protocol
- A value-less `Err()` deconstructs to `[]`, so `in Err` and `in Err()` match it and `in Err(e)` matches only an `Err` that carries a value. The sentinel `Err()` holds in place of a value is internal, and a pattern variable must never bind it
- `Some`, `None`, `Ok` and `Err` are defined as top-level constants for the four classes, beside the constructors of the same name, so a pattern reads as it does in Rust. Rails defines none of the four

## [0.9.3] - 2026-09-10

This release removes the public `value` slot from `Some`, `Ok` and `Err`, and freezes every instance as it is constructed, so an Option or a Result is the value the README already said it was.

### Upgrading from 0.9.2

`value` and `value=` are gone from `Some`, `Ok` and `Err`, and every instance is frozen as it is constructed. A read of `.value` becomes `unwrap_or(fallback)`, `expect!(message)`, `map`, `and_then` or a pattern, each of which names the other branch; a write of `.value=` becomes a new `Some(v)` assigned where the old one lived. A call to either now raises `Errgonomic::UnwrappedAccessError`, which is a `NoMethodError`, naming the combinators.

### Changes

- [Behavior change] `Some`, `Ok` and `Err` no longer expose `value` or `value=`, and every Option and Result is frozen as it is constructed, whether by `Some`, `None`, `Ok`, `Err`, `new` or a combinator; `clone` keeps it frozen. A copy that skips construction, from `dup`, `Marshal.load`, a YAML load or ActiveSupport's `deep_dup`, is not frozen; with no writer, it changes only through `instance_variable_set`. The reader reached the inner value with no `None` branch, the writer mutated a wrapper through an alias and moved a Hash key out from under its own bucket, and the README already said an Option is a value rather than a slot. The reader is protected, for the sibling reads equality, ordering and `zip` need; a call from outside gets the combinator teaching `Errgonomic::UnwrappedAccessError` gives any other miss

## [0.9.2] - 2026-09-10

This release makes `Option#and`, `#xor`, `#zip` and `#zip_with` check their operand the way `or` already did.

### Upgrading from 0.9.1

`Option#and`, `#xor`, `#zip` and `#zip_with` raise `Errgonomic::ArgumentError` on a bare operand, on a `None` receiver as well as a `Some`. Code that passed a bare value to `and` and read it back has to wrap it.

### Changes

- [Behavior change] `Option#and`, `#xor`, `#zip` and `#zip_with` check their operand the way `or` already did, raising `Errgonomic::ArgumentError` (`other must be an Option, was Integer`) before the receiver's variant is consulted. 0.9.x let `Some(2).and(3)` hand back the bare `3`, let `None().and(3)` and `None().zip(2)` accept the operand silently, and let `Some(1).zip(2)` and `Some(:l).xor(:r)` fall into a bare `NoMethodError` on `some?` or `none?`

## [0.9.1] - 2026-09-10

This release reverts the 0.9.0 change that made `to_s` render an Option or a Result. The raise is back, with a message that says what to call instead.

### Upgrading from 0.9.0

`to_s` on an Option or a Result raises `Errgonomic::SerializeError` again, so a string built from a wrapped reader fails where it is built rather than writing `Some("...")` or `None` into it. Code written against 0.9.0's rendering, whether a string interpolation, an `Array#join`, a `format`, a `String()` or a bare ERB `<%= %>`, has to take the value first: `unwrap_or` or `expect!` for the value, or `inspect` for a log line. A `rescue` that interpolates a wrapper into its message writes `inspect` there. A `rescue Errgonomic::SerializeError` written against 0.8.x still matches. A `logger.info(opt)` that rendered through 0.9.0 still renders through a plain `Logger`, but raises under Rails' `TaggedLogging` once a tag such as `request_id` is set, so it can pass in tests and raise in production: write `logger.info(opt.inspect)`. The README's Option section describes this and a `case/in` that matches nothing on a wrapper, whose `NoMatchingPatternError` no longer prints its subject.

### Changes

- [Behavior change] `to_s` on an Option or a Result raises `Errgonomic::SerializeError` where 0.9.0 rendered it as `inspect` does. The message names the value with its `inspect`, bounded to 60 characters, says `to_s` is refused, and names `inspect` for a log line and `unwrap_or` / `expect!` for the value: `Some(1) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value`. 0.9.0's rendering wrote wrapper text into data at every site that built a string from a wrapped reader, with no exception to find the site by: a UNIQUE identity column, a hostname, a hashed auth token and a customer-facing page. A raise that names the remedy serves the log-line case 0.9.0 traded for, and `inspect` is unchanged
- An Option or a Result in a Hash key raises on its way to JSON again. The json gem and ActiveSupport's `as_json` both stringify a key with `to_s`, so 0.9.0's rendering let `{ Some(1) => 2 }.as_json` write `{"Some(1)" => 2}` where a value position had always raised
- `Result#unwrap_err!` on an `Ok` raises an `Errgonomic::UnwrapError` whose message is the Ok's value as `inspect` renders it, bounded to 60 characters, and whose `value` is the value itself. The message used to be the value's `to_s`, so once `to_s` refuses, `Ok(Some(1)).unwrap_err!` printed only the class name and its `message` raised. A String value is quoted in the message, as `inspect` quotes it

## [0.9.0] - 2026-09-08

This release turns the ActiveRecord integration from a set of wrapped readers into a full set of boundaries, covering readers, writers, query binds, validation and serialization, with the behavior changes named in the bullets below.

### Upgrading from 0.8.x

A model's own `def` of a wrapped column or association reader now composes with the wrapper rather than replacing it or being replaced by it, and `super` inside that override returns the Option. An override written as `super || fallback` no longer falls back, because a `None` is truthy. Keep the Option and write `super.or_else { Some(fallback) }`, or hand the bare value back from a differently named accessor as `super.unwrap_or(fallback)`, which is the override convention the README states. Sweep the models for every `def` that names a wrapped reader and calls `super` in its body.

An attribute declared with `encrypts` is wrapped like any other nullable column, where 0.8.x excluded it from the conversion. Every read of one now answers an Option, so a truthiness idiom such as `secret ||= SecureRandom.hex` is a no-op against a `None` rather than the assignment it looks like. Sweep the reads of encrypted attributes for `||`, `||=` and `if attr`.

Several behaviors that 0.8.x code may lean on have changed. `to_s` on an Option or a Result renders instead of raising, `map_or` and `map_or_else` answer the bare value their default or block gives rather than wrapping it, and `Some` no longer delegates `marked_for_destruction?` to its record. An adapter's `type_cast` and a column type's `cast` and `serialize` no longer unwrap, because a value is unwrapped where it enters ActiveRecord instead, so code that reached `Type::Value#cast(Some(x))` directly has to unwrap the value first. An application's own `EachValidator` on a converted model is handed the inner value where 0.8.x handed it the Option.

`delegate_optional` calls the target method directly rather than sending to it, so a private or protected method on the target no longer delegates. A declaration whose `to:` is missing or `nil` raises where it is written, and a writer such as `delegate_optional :name=, to: :author` is refused.

### Changes


- `ActiveRecordOptional` installs its wrapped readers into a per-class module, so a model's own reader of the same name composes with the wrapper through `super` instead of one silently replacing the other
- A wrapped reader lifts a value exactly one layer: an Option arriving from beneath the wrapper passes through instead of being wrapped a second time
- An attribute declared with `encrypts` is wrapped like any other nullable column, now that the encryption length validator reads it through the validation seam. It round-trips as an Option, a `deterministic: true` attribute stays queryable, and `downcase:` still normalizes on write
- A reader a framework macro declares and then reads for itself is excluded from the wrapping automatically, wherever the macro is written: the `has_one` associations behind `has_rich_text` and `has_one_attached`, and the digest column `has_secure_password` hands to BCrypt. Wrapping them broke `body=`, `to_plain_text`, an attachment's own readers and `authenticate`, none of which passes through a seam that has heard of an Option. The associations are recognized by the class name their reflection carries, so neither engine has to be loaded to answer, and the digest by the module `has_secure_password` includes for the attribute, so a second `has_secure_password :recovery_password` is covered too
- `Model.errgonomic_optionals` on a subclass reports the readers it inherited along with anything it wrapped itself, where an STI subclass used to report nothing at all while responding to every wrapped reader its parent declared. `Model.errgonomic_optional_names` stays the set that class wrapped on its own
- `belongs_to` and `has_one` writers accept an Option: `Some(record)` assigns the record it wraps and `None()` clears the association, so a wrapped reader can be assigned straight onto another record
- An attribute writer accepts an Option and stores the value inside it, `None()` storing `nil`, for every column type: `record.pinned = Some(false)` stores `false` where it used to store `true`, string, text, json, date and datetime writers no longer raise, and the numeric writers no longer route through the soft-deprecated `Option#presence`. Dirty tracking, `attributes` and the before-type-cast reader see the raw value
- An `attribute :col, type, default: Some(v)` declaration unwraps its default where it is written, so the stored default is a plain value whatever the type is, as an assigned one is. A `Proc` default is wrapped rather than unwrapped, so `default: -> { Some(v) }` hands the type `v` each time a record is built
- A bulk write unwraps each value of each row before the column type sees it, so `update_all`, `insert_all`, `insert_all!`, `upsert_all` and the singular `insert`, `insert!` and `upsert` take an Option on any column, an application's own type included
- `find` and `find_by` unwrap an Option where they are given their ids and conditions, so they take one on any column: a `json` column, whose type encodes the value it is handed without calling `super`, and an application's own `ActiveModel::Type::Value` subclass, which is written the same way. A list of ids unwraps one level in, on a class, a relation and an association alike. This is also what makes `find_by` usable against an encrypted attribute, whose type serializes through the underlying type and then calls `to_s`
- `find_by(col: None())` finds the row whose column is NULL, as `find_by(col: nil)` does, where it used to bind an equality against NULL and quietly find nothing. `find(None())` reports a missing id rather than naming the wrapper
- An adapter's `type_cast` no longer unwraps an Option. Every value is unwrapped before it can reach an adapter, so nothing entered the seam; `quote` still unwraps, and that is what a value reaching the SQL boundary passes through
- A form helper on a converted model renders what one on an unconverted model renders: ActionView reads a field's value off the record through the public reader whenever it did not come from user input, which is every record an edit form loads from the database, and that seam now unwraps. `check_box` no longer raises on `to_i`, `datetime_field` no longer raises on `strftime`, and a text field writes the value rather than raising `Errgonomic::SerializeError`
- Validation on a converted model reads the value inside a wrapped attribute rather than the wrapper: `inclusion` and `exclusion` compare against the value, `presence` rejects `Some('')` as it rejects `''`, `length` and `format` no longer raise, and a `None` validates like `nil`. `validates :x, some: true` stays the Option-aware presence check, and now answers for a plain value on any model. An application's own `EachValidator` or `validates_each` block on a converted model is handed the inner value where 0.8.x handed it the Option, so one written against the wrapper as `value.some?` needs the adaptation `SomeValidator` took: `value.to_option.some?`
- `Some` no longer delegates `marked_for_destruction?` to its record. The presence, absence and associated validators were what asked it, and they now receive the record itself
- A converted model serializes as the unconverted one does: `as_json`, `to_json` and `serializable_hash` fetch every attribute through `read_attribute_for_serialization`, which unwraps, so `Some(v)` writes `v` and `None()` writes `null` where 0.8.x raised `Errgonomic::SerializeError`. An association under `include:` serializes as its record's hash, or leaves the key out where a `nil` association already does, and a wrapped reader named in `methods:` unwraps one layer. An Option handed to an arbitrary payload still raises
- `errgonomic_serialize_none :omit` drops the keys a record has no value for instead of writing them as `null`, declared on either side of the include, on a model or on a base class above it, and scoped to named readers with `only:` or `except:`. The nearest declaration wins and replaces whatever it inherits; `:null` is the default and needs no declaration. A declaration that cannot change a payload raises `ArgumentError` where it is written: an unknown mode, `only:` together with `except:`, or a scoped `:null`
- `Errgonomic::SerializeError` names the value that went unhandled: `cannot serialize an unwrapped Some("cell-a1b2")` rather than `cannot serialize an unwrapped Option`, with the value's `inspect` bounded to 60 characters so a large one does not bury the message. A payload built out of many values now says which one raised
- `delegate_optional` names its reader the way Rails' `delegate` does: `prefix: true` prefixes the target's name, and a Symbol or String prefix is the prefix itself. 0.8.x honoured only `prefix: true` and defined every other delegation under the bare method name, taking over a method of that name the model defined itself. `prefix: true` over a target that cannot name a method raises `ArgumentError` where the delegation is written
- A `delegate_optional` reader forwards what it was called with: positional arguments, keyword arguments and a block, where 0.8.x generated a reader that took no parameters and passed none on, so delegating to a method with any signature at all raised `ArgumentError`. The generated call is written out rather than sent, so a private or protected method on the target no longer delegates
- `delegate_optional` lifts its target instead of assuming an Option, so a model delegates whether or not it has converted: a plain record reads as `Some`, a nil target as `None`, and a `None` target stays `None`, where 0.8.x raised `NoMethodError` on `map` for anything but an Option. It lifts one layer at each end, so a delegated reader that answers an Option comes back as one Option rather than two
- `delegate_optional` accepts `allow_nil: true` as a no-op, so a `delegate` declaration swaps over unchanged, and raises `ArgumentError` on `allow_nil: false`, which asks for something a reader answering an Option cannot do. A declaration with no `to:` raises where it is written, with Rails' wording, where 0.8.x returned silently and defined nothing
- A `delegate_optional` reader is defined against the file and line of the declaration, so a backtrace through it and `instance_method(:reader).source_location` name the model rather than the gem
- `delegate_optional :model_name, to: :class` and any other target named for a Ruby keyword reach the target through an explicit receiver, where the generated body used to read as the keyword and raise `SyntaxError` as the model loaded
- `delegate_optional` refuses a writer (`delegate_optional :name=, to: :author`) with an `ArgumentError` where the declaration is written, rather than the `SyntaxError` the generated reader used to raise: an assignment through an absent target has nowhere to put the value
- `prefix: true` over a module target says that a module has no name to prefix with, where it used to give the message for a target that cannot name a method
- [Behavior change] `to_s` on an Option or a Result renders as `inspect` does (`Some(1).to_s # => "Some(1)"`, `Err(:x).to_s # => "Err(:x)"`) where 0.8.x raised `Errgonomic::SerializeError`. A `to_s` that raises replaces the real exception while a `rescue` builds its log line. `to_json` and `as_json` still raise
- [Behavior change] `Option#map_or` and `Option#map_or_else` answer the bare value their default or block gives, as Rust's do, where 0.8.x wrapped it: `Some(2).map_or(0) { |v| v * 2 }` is `4` and `None().map_or(0) { }` is `0`. They are the exit from the Option, where `map` stays inside it. `Result` has no `map_or` to correct
- Ordering an Option or a Result against anything else raises `Errgonomic::TypeMismatchError`, naming both operands and the spellings that work (`some_and?` / `ok_and?`, `map`, `unwrap_or`). `<=>` used to answer `nil`, which `Comparable` turned into an `ArgumentError` blaming the Option for a comparison the bare value on the other side is what broke. Ordering between two Options or two Results is unchanged, `nil` included where their inner values do not compare
- `Option#each` yields the inner value once for a `Some` and not at all for a `None`, and answers an Enumerator that knows its size without a block, so an Option reads as the zero-or-one collection it is. `Enumerable` is deliberately not included: its `filter`, `select` and `first` answer plain values where an Option's own answer Options
- `sequence_options` and `sequence_results` on `Enumerable` gather a collection of Options or Results into an Option or a Result of an Array, short-circuiting at the first `None` or `Err`, and returning that `Err` as it stands so it keeps its error. An empty enumerable gives `Some([])` / `Ok([])`, and a member that is not an Option or a Result raises `Errgonomic::TypeMismatchError`
- `Option#try` and `Option#try!` under the Rails integration send to the value inside a `Some` and answer `nil` for a `None`, where ActiveSupport's `Object#try` answered `nil` for every method on a wrapper (it asks `respond_to?`, which an Option refuses) and handed a block the wrapper itself. A method the value does not have is `nil` as Rails' `try` is; `try!` raises for it
- `Errgonomic.strict_equality = true` (and the block form `Errgonomic.with_strict_equality`) makes `==`, `!=` and `eql?` between an Option or a Result and a value that is not one raise `Errgonomic::TypeMismatchError` rather than answering false, naming both classes and the spelling to reach for. `nil` counts as cross-type and points at `none?`, and so does the other container: an Option compared to a Result names both and says to unwrap the one you meant. Two Options compare as they always did and `hash` is unchanged; the default stays quiet, and `rake test:strict` runs the Rails integration suite with it on
- `expect!` on an Option or a Result, and `present_or_raise!` on an Option, take a block that is called only on the branch that raises, so a message built from the value it is missing costs nothing on the path that succeeds. The positional message is unchanged
- `Option#presence` is supported rather than soft-deprecated: it is the Rails spelling of `unwrap_or(nil)` and no longer nudges. It stays discriminant-based, so `Some("").presence` is `""` where `"".presence` is `nil`
- The nudge from the soft-deprecated `present_or`, `present_or_else` and `present_or_raise!` fires once per process per method rather than once per call, so a hot path no longer floods stderr, and it names `present_or_raise!` with its bang
- [Docs] The README says why `take`, `replace`, `insert` and `get_or_insert` are absent: each writes through an `&mut Option`, and an Option here is a value rather than a slot
- [Docs] `map` wraps whatever its block returns, as Rust's does, so a block that returns an Option gives `Some(Some(x))`. The README and the method say so, and name `and_then` as the spelling for such a block. Its docstring also no longer claims a pedantic runtime check it never had
- [Docs] `Array#compact` keeps a `None`, because it tests for the `nil` object rather than asking `nil?`. The README names it alongside the `None#nil?` compromise and gives `reject(&:none?)`, `select(&:some?)` and `flat_map(&:to_a)` as the spellings that do what it looks like it does
- [Dev, Test] `rake test:strict` passes `TESTOPTS` through to the run it spawns, so `--seed` works there as it does for `rake test`
- [Dev, Test] - Doctests run against an in-memory ActiveRecord connection, so an `@example` under `lib/errgonomic/rails` specifies the integration the same way every other example specifies the core

## [0.8.3] - 2026-08-12

- A `has_one` reads as an Option, the way an optional `belongs_to` already did
- A singular association with `accepts_nested_attributes_for` is left unwrapped, so nested attribute assignment keeps working
- `to_option` on an Option returns it unchanged instead of wrapping it a second time

## [0.8.2] - 2026-08-12

- `as_json` refuses an unwrapped Option or Result with `Errgonomic::SerializeError`, so a container cannot reach a payload as an undefined structure
- Nullable columns wrap when the schema loads rather than when the concern is included, and an optional `belongs_to` declared after the include is wrapped too
- Including the concern on a base class reaches every model beneath it
- `errgonomic_optionals` reports the wrapped columns as well as the wrapped associations

## [0.8.1] - 2026-08-12

- Presence helpers on an Option hand back the value inside it: `present_or` and its family unwrap rather than returning the wrapper. The family is soft-deprecated on Options in favor of the combinators and nudges toward them on stderr, and the blank side raises a teaching error
- A query written with an Option finds its rows: the predicate builder unwraps, so `where(col: Some(v))` binds the value
- An encrypted attribute is left unwrapped, and `errgonomic_optional_except` opts a named attribute out of wrapping
- [Dev] - Bump activestorage and json past their security advisories

## [0.8.0] - 2026-08-07

- `Option#present?` and `#blank?` follow the discriminant, not the inner value: `Some(false)` and `Some(nil)` are present, `None()` is blank
- New combinators: `Option#filter`, `Option#flatten` and `Option#xor`
- Booleans lift into the containers: `true.then_some(v)`, `false.ok_or(err)`, and the lazy block forms of each
- Optional collections: `OptionalHash` and `OptionalArray` return an Option from a lookup, and `dig` walks a nested wrapper and checks array bounds instead of raising
- `inspect` reads as `Some(1)` and `Err(:nope)`, so a container is legible in a debugger or a test failure
- Option and Result satisfy Ruby's `eql?`/`hash` contract, so they work as hash keys
- Ordering follows Rust: `None` sorts before `Some`, `Ok` before `Err`
- A method an Option does not define raises `Errgonomic::UnwrappedAccessError` naming the combinators to reach for, rather than a bare `NoMethodError`
- The Rust spellings `is_some`, `is_none`, `is_some_and`, `is_none_or` and their Result counterparts delegate to the Ruby predicates, with a nudge on stderr
- A wrapped reader that re-enters itself raises `Errgonomic::RecursiveOptionalReadError` at the first repeated read, instead of measuring call stack depth and failing thousands of frames later
- `delegate_optional` honors `private:`
- Docs: the README covers the current API, Option equality semantics and when `unwrap!` is appropriate, and the ActiveRecord compromises are written down as a named, closed register
- [Dev, Test] - The gem builds as a flake output with gems from gems4nix, CI tracks the latest Ruby 3.4, the tree is rubocop clean, and CONTRIBUTING states the development methodology

## [0.7.0] - 2026-04-22

- `Result#map_err` maps the error of an `Err` and leaves an `Ok` alone
- `Result#deconstruct` makes a Result pattern matchable: `case result in Errgonomic::Result::Ok, value`

## [0.6.0] - 2026-03-23

- Breaking: `and_then` yields the inner value and `or_else` yields the inner error, where both used to yield the container
- Opting out of the pedantic block checks now works. `give_me_ambiguous_downstream_errors` was read through an expression that was always true, so the check fired whatever you set; the default is still to raise when a combinator's block returns something other than an Option or Result
- `Result#map` returns a new `Ok` instead of mutating the receiver in place
- `UnwrapError#value` exposes the inner error, and the value argument is optional
- `ActiveRecordOptional` is opt-in per model: a model includes the concern itself and `Errgonomic::Rails.setup_after` wraps nothing
- [Dev, Test] - Replace rspec with minitest, and run `rake test` in CI alongside the doctests

## [0.5.1] - 2026-03-03

- `TypeMismatchError` descends from `Errgonomic::Error` again, so `rescue Errgonomic::Error` catches it

## [0.5.0] - 2026-03-02

- An unwrapped Option or Result refuses to serialize: `to_s` and `to_json` raise the new `Errgonomic::SerializeError` rather than emitting an undefined structure. Interpolating a container into a string now raises
- `TypeMismatchError` descends from `Errgonomic::TypeError`, a new subclass of Ruby's `TypeError`

## [0.4.2] - 2026-02-27

- An Option binds into a query: the connection adapter quotes `Some(v)` as the value it wraps and `None()` as `NULL`
- `Errgonomic::Rails.setup_after` no longer eager loads the application to wrap every model with a table. A model that wants wrapped readers includes `Errgonomic::Rails::ActiveRecordOptional` itself

## [0.4.1] - 2026-02-20

- Bugfix: `unwrap_or_else` yields the inner error

## [0.4.0] - 2025-11-24

- ActiveRecord integration: a model that includes `Errgonomic::Rails::ActiveRecordOptional` reads its nullable columns and optional `belongs_to` associations as Options, and `validates :x, some: true` is the matching presence check
- `delegate_optional` defines a reader that maps a method through an optional association
- `Result#map`, `Result#tap_ok` and `Result#tap_err`
- `Err#unwrap!` raises an `UnwrapError` carrying the inner error value

## [0.3.0] - 2025-05-01

- Type assertions: `type_or_raise!`, `type_or`

## [0.2.0] - 2025-03-28

- Introduce (most of) Result and Option
- Presence helpers which raise should have a bang on their name
- [Dev, Test] - Replace rspec with yard-doctest

## [0.1.0] - 2025-02-27

- Initial release with some basic extensions for presence
