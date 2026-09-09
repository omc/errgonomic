## [Unreleased]

- `ActiveRecordOptional` installs its wrapped readers into a per-class module, so a model's own reader of the same name composes with the wrapper through `super` instead of one silently replacing the other
- A wrapped reader lifts a value exactly one layer: an Option arriving from beneath the wrapper passes through instead of being wrapped a second time
- `belongs_to` and `has_one` writers accept an Option: `Some(record)` assigns the record it wraps and `None()` clears the association, so a wrapped reader can be assigned straight onto another record
- An attribute writer accepts an Option and stores the value inside it, `None()` storing `nil`, for every column type: `record.pinned = Some(false)` stores `false` where it used to store `true`, string, text, json, date and datetime writers no longer raise, and the numeric writers no longer route through the soft-deprecated `Option#presence`. Dirty tracking, `attributes` and the before-type-cast reader see the raw value
- A value that reaches the database without passing an attribute writer unwraps at the type cast instead, so `update_all`, `insert_all`, `upsert` and a default declared with `attribute :col, :string, default: Some(v)` take Options for every column type
- Validation on a converted model reads the value inside a wrapped attribute rather than the wrapper: `inclusion` and `exclusion` compare against the value, `presence` rejects `Some('')` as it rejects `''`, `length` and `format` no longer raise, and a `None` validates like `nil`. `validates :x, some: true` stays the Option-aware presence check, and now answers for a plain value on any model. An application's own `EachValidator` or `validates_each` block on a converted model is handed the inner value where 0.8.x handed it the Option, so one written against the wrapper as `value.some?` needs the adaptation `SomeValidator` took: `value.to_option.some?`
- An attribute declared with `encrypts` is wrapped like any other nullable column, now that the encryption length validator reads it through the validation seam. It round-trips as an Option, a `deterministic: true` attribute stays queryable, and `downcase:` still normalizes on write
- `Some` no longer delegates `marked_for_destruction?` to its record. The presence, absence and associated validators were what asked it, and they now receive the record itself
- A column type unwraps an Option when it serializes a value as well as when it casts one, so `find_by(col: Some(v))` works where it previously reached the type with the wrapper still on: `find_by` binds into a cached statement rather than through the predicate builder. This is what makes `find_by` usable against an encrypted attribute, whose type serializes through the underlying type and then calls `to_s`
- A converted model serializes as the unconverted one does: `as_json`, `to_json` and `serializable_hash` fetch every attribute through `read_attribute_for_serialization`, which unwraps, so `Some(v)` writes `v` and `None()` writes `null` where 0.8.x raised `Errgonomic::SerializeError`. An association under `include:` serializes as its record's hash, or leaves the key out where a `nil` association already does, and a wrapped reader named in `methods:` unwraps one layer. An Option handed to an arbitrary payload still raises
- `errgonomic_serialize_none :omit` drops the keys a record has no value for instead of writing them as `null`, declared on either side of the include, on a model or on a base class above it, and scoped to named readers with `only:` or `except:`. The nearest declaration wins and replaces whatever it inherits; `:null` is the default and needs no declaration. A declaration that cannot change a payload raises `ArgumentError` where it is written: an unknown mode, `only:` together with `except:`, or a scoped `:null`
- `sequence_options` and `sequence_results` on `Enumerable` gather a collection of Options or Results into an Option or a Result of an Array, short-circuiting at the first `None` or `Err`, and returning that `Err` as it stands so it keeps its error. An empty enumerable gives `Some([])` / `Ok([])`, and a member that is not an Option or a Result raises `Errgonomic::TypeMismatchError`
- [Docs] `Array#compact` keeps a `None`, because it tests for the `nil` object rather than asking `nil?`. The README names it alongside the `None#nil?` compromise and gives `reject(&:none?)`, `select(&:some?)` and `flat_map(&:to_a)` as the spellings that do what it looks like it does
- [Dev, Test] - Doctests run against an in-memory ActiveRecord connection, so an `@example` under `lib/errgonomic/rails` specifies the integration the same way every other example specifies the core

## [0.4.1] - 2025-02-20

- Bugfix: `unwrap_or_else` yields the inner error

## [0.2.0] - 2025-05-01

- Type assertions: `type_or_raise!`, `type_or`

## [0.2.0] - 2025-03-28

- Introduce (most of) Result and Option
- Presence helpers which raise should have a bang on their name
- [Dev, Test] - Replace rspec with yard-doctest

## [0.1.0] - 2025-02-27

- Initial release with some basic extensions for presence
