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
