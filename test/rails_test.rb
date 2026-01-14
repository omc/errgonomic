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
end

class Book < ActiveRecord::Base
  has_many :reviews
  has_many :reviewers, through: :reviews, source: :user
  belongs_to :author, optional: true

  delegate_optional :name, to: :author, prefix: true
end

class Genre < ActiveRecord::Base
  has_many :books
  belongs_to :parent, class_name: 'Genre', optional: true
end

# Optional associations have to be defined after the model is evaluated so we
# can reflect on those associations.
Errgonomic::Rails.setup_after

class BugTest < Minitest::Test
  def test_optional_attributes
    author = Author.create!(name: 'Cixin Liu')
    assert author.name.present?
    assert author.bio.none?
    book = author.books.create!(title: 'The Three-Body Problem')
    assert book.isbn.none?
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
end
