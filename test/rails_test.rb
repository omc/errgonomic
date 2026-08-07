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
end

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

  private

  def deeper(frames, &block)
    return block.call if frames.zero?

    deeper(frames - 1, &block)
  end
end
