# frozen_string_literal: true

require 'active_record'
require 'minitest/autorun'
require 'logger'

require_relative '../lib/errgonomic/rails'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = Logger.new(File::NULL)

# Book reviews with various optional attributes and associations
ActiveRecord::Schema.define do
  create_table 'authors', force: :cascade do |t|
    t.string :name, null: false
    t.text :bio
    t.timestamps
  end

  create_table 'books', force: :cascade do |t|
    t.string :title, null: false
    t.string :isbn
    t.date :published_at
    t.references :author
    t.references :genre
    t.timestamps
  end

  create_table 'genres', force: :cascade do |t|
    t.string :name, null: false
    t.references :parent, foreign_key: { to_table: :genres }
    t.timestamps
  end

  create_table 'magazines', force: :cascade do |t|
    t.string :title, null: false
    t.string :issn
    t.timestamps
  end

  create_table 'credentials', force: :cascade do |t|
    t.string :access_key, limit: 255
    t.string :access_secret, limit: 255
    t.timestamps
  end
end

ActiveRecord::Encryption.configure(
  primary_key: 'test primary key',
  deterministic_key: 'test deterministic key',
  key_derivation_salt: 'test key derivation salt'
)

# Before classes are loaded we need to define helper methods like `delegate_optional`
Errgonomic::Rails.setup_before

class Author < ActiveRecord::Base
  has_many :books
  include Errgonomic::Rails::ActiveRecordOptional
end

class Book < ActiveRecord::Base
  has_many :reviews
  has_many :reviewers, through: :reviews, source: :user
  belongs_to :author, optional: true

  include Errgonomic::Rails::ActiveRecordOptional
  delegate_optional :name, to: :author, prefix: true
end

class Genre < ActiveRecord::Base
  has_many :books
  belongs_to :parent, class_name: 'Genre', optional: true
  include Errgonomic::Rails::ActiveRecordOptional
  delegate_optional :name, to: :parent, prefix: true, private: true
end

# A buggy layer that re-enters the attribute reader from beneath it: the
# generated reader's super lands here, and the unqualified call restarts
# dispatch at the top of the chain.
module ReentrantBio
  def bio
    bio
  end
end

class LoopyAuthor < ActiveRecord::Base
  self.table_name = 'authors'
  include ReentrantBio
  include Errgonomic::Rails::ActiveRecordOptional
end

# Encryption adds a length validator that reads the raw attribute, and
# declares itself after the concern is included, as applications write it.
class Credential < ActiveRecord::Base
  include Errgonomic::Rails::ActiveRecordOptional
  encrypts :access_secret
end

# An opt-out named before the include keeps an attribute unwrapped, for
# machinery the concern does not know about.
class OptedOutCredential < ActiveRecord::Base
  self.table_name = 'credentials'
  errgonomic_optional_except :access_key
  include Errgonomic::Rails::ActiveRecordOptional
end

# Rails convention puts a concern at the top of a model, above its
# associations, so an optional belongs_to is routinely declared after the
# include.
class LateAssociationBook < ActiveRecord::Base
  self.table_name = 'books'
  include Errgonomic::Rails::ActiveRecordOptional
  belongs_to :author, optional: true
end

# An opt-out names an association the same way it names an attribute.
class OptedOutBook < ActiveRecord::Base
  self.table_name = 'books'
  errgonomic_optional_except :author
  belongs_to :author, optional: true
  include Errgonomic::Rails::ActiveRecordOptional
end

# A subclass has its own schema state, so it reaches the wrapping seam a
# second time for columns its parent already wrapped.
class Novel < Book; end

# Where the include goes decides how far it reaches. On an application's own
# base class it reaches every model below, so a model converts without naming
# errgonomic at all.
class HouseRecord < ActiveRecord::Base
  self.abstract_class = true
  include Errgonomic::Rails::ActiveRecordOptional
end

# Nothing in these two mentions the concern.
class Zine < HouseRecord
  self.table_name = 'magazines'
end

class Chapbook < HouseRecord
  self.table_name = 'books'
  belongs_to :author, optional: true
end

# A model that keeps value-or-nil throughout.
class PlainZine < HouseRecord
  self.table_name = 'magazines'
  errgonomic_optional_off
end

# One attribute back to value-or-nil, in a model with no include to declare it
# before.
class PartlyPlainZine < HouseRecord
  self.table_name = 'magazines'
  errgonomic_optional_except :issn
end

# A model from a gem descends straight from ActiveRecord::Base, as engine
# models do, so an application's base class does not reach it.
class VendorLedger < ActiveRecord::Base
  self.table_name = 'magazines'
end

class BugTest < Minitest::Test
  def test_optional_attributes
    author = Author.create!(name: 'Cixin Liu')
    assert author.name.present?
    assert author.bio.none?
    book = author.books.create!(title: 'The Three-Body Problem')
    assert book.isbn.none?
  end

  # Option presence must beat ActiveSupport's Object#present?, where any
  # non-nil object (including None) counts as present.
  def test_option_presence_with_active_support_loaded
    author = Author.create!(name: 'Cixin Liu')
    assert author.bio.blank?
    refute author.bio.present?
    assert author.name.present?
  end

  # The presence helpers are how application code reaches a wrapped
  # attribute's value, so they must yield the value and not the wrapper.
  def test_wrapped_attribute_round_trips_through_present_or_raise
    author = Author.create!(name: 'Cixin Liu', bio: 'writes sci-fi')
    assert_equal 'writes sci-fi', author.bio.present_or_raise('no bio')
    assert_equal 'writes sci-fi', author.bio.present_or('none given')
    assert_equal 'writes sci-fi', author.bio.presence

    unwritten = Author.create!(name: 'Liu Cixin')
    assert_raises(Errgonomic::NotPresentError) { unwritten.bio.present_or_raise('no bio') }
    assert_equal 'none given', unwritten.bio.present_or('none given')
    assert_nil unwritten.bio.presence
  end

  def test_optional_associations
    author = Author.create!(name: 'Cixin Liu')
    book = author.books.create!(title: 'The Dark Forest')
    assert book.author.some?
  end

  # Feeding a wrapped attribute back into a query is among the most common
  # Rails idioms, so a Some has to bind exactly as its inner value would.
  def test_where_with_a_some_matches_the_row
    genre = Genre.create!(name: 'Sci-Fi')
    book = Book.create!(title: 'The Dark Forest', genre_id: genre.id)

    assert_equal 1, Book.where(genre_id: book.genre_id).count
    refute_includes Book.where(genre_id: book.genre_id).to_sql, '= NULL'
  end

  # A None reads as absent, which for a hash condition means IS NULL rather
  # than an = NULL that can never match.
  def test_where_with_a_none_asks_for_null
    unshelved = Book.create!(title: 'Ball Lightning')

    relation = Book.where(title: 'Ball Lightning', genre_id: unshelved.genre_id)
    assert_includes relation.to_sql, 'IS NULL'
    assert_equal 1, relation.count
  end

  def test_where_with_an_array_of_options
    first = Genre.create!(name: 'Sci-Fi')
    second = Genre.create!(name: 'Fantasy')
    Book.create!(title: 'The Dark Forest', genre_id: first.id)
    Book.create!(title: 'The Hobbit', genre_id: second.id)

    relation = Book.where(genre_id: [Some(first.id), Some(second.id)])
    assert_equal 2, relation.count
    refute_includes relation.to_sql, 'NULL'
  end

  # Hash and Array serialization recurses with as_json, never to_json, so
  # the refusal has to sit on as_json to survive nesting.
  def test_nested_options_and_results_refuse_to_serialize
    assert_raises(Errgonomic::SerializeError) { Some(5).as_json }
    assert_raises(Errgonomic::SerializeError) { { a: Some(5) }.to_json }
    assert_raises(Errgonomic::SerializeError) { { a: None() }.to_json }
    assert_raises(Errgonomic::SerializeError) { [Some(5)].to_json }
    assert_raises(Errgonomic::SerializeError) { Ok(5).as_json }
    assert_raises(Errgonomic::SerializeError) { { a: Err(5) }.to_json }
    assert_raises(Errgonomic::SerializeError) { [Ok(5)].to_json }
  end

  def test_delegate_optional
    author = Author.create!(name: 'Cixin Liu')
    book = author.books.create!(title: 'Death\'s End')
    assert book.author_name.some?
    assert_equal author.name, book.author_name.unwrap!
  end

  # Wrapped readers must work on a deep-but-legitimate stack; genuine runaway
  # recursion is SystemStackError's job.
  def test_optional_attributes_read_on_a_deep_stack
    author = Author.create!(name: 'Cixin Liu', bio: 'writes sci-fi')
    deeper(1100) { assert_equal 'writes sci-fi', author.bio.unwrap! }
  end

  def test_recursive_read_raises_a_named_error_at_first_reentry
    author = LoopyAuthor.create!(name: 'Cixin Liu', bio: 'writes sci-fi')
    error = assert_raises(Errgonomic::RecursiveOptionalReadError) { author.bio }
    assert_match(/bio/, error.message)
  end

  def test_private_delegate_optional
    fiction = Genre.create!(name: 'Fiction')
    scifi = Genre.create!(name: 'Sci-Fi', parent: fiction)
    assert_raises(NoMethodError) { scifi.parent_name }
    assert_equal 'Fiction', scifi.send(:parent_name).unwrap!
  end

  def test_encrypted_attributes_are_left_unwrapped
    credential = Credential.create!(access_key: 'abc123', access_secret: 'shhh')

    assert_equal 'shhh', credential.access_secret
    assert_equal 'abc123', credential.access_key.unwrap!
  end

  def test_encrypted_attributes_may_be_absent
    credential = Credential.create!(access_key: 'abc123')

    assert_nil credential.access_secret
    assert credential.reload.access_secret.nil?
  end

  # ActiveRecord loads a model's schema on first use, not at definition, so a
  # class body must not need a database. Wrapping at include time did, and
  # any boot that loads models without a reachable database — an asset build,
  # an image build, a schema check — then fails on the include.
  def test_including_the_concern_does_not_reach_for_the_schema
    statements = []
    subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      statements << payload[:sql]
    end

    magazine = Class.new(ActiveRecord::Base) do
      def self.name = 'Magazine'
      self.table_name = 'magazines'
      include Errgonomic::Rails::ActiveRecordOptional
    end

    ActiveSupport::Notifications.unsubscribe(subscription)

    assert_empty statements
    assert magazine.create!(title: 'Nature').issn.none?
  end

  # What a model wrapped is how a conversion is checked, so it has to answer
  # for the columns too, before anything else has touched the model.
  def test_the_wrapped_set_is_reported_before_the_schema_is_used
    quarterly = Class.new(ActiveRecord::Base) do
      def self.name = 'Quarterly'
      self.table_name = 'magazines'
      include Errgonomic::Rails::ActiveRecordOptional
    end

    assert_equal %w[issn], quarterly.errgonomic_optionals
  end

  # An inherited reader is already wrapped, and a second wrap nests: Some of
  # a Some for a present value, while an absent one collapses back to None
  # because None answers nil?. Half of it is silent.
  def test_a_subclass_reads_its_inherited_wrapped_attributes_once
    author = Author.create!(name: 'Cixin Liu')
    novel = Novel.create!(title: 'Death\'s End', author_id: author.id, isbn: '9780765377104')

    assert_equal '9780765377104', novel.isbn.unwrap!
    assert_equal author.id, novel.author.unwrap!.id
    assert Novel.create!(title: 'Supernova Era').isbn.none?
  end

  # An include on a base class reaches every model below it, columns and
  # associations alike, which is how an application converts all at once.
  def test_a_base_class_include_reaches_the_models_below_it
    assert Zine.create!(title: 'Nature').issn.none?
    assert_equal %w[issn], Zine.errgonomic_optionals

    author = Author.create!(name: 'Cixin Liu')

    assert_equal author.id, Chapbook.create!(title: 'The Wandering Earth II', author_id: author.id).author.unwrap!.id
    assert Chapbook.create!(title: 'Supernova Era').author.none?
  end

  # A model whose own code reads its attributes raw has to be able to say so,
  # in a model body with no include to point at.
  def test_a_model_below_the_base_class_can_opt_out_entirely
    assert_nil PlainZine.create!(title: 'Asimovs').issn
    assert_empty PlainZine.errgonomic_optionals
  end

  def test_a_model_below_the_base_class_can_opt_out_one_attribute
    assert_equal '1937-7843', PartlyPlainZine.create!(title: 'Clarkesworld', issn: '1937-7843').issn
  end

  # Engine and gem models descend straight from ActiveRecord::Base, and their
  # own code knows nothing about an Option.
  def test_a_model_outside_the_base_class_is_untouched
    assert_nil VendorLedger.create!(title: 'Ledger').issn
  end

  # Wrapping only what the class already declared makes the include's
  # position load-bearing, and a partial conversion is silent.
  def test_optional_belongs_to_declared_after_the_include_is_wrapped
    author = Author.create!(name: 'Cixin Liu')
    book = LateAssociationBook.create!(title: 'The Dark Forest', author_id: author.id)

    assert book.author.some?
    assert_equal author.name, book.author.unwrap!.name
    assert LateAssociationBook.create!(title: 'The Wandering Earth').author.none?
  end

  def test_errgonomic_optional_except_skips_named_associations
    author = Author.create!(name: 'Cixin Liu')
    book = OptedOutBook.create!(title: 'The Dark Forest', author_id: author.id)

    assert_equal author.name, book.author.name
  end

  def test_errgonomic_optional_except_skips_named_attributes
    credential = OptedOutCredential.create!(access_key: 'abc123', access_secret: 'shhh')

    assert_equal 'abc123', credential.access_key
    assert_equal 'shhh', credential.access_secret.unwrap!
  end

  private

  def deeper(frames, &block)
    return block.call if frames.zero?

    deeper(frames - 1, &block)
  end
end
