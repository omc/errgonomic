# Errgonomic

Errgonomic provides some lightweight, opinionated ergonomics for error handling in Ruby. These semantics are a blend of Rails `present?` conventions, and Rust `Option` and `Result` type combinators. Without going full Option and Result. Probably.

## Design

Errgonomic aims at the intersection of two idioms rather than translating one into the other. Rails supplies the mechanism: a concern, an attribute reader overridden with `super`, the reader as the boundary of a model's public surface. Rust supplies the shape of the value: an `Option` you handle with combinators, instead of a value that may or may not be `nil`. Convention over configuration and least surprise are the tests every design choice here has to pass, and where the two idioms already agree we follow the convention and say nothing more about it.

Where the gem leaves one of them, the docs say so and say why. The reason is nearly always mechanical: ActiveRecord assumes things about accessors that a strict Option cannot satisfy. The [ActiveRecord compromises](#activerecord-compromises) are that register, enumerated and closed.

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

`map` wraps whatever the block returns, as Rust's does, so a block that itself returns an Option gives `Some(Some(x))`. `and_then` is the spelling for that block.

Options support pattern matching:

```ruby
case measurement
in Errgonomic::Option::Some, value
  "Measurement is #{value}"
in Errgonomic::Option::None
  "Measurement is not available"
end
```

An unhandled Option refuses to leak into your output: `to_json` and `as_json` raise `Errgonomic::SerializeError`, so you handle the inner value deliberately rather than shipping `#<Errgonomic::Option::Some...>` to a user. The refusal covers `as_json` because Hash and Array serialization recurses through that method, and an Option nested in a payload would otherwise serialize as `{"value": ...}`. A converted ActiveRecord model is the one exception, at the model boundary: it unwraps each attribute as it serializes, so a record's own `as_json` says what an unconverted record's says. See [Rails integration](#rails-integration).

`to_s` renders rather than refusing: `Some(1).to_s` is `"Some(1)"` and `None().to_s` is `"None"`, matching `inspect`, and the same holds for `Ok` and `Err`. Rust gives `Option` a `Debug` and no `Display`, so raising was the faithful reading, but a `to_s` that raises replaces the real exception while a `rescue` builds its log line, which is the worst possible place to be strict. The rendered form is unambiguous: a `Some(1)` in a log says a wrapper arrived where a value was meant.

`expect!` also takes a block, on an Option and a Result alike, so a message that interpolates is built only on the branch that raises: `tier.expect! { "no tier for #{account.id}" }`. `present_or_raise!` takes one on the same terms. The positional form is unchanged.

`unwrap!` and `expect!` are for tests and consoles, not application code: they raise on `None`, which is exactly the ambiguous failure the type exists to prevent. Application code should always have a combinator or pattern match that handles the `None` branch explicitly; if none fits, that is a gap worth an issue rather than a reason to unwrap.

Presence follows the discriminant, as in Rust: `Some` is `present?` and `None` is `blank?`, regardless of the wrapped value. So `Some(false).present?` and `Some(nil).present?` are both `true`. If you care about the inner value's own presence, unwrap it first.

Truthiness is the Rails reflex that breaks. An Option is an object, so `None()` is truthy: `isbn || 'unassigned'` hands back the `None`, `if isbn` takes the present branch, and nothing raises to say so. Reach for `unwrap_or('unassigned')`, or for `map` and `and_then` when the fallback is itself an Option. Safe navigation looks for the `nil` object rather than asking `nil?`, so `isbn&.strip` calls into the Option and raises `Errgonomic::UnwrappedAccessError`, where `isbn.map(&:strip)` does what was meant. Under the Rails integration `None#nil?` answers `true`, so an explicit `nil?` check behaves, but `||` and `&.` never consult it.

Writers unwrap under that integration, which changes what a truthiness slip costs rather than removing it. `self.isbn = isbn || 'unassigned'` no longer leaks a wrapper into the database; it silently persists whatever `isbn` held, `nil` included, because a `None` is truthy and the fallback is never reached. The write succeeds and nothing raises. `unwrap_or('unassigned')` is the spelling that means it.

`presence` is the Rails spelling of `unwrap_or(nil)`, and it is supported: `Some(x).presence` is `x` and `None().presence` is `nil`, so `isbn.presence || 'unassigned'` reaches the value rather than the wrapper. It follows the discriminant, as every presence question on an Option does, so `Some("").presence` is `""` where `"".presence` on any other object is `nil`. An Option's presence is whether it holds a value, not what that value amounts to; unwrap first (`isbn.unwrap_or("").presence`) to ask the inner value's own presence.

The remaining present-side helpers are soft-deprecated on Options in favor of the combinators. They unwrap, where on any other object they return the receiver: `Some(v).present_or_raise!(msg)`, `present_or(default)` and `present_or_else { }` all yield `v`, and `None` raises, substitutes, or computes. Each prints a one-line stderr nudge naming the combinator to use instead (`expect!`, `unwrap_or`, `unwrap_or_else`), once per process per method rather than once per call, so a hot path does not flood the log. The blank side (`blank_or*`) raises `UnwrappedAccessError` outright: an Option's blankness is its discriminant, so test it with `none?`.

Equality is between Options only: `Some(5) == Some(5)`, but `Some(5) == 5` and `None() == nil` are `false`. That is quiet, never an error, matching how every Ruby object compares across types. Rust rejects `Some(5) == 5` at compile time; Ruby cannot, so guard the idiom in review and tests: compare against a wrapped value (`opt == Some(5)`) or test the inner value (`opt.some_and? { |v| v == 5 }`). `Errgonomic.strict_equality = true` turns that guard into an error, which is what a test suite wants; see [Pedantic runtime checks](#pedantic-runtime-checks).

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

Like Options, unwrapped Results refuse `to_json` and `as_json`, and render `to_s` as `inspect` does. And `Object#result?` / `Object#assert_result!` help enforce at runtime that a value is a Result.

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

`sequence_options` and `sequence_results` are the all-or-nothing collection, which Rust spells as a `collect` into `Option<Vec<T>>` or `Result<Vec<T>, E>`. The name is Haskell's `sequence`, the operation Rust's `collect` performs underneath, rather than anything a Rubyist would already recognize. They are on `Enumerable`, so they compose with `map` instead of needing a wrapper type. The first `None` or `Err` short-circuits, and an `Err` comes back as it stands, still carrying its error.

```ruby
[Some(1), Some(2)].sequence_options   # => Some([1, 2])
[Some(1), None()].sequence_options    # => None()
[].sequence_options                   # => Some([])

[Ok(1), Ok(2)].sequence_results       # => Ok([1, 2])
[Ok(1), Err(:nope)].sequence_results  # => Err(:nope)
```

A member that is not an Option, or not a Result, raises `Errgonomic::TypeMismatchError` in the same pedantic style as `Option#flatten`. It raises regardless of `with_ambiguous_downstream_errors`, which relaxes what a block returned rather than what a caller passed in. A Hash enumerates as pairs, which are Arrays, so `hash.values.sequence_options` is the spelling for a hash of Options.

Three operations over a collection of Options are easy to confuse with one another, so it is worth naming all three:

| Rust | meaning | errgonomic |
| --- | --- | --- |
| `iter.flatten()` | drop the absent members | `reject(&:none?)`, `select(&:some?)`, or `flat_map(&:to_a)` to unwrap while dropping |
| `Option::flatten` | unnest an `Option<Option<T>>` | `Option#flatten` |
| `collect::<Option<Vec<_>>>()` | all or nothing | `sequence_options`, `sequence_results` |

`Array#compact` is not in that first row. It is implemented in C and tests for the `nil` object rather than asking `nil?`, so it keeps a `None` where the idiom reads as though it drops it, and something downstream then dereferences the wrapper. Use `reject(&:none?)` or `select(&:some?)` to keep the wrappers, `flat_map(&:to_a)` to unwrap in the same pass, and `sequence_options` when an absent member should take the whole collection with it. The first two ask every member the question, so a plain `nil` still in the list raises `NoMethodError`; `flat_map(&:to_a)` survives one, since `nil.to_a` is `[]`, but not a bare value.

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

Cross-type equality is the other pedantic check, and it is off by default because a quiet `false` is what every Ruby object answers. Turn it on and a comparison between a wrapper and a value that is not one raises `Errgonomic::TypeMismatchError`, naming both classes and the spelling to reach for:

```ruby
Errgonomic.strict_equality = true

Some(5) == 5        # => raises Errgonomic::TypeMismatchError
Some(5) != 5        # => raises
Some(5).eql?(5)     # => raises
None() == nil       # => raises, pointing at none?
Ok(1) == 1          # => raises
Some(5) == Some(5)  # => true, as always
```

Two Options, or two Results, compare as they always did, and `hash` is untouched, so an Option stays usable as a Hash key with it on. It is meant for a test suite or CI, not for production, and there is a block form for scoping it the way the ambiguous-error opt-out is scoped:

```ruby
Errgonomic.with_strict_equality do
  assert_equal Some(5), book.pages
end
```

This gem runs its own Rails integration suite that way, as `rake test:strict`.

### Rails integration

When `Rails::Railtie` is defined, Errgonomic installs a Railtie with two opt-in integrations for ActiveRecord:

- `include Errgonomic::Rails::ActiveRecordOptional` in a model makes its nullable attributes and `optional: true` associations return `Some(value)` or `None()` instead of a value-or-nil. Every nullable column and optional association is wrapped, with no per-attribute opt-in. Three kinds of reader stay unwrapped: a singular association with `accepts_nested_attributes_for`, which ActiveRecord assigns through the reader and reads raw; a `has_one ..., required: true`, whose absence is a validation failure rather than a value; and anything named by `errgonomic_optional_except`.

```ruby
class Credential < ApplicationRecord
  errgonomic_optional_except :legacy_token
  include Errgonomic::Rails::ActiveRecordOptional

  encrypts :access_secret   # wrapped like any other nullable column
  has_one :rotation_schedule # wrapped: Some(schedule) or None()
  has_one :owner, required: true # left unwrapped: absence is a validation failure
end
```

**Where the include goes.** A model that includes the concern converts itself, and only itself. The include may sit at the top of the model with the other concerns, which is where Rails convention puts one. An `optional: true` association declared below it is wrapped as it is declared, rather than only the associations the class happened to declare above it.

```ruby
class Book < ApplicationRecord
  include Errgonomic::Rails::ActiveRecordOptional

  belongs_to :author, optional: true   # Some(author) or None()
end
```

On an application's own base class, the same include reaches every model below it, and no model mentions errgonomic again:

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  include Errgonomic::Rails::ActiveRecordOptional
end
```

Converting one model or all of them is therefore where the include goes, not a setting to choose. The association macros wrap as each model declares them, and a model's nullable columns are wrapped when ActiveRecord loads its schema, so no class body needs a database while it loads.

An application's own base class is the useful place for it. Engine and gem models such as `ActiveStorage::Blob` and `PaperTrail::Version` descend straight from `ActiveRecord::Base`, and their own code reads their attributes knowing nothing about an Option. Including it on `ActiveRecord::Base` reaches those too, which is rarely what anyone wants.

Two ways out, both readable in a model with no include of its own to point at:

```ruby
class LegacyImport < ApplicationRecord
  errgonomic_optional_off                     # this model keeps value-or-nil throughout
end

class Credential < ApplicationRecord
  errgonomic_optional_except :legacy_token    # this attribute does
end
```

**Overriding a wrapped reader.** Wrapped readers live in a module the concern includes into the model, so a model's own `def` of the same name coexists with the wrapper and reads the Option through `super`. The rule is one of layering: a `def` in the model's own class body, or a module the model itself includes after the errgonomic include, sits above the wrapper and reads the Option from `super`.

The type does not change inside the override. `super` hands back exactly what every other caller of the reader gets, so an override that keeps the Option keeps the model's contract:

```ruby
class Book < ApplicationRecord
  include Errgonomic::Rails::ActiveRecordOptional

  belongs_to :author, optional: true

  def isbn
    super.map(&:strip)   # super is Some(isbn) or None(), and so is this
  end

  def display_isbn
    isbn.unwrap_or('unassigned')
  end
end
```

An accessor that hands back a plain value is a different method with a different name, the way a Rust `fn display_name(&self) -> String` sits beside a `name: Option<String>` field. `display_isbn` is that method; `isbn` stays the field.

A same-named `def` that never calls `super` is legal Ruby and the model owns its return value outright: the wrapper stays installed beneath it and nothing reaches it. It is the un-idiomatic spelling, and it leaves one loose end: `Model.errgonomic_optionals` still reports the reader as wrapped, because the conversion did wrap it.

**Storage stays nullable; the reader is the boundary.** Only the reader returns an Option. `self[:isbn]`, `read_attribute(:isbn)`, `isbn_was`, `isbn_change`, and `attributes` all answer the raw column value or `nil`, which is where Rails already draws the line for a reader override: the attribute is the storage, the reader is the interface. Rust would expect the Option all the way down, and this is the largest place the gem does not follow it, because dirty tracking, serialization, and query building each read the attribute directly and an Option would have to survive all of them.

Writers take either a plain value or an Option of one, for attributes and singular associations alike, so a wrapped reader's value assigns straight back: `other_book.title = book.title` and `other_book.author = book.author` both do what they read like. `book.isbn = '9780765377104'` means what it always did, and assigning `None()` stores `nil`. Assigning an Option is assigning the value inside it for every column type, so a wrapped `false` stores `false`, and the storage behind the reader stays raw: `changes`, `read_attribute_before_type_cast` and `attributes` see the value, never the wrapper. `find`, `find_by`, `exists?`, `update_all`, `insert_all`, `upsert` and an attribute default take Options on the same terms, unwrapping where the value enters ActiveRecord rather than at a writer.

Every one of those seams is installed on ActiveModel or ActiveRecord itself, as the quoting and predicate-builder seams are. They apply to every model in the application, whether or not it includes the concern: the concern decides what a reader returns, not what a writer accepts. None of them asks anything of the column type, so a type that never calls `super` from its own `cast` or `serialize` needs no cooperation: an application's own `ActiveModel::Type::Value` subclass and a `json` column both take an Option wherever a plain value goes.

**Validation reads the value.** Standard validators on a converted model behave exactly as they do on an unconverted one. `inclusion`, `exclusion`, `presence`, `length`, `format`, `numericality` and the rest weigh the value inside the Option, and a `None` validates like `nil`, because every `EachValidator` fetches its attribute through `read_attribute_for_validation`, which unwraps. `validates :isbn, some: true` is the Option-aware presence check, asking only whether the value is there: `Some('')` passes `some:` and fails `presence: true`, exactly as `''` fails it. Custom validation code is the exception, because it reads the public reader: a `validate :check_isbn` whose body calls `isbn` gets `Some('9780765377104')`, the same as every other caller.

**Serialization.** A converted model serializes as the unconverted one does. `as_json`, `to_json` and `serializable_hash` fetch every attribute through `read_attribute_for_serialization`, which unwraps, so `Some(v)` writes `v` and `None()` writes `null`. Both idioms agree on the default: Rails writes an absent value as `null`, and so does serde unless a field asks otherwise. The refusal stands everywhere else, so a hand-built Option in an arbitrary payload (`{ isbn: book.isbn }.to_json`) still raises `Errgonomic::SerializeError`.

An association under `include:` follows the same rule: `Some(author)` serializes as the record's own hash, and a `None` leaves the key out, which is what `include:` already does with a `nil` association. A `has_many` is never an Option and is untouched. A wrapped reader named in `methods:` unwraps one layer as well, so `as_json(methods: :isbn)` writes the value; a method that hands back a plain value is unchanged.

Omission is the opt-in, as it is in serde, and it is declared on the model rather than on `belongs_to` or `has_one`:

```ruby
class ApplicationRecord < ActiveRecord::Base
  include Errgonomic::Rails::ActiveRecordOptional
  errgonomic_serialize_none :omit                  # drop keys whose value is None
end

class Book < ApplicationRecord
  errgonomic_serialize_none :null                  # this model keeps them, as null (the default)
end

class Manuscript < ApplicationRecord
  errgonomic_serialize_none :omit, only: %i[isbn]  # only this reader is dropped; except: also accepted
end
```

The declaration reads as well above the include as below it, as `errgonomic_optional_except` does. The nearest declaration wins and replaces whatever it inherits, rather than layering onto it, so a reader a scoped declaration does not name keeps the default. Omission drops keys from the payload the caller asked for, so it composes with the caller's own `only:` and `except:`. It governs by reader name wherever the key came from, so a `methods:` entry naming a wrapped reader that reads `None` is dropped along with the reader, while a plain method that happens to return `nil` is kept. A declaration that cannot change a payload raises `ArgumentError` where it is written, naming what to write instead. That covers a mode other than `:null` or `:omit`, `only:` together with `except:`, and a scoped `:null`, which asks for the default on the readers it names and leaves the rest at the default anyway.

`Model.errgonomic_optionals` reports which readers a model wrapped, including nullable foreign-key columns, so `book.author_id` is `Some(1)` alongside `book.author`. That is how to check that a conversion did what it meant to.

`delegate_optional` is Rails' `delegate` with `allow_nil`, where the absent case is a `None` rather than a `nil`: `delegate_optional :name, to: :author` gives `book.name # => Some('Cixin Liu')`, and `None()` where there is no author. The prefix forms are Rails': `prefix: true` names the reader after the target (`author_name`), and `prefix: :writer` names it `writer_name`. `private: true` works as it does there. The reader forwards whatever it was called with, arguments and block alike. `allow_nil: true` is accepted and says nothing new, so a `delegate` declaration swaps over unchanged unless it delegates a writer. `delegate_optional :name=, to: :author` raises instead: an assignment through an absent target has nowhere to put the value, and dropping it silently is what the type is there to prevent. `allow_nil: false` asks for a reader that raises on absence, which this does not have, so it raises `ArgumentError` where it is written, as a declaration with no `to:` does.

It is available on every model, converted or not, because it lifts both ends one layer. The target is lifted, so a plain record reads as `Some` and a `nil` as `None`. What the delegated call returns is lifted too, so a delegated reader that is itself an Option comes back as one Option rather than two.

`Object#to_option` lifts any value into an Option (`nil.to_option # => None()`). It lifts once and only once: an Option passes through unchanged (`Some(1).to_option # => Some(1)`), so lifting a value whose provenance you do not know is safe. That is the rule everywhere in the integration. An ActiveRecord attribute or association is never an optional of an optional, so a wrapped reader never nests a second Option around a value that already is one. Nesting is invisible until something reaches for the inner value, which is the ambiguous failure the type exists to prevent.

`try` reaches the value inside the Option: `book.isbn.try(:strip)` strips the ISBN and answers `nil` where there is none, and the block form yields the value (`book.isbn.try { |isbn| isbn.strip }`). ActiveSupport's `Object#try` asks `respond_to?` first, which an Option answers `false` to for anything it does not define, so without this it would be a quiet `nil` for every method and would hand a block the wrapper rather than the value. A method the value does not have is still `nil`, as it is for any other receiver, and `try!` is Rails' strict variant, which raises for that and still answers `nil` for a `None`. Both are defined only under this integration, where ActiveSupport's `try` is what they follow.

#### ActiveRecord compromises

This is the register of where the gem leaves the Rust idiom, and why. ActiveRecord assumes things about accessors that a strict Rust `Option` cannot satisfy, so the integration carries five deliberate compromises, each one forced by a specific piece of ActiveRecord machinery rather than chosen. Everywhere else, treat a departure from Rust's `Option` semantics as a bug; these five are intended:

1. `None#nil?` answers `true`, so ActiveRecord internals and ordinary `.nil?` checks treat an absent value as absent. Equality does not follow suit: `None() == nil` is still `false`. Nor does `Array#compact`, the common collection idiom for dropping absent members: it tests for the `nil` object, so it keeps a `None` where `reject(&:none?)` drops it.
2. `Some` delegates `persisted?` and `touch_later` to its record, so a `Some` can stand in for it where ActiveRecord reads an association back through its public reader, as a `belongs_to ..., touch: true` does after a save.
3. An `Option` is unwrapped where a value enters ActiveRecord, above the column type in every case. Quoting and the predicate builder are patched so an `Option` passed into `where`/`quote` is unwrapped at the SQL boundary: `Some(v)` binds exactly as `v`, and `None()` as `nil`, so a hash condition asks for `IS NULL`. An array of Options unwraps too. An Option interpolated into raw SQL (`where("id = ?", opt)`) still raises, as it should. Assignment unwraps on the same principle. A singular association writer takes an Option of a record: `book.author = Some(author)` assigns it and `book.author = None()` clears the association, while a `Some` of the wrong class still raises `AssociationTypeMismatch`. An attribute writer takes an Option of a value, for every column type, and unwraps before the attribute is built, so `book.isbn = other.isbn` round-trips and nothing behind the reader ever holds a wrapper. A value that reaches the database without passing a writer unwraps where it enters ActiveRecord, above the column type in every case: in the ids and conditions `find` and `find_by` are given, on a class, a relation and an association alike; in the rows `update_all`, `insert_all` and `upsert` take; and in a default declared with `attribute :isbn, :string, default: Some('unassigned')`, unwrapped where it is written.
4. `SomeValidator` asks whether a value is there at all, where `presence` asks whether it amounts to anything: `Some('')` passes `validates :x, some: true` and fails `presence: true`. It lifts what it is handed, so it asks the same question of any model, converted or not.
5. Where ActiveRecord's own machinery reads a value raw, it gets one. Validation unwraps at `read_attribute_for_validation`, the seam every `EachValidator` fetches an attribute through, and serialization at `read_attribute_for_serialization`, the seam every attribute in a payload is fetched through, so a standard validator weighs the value and a payload carries it rather than the wrapper. A singular association with `accepts_nested_attributes_for` goes further and keeps its plain reader: nested attributes are assigned through the reader, and ActiveRecord asks whatever it finds there whether it is a new record.

The set is closed. If a future integration appears to need a sixth compromise, that is a signal ActiveRecord is pushing back somewhere unmapped, and it warrants a design discussion rather than a quiet patch. `errgonomic_optional_except` and `errgonomic_serialize_none` are deliberately not on the list: they are configuration, an escape hatch that softens the all-or-nothing include for whatever conflict shows up next and a choice of how an absent value is written, rather than semantic exceptions.

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
