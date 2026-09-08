## [Unreleased]

- `ActiveRecordOptional` installs its wrapped readers into a per-class module, so a model's own reader of the same name composes with the wrapper through `super` instead of one silently replacing the other
- A wrapped reader lifts a value exactly one layer: an Option arriving from beneath the wrapper passes through instead of being wrapped a second time
- `belongs_to` and `has_one` writers accept an Option: `Some(record)` assigns the record it wraps and `None()` clears the association, so a wrapped reader can be assigned straight onto another record
- An attribute writer accepts an Option and stores the value inside it, `None()` storing `nil`, for every column type: `record.pinned = Some(false)` stores `false` where it used to store `true`, string, text, json, date and datetime writers no longer raise, and the numeric writers no longer route through the soft-deprecated `Option#presence`. Dirty tracking, `attributes` and the before-type-cast reader see the raw value
- Validation on a converted model reads the value inside a wrapped attribute rather than the wrapper: `inclusion` and `exclusion` compare against the value, `presence` rejects `Some('')` as it rejects `''`, `length` and `format` no longer raise, and a `None` validates like `nil`. `validates :x, some: true` stays the Option-aware presence check, and now answers for a plain value on any model. An application's own `EachValidator` or `validates_each` block on a converted model is handed the inner value where 0.8.x handed it the Option, so one written against the wrapper as `value.some?` needs the adaptation `SomeValidator` took: `value.to_option.some?`
- An attribute declared with `encrypts` is wrapped like any other nullable column, now that the encryption length validator reads it through the validation seam. It round-trips as an Option, a `deterministic: true` attribute stays queryable, and `downcase:` still normalizes on write
- `Some` no longer delegates `marked_for_destruction?` to its record. The presence, absence and associated validators were what asked it, and they now receive the record itself
- An adapter's `type_cast` no longer unwraps an Option. Every value is unwrapped before it can reach an adapter, so nothing entered the seam; `quote` still unwraps, and that is what a value reaching the SQL boundary passes through
- `find` and `find_by` unwrap an Option where they are given their ids and conditions, so they take one on any column: a `json` column, whose type encodes the value it is handed without calling `super`, and an application's own `ActiveModel::Type::Value` subclass, which is written the same way. A list of ids unwraps one level in, on a class, a relation and an association alike. This is also what makes `find_by` usable against an encrypted attribute, whose type serializes through the underlying type and then calls `to_s`
- An `attribute :col, type, default: Some(v)` declaration unwraps its default where it is written, so the stored default is a plain value whatever the type is, as an assigned one is. A `Proc` default is wrapped rather than unwrapped, so `default: -> { Some(v) }` hands the type `v` each time a record is built
- A bulk write unwraps each value of each row before the column type sees it, so `update_all`, `insert_all`, `insert_all!`, `upsert_all` and the singular `insert`, `insert!` and `upsert` take an Option on any column, an application's own type included
- `find_by(col: None())` finds the row whose column is NULL, as `find_by(col: nil)` does, where it used to bind an equality against NULL and quietly find nothing. `find(None())` reports a missing id rather than naming the wrapper
- A converted model serializes as the unconverted one does: `as_json`, `to_json` and `serializable_hash` fetch every attribute through `read_attribute_for_serialization`, which unwraps, so `Some(v)` writes `v` and `None()` writes `null` where 0.8.x raised `Errgonomic::SerializeError`. An association under `include:` serializes as its record's hash, or leaves the key out where a `nil` association already does, and a wrapped reader named in `methods:` unwraps one layer. An Option handed to an arbitrary payload still raises
- `errgonomic_serialize_none :omit` drops the keys a record has no value for instead of writing them as `null`, declared on either side of the include, on a model or on a base class above it, and scoped to named readers with `only:` or `except:`. The nearest declaration wins and replaces whatever it inherits; `:null` is the default and needs no declaration. A declaration that cannot change a payload raises `ArgumentError` where it is written: an unknown mode, `only:` together with `except:`, or a scoped `:null`
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
