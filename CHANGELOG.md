## [Unreleased]

- `ActiveRecordOptional` installs its wrapped readers into a per-class module, so a model's own reader of the same name composes with the wrapper through `super` instead of one silently replacing the other

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
