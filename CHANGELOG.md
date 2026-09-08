## [Unreleased]

- `ActiveRecordOptional` installs its wrapped readers into a per-class module, so a model's own reader of the same name composes with the wrapper through `super` instead of one silently replacing the other
- A wrapped reader lifts a value exactly one layer: an Option arriving from beneath the wrapper passes through instead of being wrapped a second time
- `belongs_to` and `has_one` writers accept an Option: `Some(record)` assigns the record it wraps and `None()` clears the association, so a wrapped reader can be assigned straight onto another record
- An attribute writer accepts an Option and stores the value inside it, `None()` storing `nil`, for every column type: `record.pinned = Some(false)` stores `false` where it used to store `true`, string, text, json, date and datetime writers no longer raise, and the numeric writers no longer route through the soft-deprecated `Option#presence`. Dirty tracking, `attributes` and the before-type-cast reader see the raw value
- A value that reaches the database without passing an attribute writer unwraps at the type cast instead, so `update_all`, `insert_all`, `upsert` and a default declared with `attribute :col, :string, default: Some(v)` take Options for every column type
- Validation on a converted model reads the value inside a wrapped attribute rather than the wrapper: `inclusion` and `exclusion` compare against the value, `presence` rejects `Some('')` as it rejects `''`, `length` and `format` no longer raise, and a `None` validates like `nil`. `validates :x, some: true` stays the Option-aware presence check, and now answers for a plain value on any model
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
