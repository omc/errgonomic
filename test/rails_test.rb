# frozen_string_literal: true

require 'active_record'
require 'action_view'
require 'openssl'
require 'active_storage'
require 'active_storage/reflection'
require 'active_storage/service/disk_service'
require 'active_storage/service/registry'
require 'action_text'
require 'zeitwerk'
require 'minitest/autorun'
require 'logger'
require 'stringio'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/errgonomic/rails'

# ActionText and ActiveStorage are engines, so outside a Rails application
# their models, table prefixes and the macros that declare them are wired up
# by hand. Their own models declare attachments of their own, and the service
# check those run reaches for a Rails application unless the model has yet to
# connect, so they are defined before the connection is established.
engine_loader = Zeitwerk::Loader.new
engine_loader.push_dir(File.join(Gem.loaded_specs.fetch('activestorage').full_gem_path, 'app', 'models'))
engine_loader.push_dir(File.join(Gem.loaded_specs.fetch('actiontext').full_gem_path, 'app', 'models'))
engine_loader.push_dir(File.join(Gem.loaded_specs.fetch('actiontext').full_gem_path, 'app', 'helpers'))
engine_loader.setup

def ActiveStorage.table_name_prefix = 'active_storage_'
def ActionText.table_name_prefix = 'action_text_'

ActiveRecord::Base.include(ActiveStorage::Attached::Model)
ActiveRecord::Base.include(ActiveStorage::Reflection::ActiveRecordExtensions)
ActiveRecord::Reflection.singleton_class.prepend(ActiveStorage::Reflection::ReflectionExtension)
ActiveRecord::Base.include(ActionText::Attribute)
engine_loader.eager_load

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = Logger.new(File::NULL)
ActiveStorage.logger = Logger.new(File::NULL)
# The disk service writes what a test attaches, so the run takes its
# directory away with it rather than leaving one behind under TMPDIR.
storage_root = Dir.mktmpdir
Minitest.after_run { FileUtils.remove_entry(storage_root) }
ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new(test: { service: 'Disk', root: storage_root })
ActiveStorage::Blob.service = ActiveStorage::Blob.services.fetch(:test)

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

  create_table 'profiles', force: :cascade do |t|
    t.string :tagline
    t.references :author
    t.references :agency
    t.timestamps
  end

  create_table 'agencies', force: :cascade do |t|
    t.string :name, null: false
    t.timestamps
  end

  create_table 'citations', force: :cascade do |t|
    t.string :note
    t.references :subject, polymorphic: true
    t.timestamps
  end

  create_table 'awards', force: :cascade do |t|
    t.string :name, null: false
    t.references :author
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
    t.string :access_token, limit: 255
    t.string :handle, limit: 255
    t.timestamps
  end

  create_table 'manuscripts', force: :cascade do |t|
    t.string :title
    t.string :currency
    t.string :status
    t.string :isbn
    t.integer :pages
    t.boolean :accepted
    t.references :author
    t.timestamps
  end

  create_table 'ledgers', force: :cascade do |t|
    t.string :memo
    t.integer :price
    t.timestamps
  end

  create_table 'tags', id: :string, primary_key: :slug, force: :cascade do |t|
    t.string :label
  end

  create_table 'members', force: :cascade do |t|
    t.string :nickname
    t.string :password_digest
    t.timestamps
  end

  # The columns the engines' own migration templates declare, less the
  # indexes, foreign keys and variant records nothing here reads.
  create_table 'action_text_rich_texts', force: :cascade do |t|
    t.string :name, null: false
    t.text :body
    t.references :record, null: false, polymorphic: true, index: false
    t.timestamps
  end

  create_table 'active_storage_blobs', force: :cascade do |t|
    t.string :key, null: false
    t.string :filename, null: false
    t.string :content_type
    t.text :metadata
    t.string :service_name, null: false
    t.bigint :byte_size, null: false
    t.string :checksum
    t.datetime :created_at, null: false
  end

  create_table 'active_storage_attachments', force: :cascade do |t|
    t.string :name, null: false
    t.references :record, null: false, polymorphic: true, index: false
    t.references :blob, null: false
    t.datetime :created_at, null: false
  end

  create_table 'notes', force: :cascade do |t|
    t.boolean :pinned
    t.string :title
    t.text :body
    t.json :meta
    t.integer :rank
    t.float :score
    t.decimal :price
    t.date :due_on
    t.datetime :read_at
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
  has_one :profile, dependent: :destroy
  include Errgonomic::Rails::ActiveRecordOptional
  has_one :award, dependent: :destroy
end

class Profile < ActiveRecord::Base
  belongs_to :author
  belongs_to :agency
end

class Agency < ActiveRecord::Base
end

class Award < ActiveRecord::Base
  belongs_to :author
end

# A has_one declared required asserts the record is there, so its reader is
# left alone: absence is a validation failure rather than a value.
class Publisher < ActiveRecord::Base
  self.table_name = 'authors'
  include Errgonomic::Rails::ActiveRecordOptional
  has_one :profile, required: true, foreign_key: :author_id
end

# A polymorphic belongs_to takes the class it points at from the record
# assigned, so the writer has to reach the record inside the Option before
# either key is written.
class Citation < ActiveRecord::Base
  include Errgonomic::Rails::ActiveRecordOptional
  belongs_to :subject, polymorphic: true, optional: true
end

# A has_one :through assigns by creating or destroying the join record and
# reads the assigned record's own key to do it.
class Contributor < ActiveRecord::Base
  self.table_name = 'authors'
  include Errgonomic::Rails::ActiveRecordOptional
  has_one :profile, foreign_key: :author_id, dependent: :destroy
  has_one :agency, through: :profile
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

# A delegation target whose methods take a positional argument, a keyword
# argument and a block.
class Chronicler < ActiveRecord::Base
  self.table_name = 'authors'

  def greeting(salutation, punctuation: '.')
    "#{salutation}, #{name}#{punctuation}"
  end

  def transformed_name
    yield(name)
  end
end

# A Symbol prefix names the delegated reader, so the model's own method of
# the bare name is not the delegation's to take.
class Almanac < ActiveRecord::Base
  self.table_name = 'books'
  belongs_to :author, class_name: 'Chronicler', optional: true
  include Errgonomic::Rails::ActiveRecordOptional

  def name
    'the almanac itself'
  end

  delegate_optional :name, to: :author, prefix: :acct
end

class Compendium < ActiveRecord::Base
  self.table_name = 'books'
  belongs_to :author, class_name: 'Chronicler', optional: true
  include Errgonomic::Rails::ActiveRecordOptional
  delegate_optional :greeting, :transformed_name, to: :author, prefix: true
end

# Targets named for Ruby keywords: the delegation has to reach them through
# an explicit receiver.
class Edition < ActiveRecord::Base
  self.table_name = 'books'
  include Errgonomic::Rails::ActiveRecordOptional
  delegate_optional :table_name, to: :class, prefix: true

  def next
    Edition.where('id > ?', id).order(:id).first
  end

  delegate_optional :title, to: :next, prefix: true
end

# delegate_optional is available on every model, so it has to work over an
# association reader that hands back a plain record or nil.
class Bulletin < ActiveRecord::Base
  self.table_name = 'books'
  belongs_to :author, class_name: 'Chronicler', optional: true
  delegate_optional :name, to: :author, prefix: true
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

# Encryption surrounds an attribute with machinery of its own, and declares
# itself after the concern is included, as applications write it. A
# deterministic attribute is queryable, and downcase: normalizes it on write.
class Credential < ActiveRecord::Base
  include Errgonomic::Rails::ActiveRecordOptional
  encrypts :access_secret
  encrypts :access_token, deterministic: true
  encrypts :handle, deterministic: true, downcase: true
end

# Nested attributes are assigned through the public reader, and ActiveRecord
# asks whatever it finds there whether it is a new record, so a wrapped
# singular association cannot survive the round trip.
class Editor < ActiveRecord::Base
  self.table_name = 'authors'
  include Errgonomic::Rails::ActiveRecordOptional
  has_one :profile, foreign_key: :author_id
  accepts_nested_attributes_for :profile, allow_destroy: true
end

class Anthology < ActiveRecord::Base
  self.table_name = 'books'
  include Errgonomic::Rails::ActiveRecordOptional
  belongs_to :author, optional: true
  accepts_nested_attributes_for :author
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

# touch: and dependent: reach the associated record after a save or a
# destroy, and a wrapped reader is what they find it through.
class TouchingBook < ActiveRecord::Base
  self.table_name = 'books'
  include Errgonomic::Rails::ActiveRecordOptional
  belongs_to :author, optional: true, touch: true
end

class DependentBook < ActiveRecord::Base
  self.table_name = 'books'
  include Errgonomic::Rails::ActiveRecordOptional
  belongs_to :author, optional: true, dependent: :destroy
end

# An autosaved has_one is destroyed with its parent once it is marked, along
# a path that reads the association's own target rather than the reader.
class CuratedAuthor < ActiveRecord::Base
  self.table_name = 'authors'
  include Errgonomic::Rails::ActiveRecordOptional
  has_one :profile, foreign_key: :author_id, autosave: true
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

# A model's own reader has to survive the wrapping and reach the Option
# through super. These two differ only in where the defs sit relative to the
# include and to the association macro.
class PrefacedBook < ActiveRecord::Base
  self.table_name = 'books'

  def isbn
    super.or_else { Some('unassigned') }
  end

  def author
    super.map(&:name)
  end

  belongs_to :author, optional: true
  include Errgonomic::Rails::ActiveRecordOptional
end

class AnnotatedBook < ActiveRecord::Base
  self.table_name = 'books'
  include Errgonomic::Rails::ActiveRecordOptional
  belongs_to :author, optional: true

  def isbn
    super.or_else { Some('unassigned') }
  end

  def author
    super.map(&:name)
  end
end

# A has_one composes the same way, and a def that never calls super owns
# its value outright.
class AnnotatedAuthor < ActiveRecord::Base
  self.table_name = 'authors'
  include Errgonomic::Rails::ActiveRecordOptional
  has_one :profile, foreign_key: :author_id

  def profile
    super.map(&:tagline)
  end

  def bio
    'undisclosed'
  end
end

# Touching the schema from the class body generates the column wrappers
# before the override below is read.
class EagerlyLoadedBook < ActiveRecord::Base
  self.table_name = 'books'
  include Errgonomic::Rails::ActiveRecordOptional
  load_schema

  def isbn
    super.or_else { Some('unassigned') }
  end
end

# A model below the base class has no include of its own to sit above or
# below, and overrides a wrapped reader the same way.
class Broadsheet < HouseRecord
  self.table_name = 'magazines'

  def issn
    super.or_else { Some('unregistered') }
  end
end

# A layer beneath the wrapper may hand back an Option of its own.
module TrimmedIsbn
  def isbn
    super.to_option.map(&:strip)
  end
end

class TrimmedBook < ActiveRecord::Base
  self.table_name = 'books'
  include TrimmedIsbn
  include Errgonomic::Rails::ActiveRecordOptional
end

# One nullable column per type an attribute writer has to cast, so what an
# Option stores can be compared against what its inner value stores.
class Note < ActiveRecord::Base
  include Errgonomic::Rails::ActiveRecordOptional
end

# ActionText and ActiveStorage read the associations their macros declare
# through code of their own, and has_secure_password reads the digest column
# raw, so each of these readers has to stay a plain value. The macros are
# declared where an application writes them, below the include.
class Member < ActiveRecord::Base
  include Errgonomic::Rails::ActiveRecordOptional
  has_one :award, foreign_key: :author_id
  has_rich_text :body
  has_one_attached :avatar, service: :test
  has_secure_password
end

# A model that has loaded its schema before the macro is declared, so the
# digest column is already wrapped when has_secure_password arrives.
class EagerMember < ActiveRecord::Base
  self.table_name = 'members'
  include Errgonomic::Rails::ActiveRecordOptional
  load_schema
  has_secure_password
end

# The unconverted twin of Note, for what a form renders from the same row.
class PlainNote < ActiveRecord::Base
  self.table_name = 'notes'
end

# A string primary key, where find casting an id it was handed raw fails
# outright rather than coercing the wrapper down a soft-deprecated path.
class Tag < ActiveRecord::Base
  self.primary_key = 'slug'
  include Errgonomic::Rails::ActiveRecordOptional
end

# A declared default is cast on its way into a new record rather than
# assigned through a writer.
class DefaultedNote < ActiveRecord::Base
  self.table_name = 'notes'
  attribute :pinned, :boolean, default: Some(false)
  attribute :rank, :integer, default: Some(0)
  attribute :meta, :json, default: Some({ 'shelf' => 'new' })
  attribute :title, :string, default: None()
end

# An application's own type, casting and serializing a value object of its
# own. It overrides both without calling super, which is what a type written
# against ActiveModel::Type::Value's documented contract does, so no seam
# prepended onto Value stands between it and the value it is handed.
Money = Struct.new(:cents)

class MoneyType < ActiveModel::Type::Value
  def cast(value)
    case value
    when nil then nil
    when Money then value
    when Integer then Money.new(value)
    else raise ArgumentError, "MoneyType cannot cast #{value.class}"
    end
  end

  def serialize(value)
    case value
    when nil then nil
    when Money then value.cents
    when Integer then value
    else raise ArgumentError, "MoneyType cannot serialize #{value.class}"
    end
  end
end

class Ledger < ActiveRecord::Base
  attribute :price, MoneyType.new
  include Errgonomic::Rails::ActiveRecordOptional
end

# A default on a custom type is cast on its way into a new record, by the
# custom type rather than by the one the column would have had.
class DefaultedLedger < ActiveRecord::Base
  self.table_name = 'ledgers'
  attribute :price, MoneyType.new, default: Some(Money.new(500))
end

class UnpricedLedger < ActiveRecord::Base
  self.table_name = 'ledgers'
  attribute :price, MoneyType.new, default: None()
end

# A Proc default is called when the record is built, so what it returns meets
# the column type exactly where a literal default does.
class ProcDefaultedNote < ActiveRecord::Base
  self.table_name = 'notes'
  attribute :title, :string, default: -> { Some('Wanderer') }
  attribute :body, :text, default: -> { None() }
end

# A converted model carrying one validator family per wrapped column, so
# each is asked what it makes of a Some and of a None.
class Manuscript < ActiveRecord::Base
  include Errgonomic::Rails::ActiveRecordOptional
  validates :currency, inclusion: { in: %w[USD EUR] }, allow_nil: true
  validates :status, exclusion: { in: %w[withdrawn] }, allow_nil: true
  validates :isbn, length: { maximum: 13 }, format: { with: /\A[0-9]*\z/ }, allow_nil: true
  validates :pages, numericality: { greater_than: 0 }, allow_nil: true
end

# Validators that weigh a value in other ways: absence asks whether it
# amounts to nothing, acceptance matches it against a literal, comparison
# orders it.
class RetractedManuscript < ActiveRecord::Base
  self.table_name = 'manuscripts'
  include Errgonomic::Rails::ActiveRecordOptional
  validates :status, absence: true
  validates :accepted, acceptance: true
  validates :pages, comparison: { greater_than: 0 }, allow_nil: true
end

# presence and some: ask different questions of the same attribute: whether
# the value amounts to anything, and whether it is there at all.
class SubmittedManuscript < ActiveRecord::Base
  self.table_name = 'manuscripts'
  include Errgonomic::Rails::ActiveRecordOptional
  validates :title, presence: true, some: true
end

# some: is available on any model, so it has to answer for a plain value too.
class PlainManuscript < ActiveRecord::Base
  self.table_name = 'manuscripts'
  validates :title, some: true
end

# A belongs_to without optional: true is required, and Rails validates it
# with a presence validation of its own.
class AttributedManuscript < ActiveRecord::Base
  self.table_name = 'manuscripts'
  self.belongs_to_required_by_default = true
  include Errgonomic::Rails::ActiveRecordOptional
  belongs_to :author
end

# A wrapped has_one validated for presence, the association side of the same
# seam.
class ProfiledAuthor < ActiveRecord::Base
  self.table_name = 'authors'
  include Errgonomic::Rails::ActiveRecordOptional
  has_one :profile, foreign_key: :author_id
  validates :profile, presence: true
end

# Serialization twins over one row: what a conversion changes about a payload
# is whatever these two disagree about.
class SerializedBook < ActiveRecord::Base
  self.table_name = 'books'
  include Errgonomic::Rails::ActiveRecordOptional
  belongs_to :author, optional: true, class_name: 'SerializedAuthor'

  def display_isbn
    isbn.unwrap_or('unassigned')
  end
end

class SerializedAuthor < ActiveRecord::Base
  self.table_name = 'authors'
  include Errgonomic::Rails::ActiveRecordOptional
  has_many :books, class_name: 'SerializedBook', foreign_key: :author_id
end

class PlainBook < ActiveRecord::Base
  self.table_name = 'books'
  belongs_to :author, optional: true, class_name: 'PlainAuthor'

  def display_isbn
    isbn || 'unassigned'
  end
end

class PlainAuthor < ActiveRecord::Base
  self.table_name = 'authors'
  has_many :books, class_name: 'PlainBook', foreign_key: :author_id
end

# Omission is the opt-in, and an application's own base class is where it is
# declared once for every model below.
class TerseRecord < ActiveRecord::Base
  self.abstract_class = true
  include Errgonomic::Rails::ActiveRecordOptional
  errgonomic_serialize_none :omit
end

class TerseBook < TerseRecord
  self.table_name = 'books'
  belongs_to :author, optional: true, class_name: 'SerializedAuthor'

  # A plain method is not a reader a declaration governs, whatever it answers.
  def blurb
    nil
  end
end

# A model below the declaration names the other mode, and gets what a model
# with no declaration anywhere gets.
class VerboseBook < TerseRecord
  self.table_name = 'books'
  errgonomic_serialize_none :null
end

# only: and except: scope the mode to named readers, and a reader outside the
# scope keeps the default.
class SelectiveBook < TerseRecord
  self.table_name = 'books'
  errgonomic_serialize_none :omit, only: %i[isbn]
end

class ExceptedBook < TerseRecord
  self.table_name = 'books'
  errgonomic_serialize_none :omit, except: %i[isbn]
end

# Rails convention puts a concern at the top of a model, but configuration
# reads as well above the include as below it, so it has to work either way.
class EarlyTerseBook < ActiveRecord::Base
  self.table_name = 'books'
  errgonomic_serialize_none :omit
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
  # find_by binds its values outside the predicate builder, so an Option
  # reaches the column type rather than the quoting seam. A regression guard:
  # both of these hold today, and the serialize boundary has to keep them.
  def test_find_by_takes_an_option_on_a_string_or_integer_column
    note = Note.create!(title: 'Ball Lightning', rank: 987)

    assert_equal note.id, Note.find_by(title: Some('Ball Lightning')).id
    assert_equal note.id, Note.find_by(rank: Some(987)).id
  end

  # A json column encodes the value it is given rather than handing it on, so
  # find_by has to meet the Option before the column type does, as where
  # already does.
  def test_find_by_takes_an_option_on_a_json_column
    note = Note.create!(meta: { 'isbn' => '9780765377104' })

    assert_equal note.id, Note.find_by(meta: Some({ 'isbn' => '9780765377104' })).id
  end

  # A None means absent, and find_by asks the statement cache for an equality
  # bind, which can never match a NULL. Unwrapping before find_by decides
  # sends it down the relation path instead, where the predicate builder
  # renders IS NULL, so find_by(col: None()) says what find_by(col: nil) says.
  def test_find_by_with_a_none_asks_for_null
    untitled = Note.create!(body: 'Ball Lightning')

    assert_equal untitled.id, Note.find_by(id: untitled.id, title: None()).id
    assert_equal untitled.id, Note.find_by(id: untitled.id, meta: None()).id
    assert_equal untitled.id, Note.find_by(id: untitled.id, title: nil).id
    assert_nil Note.find_by(id: untitled.id, title: Some('The Dark Forest'))
  end

  # find and exists? bind through the same query attribute find_by does, so a
  # Some has to arrive there as its inner value as well.
  def test_find_and_exists_take_an_option_on_a_primary_key
    genre = Genre.create!(name: 'Sci-Fi')
    book = Book.create!(title: 'The Dark Forest', genre_id: genre.id)

    assert_equal genre.id, Genre.find(book.genre_id).id
    assert Genre.exists?(id: Some(genre.id))
  end

  # find given a list of ids casts each one after the query has run, so an
  # Option in the list has to be unwrapped before it goes in. A relation and
  # an association reach that path without passing the class method.
  def test_find_with_a_list_of_options
    Tag.create!(slug: 'aa', label: 'first')
    Tag.create!(slug: 'bb', label: 'second')
    author = Author.create!(name: 'Cixin Liu')
    ants = Book.create!(title: 'Of Ants and Dinosaurs', author_id: author.id)
    village = Book.create!(title: 'The Village Teacher', author_id: author.id)

    nudges = capture_stderr do
      assert_equal %w[bb aa], Tag.find([Some('bb'), Some('aa')]).map(&:slug)
      assert_equal %w[bb aa], Tag.where.not(label: nil).find([Some('bb'), Some('aa')]).map(&:slug)
      assert_equal [village.id, ants.id], author.books.find([Some(village.id), Some(ants.id)]).map(&:id)
    end

    assert_empty nudges
  end

  # An absent id is no id, so find says what it says for nil rather than
  # naming the wrapper it could not match.
  def test_find_with_a_none_reports_a_missing_id
    error = assert_raises(ActiveRecord::RecordNotFound) { Genre.find(None()) }

    assert_equal 'Couldn\'t find Genre without an ID', error.message
  end

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
    assert_raises(Errgonomic::SerializeError) { Some(5).to_json }
    assert_raises(Errgonomic::SerializeError) { Some(5).as_json }
    assert_raises(Errgonomic::SerializeError) { { a: Some(5) }.to_json }
    assert_raises(Errgonomic::SerializeError) { { a: None() }.to_json }
    assert_raises(Errgonomic::SerializeError) { [Some(5)].to_json }
    assert_raises(Errgonomic::SerializeError) { Ok(5).as_json }
    assert_raises(Errgonomic::SerializeError) { { a: Err(5) }.to_json }
    assert_raises(Errgonomic::SerializeError) { [Ok(5)].to_json }
  end

  # A string is where a wrapper turns into data: a join builds an identity
  # column, an interpolation a hostname, a format a node role. Each reaches
  # the value through to_s, so each refuses.
  def test_a_wrapper_refuses_to_become_a_string
    assert_raises(Errgonomic::SerializeError) { [Some('org'), Some('metrics')].join('/') }
    assert_raises(Errgonomic::SerializeError) { [Some(1), None()].join(',') }
    assert_raises(Errgonomic::SerializeError) { "#{None()}.us-east-1.example" }
    assert_raises(Errgonomic::SerializeError) { "data_#{Some('hot')}" }
    assert_raises(Errgonomic::SerializeError) { None().to_s.split(',') }
    assert_raises(Errgonomic::SerializeError) { format('%s', Some(1)) }
    assert_raises(Errgonomic::SerializeError) { String(Some(1)) }
    assert_raises(Errgonomic::SerializeError) { "outcome: #{Ok(1)}" }
    assert_raises(Errgonomic::SerializeError) { [Err(:x), Ok(1)].join(',') }
    assert_raises(Errgonomic::SerializeError) { format('%s', Err(:x)) }
    assert_raises(Errgonomic::SerializeError) { String(Ok(1)) }
    assert_equal 'Some("hot")', Some('hot').inspect
    assert_equal 'Err(:x)', Err(:x).inspect
  end

  # ActionView's output buffer appends a value through to_s, so a bare
  # <%= reader %> of a Some raises rather than shipping Some(&quot;...&quot;)
  # to a page; the template wraps the refusal as its cause. A None answers
  # nil? under the Rails integration, and the buffer skips a nil before it
  # asks for to_s, so a None renders as nothing.
  def test_a_bare_erb_tag_refuses_a_wrapper
    view = ActionView::Base.with_empty_template_cache.empty
    [Some('visible'), Ok(1), Err(:x)].each do |wrapper|
      error = assert_raises(ActionView::Template::Error) { view.render(inline: '<%= value %>', locals: { value: wrapper }) }
      assert_kind_of Errgonomic::SerializeError, error.cause
    end
    assert_equal '', view.render(inline: '<%= value %>', locals: { value: None() })
  end

  # The json gem and ActiveSupport's as_json both stringify a Hash key with
  # to_s, so the refusal reaches a key position through to_s alone.
  def test_an_option_in_a_hash_key_refuses_to_serialize
    assert_raises(Errgonomic::SerializeError) { { Some(1) => 2 }.to_json }
    assert_raises(Errgonomic::SerializeError) { { Some(1) => 2 }.as_json }
    assert_raises(Errgonomic::SerializeError) { JSON.generate({ Some(1) => 2 }) }
    assert_raises(Errgonomic::SerializeError) { [1, 2, 3].group_by { |i| i.even? ? Some(:even) : None() }.to_json }
    assert_raises(Errgonomic::SerializeError) { [1, 2, 3].group_by { |i| i.even? ? Some(:even) : None() }.as_json }
    assert_raises(Errgonomic::SerializeError) { { Ok(1) => 2 }.as_json }
    assert_raises(Errgonomic::SerializeError) { JSON.generate({ Err(:x) => 2 }) }
  end

  # A converted model's optional association keys a group_by by its reader,
  # and the grouped payload is what reaches JSON.
  def test_a_group_by_over_a_wrapped_reader_refuses_to_serialize
    author = Author.create!(name: 'Ursula K. Le Guin')
    Book.create!(title: 'The Dispossessed', author_id: author.id)
    Book.create!(title: 'Anonymous')

    assert_raises(Errgonomic::SerializeError) { Book.all.group_by(&:author).to_json }
  end

  # A conversion changes what a reader returns, not what a record serializes:
  # the payload has to match the model that was never converted, key for key.
  def test_a_converted_record_serializes_as_the_unconverted_one_does
    author = Author.create!(name: 'Cixin Liu')
    row = Book.create!(title: 'The Dark Forest', isbn: '9780765377104', author_id: author.id)

    assert_equal PlainBook.find(row.id).serializable_hash, SerializedBook.find(row.id).serializable_hash
    assert_equal PlainBook.find(row.id).as_json, SerializedBook.find(row.id).as_json
    assert_equal PlainBook.find(row.id).to_json, SerializedBook.find(row.id).to_json
  end

  # Rails writes an absent value as null, and so does serde unless a field
  # asks otherwise, so a None does too and no declaration is needed to say so.
  def test_a_none_serializes_as_null
    row = Book.create!(title: 'Supernova Era')

    assert_equal PlainBook.find(row.id).as_json, SerializedBook.find(row.id).as_json
    assert_nil SerializedBook.find(row.id).as_json['isbn']
    assert_includes SerializedBook.find(row.id).to_json, '"isbn":null'
  end

  # ActiveSupport recurses through as_json, so a record inside an ordinary
  # payload serializes the way the record itself does.
  def test_a_converted_record_serializes_inside_a_payload
    row = Book.create!(title: 'The Dark Forest')

    assert_equal({ book: PlainBook.find(row.id) }.to_json, { book: SerializedBook.find(row.id) }.to_json)
    assert_equal [PlainBook.find(row.id)].to_json, [SerializedBook.find(row.id)].to_json
  end

  # An included association is fetched through its reader, so a Some
  # serializes as the record's own hash and a None leaves the key out, which
  # is what a nil association does on a model that was never converted.
  def test_an_included_association_serializes_through_the_option
    author = Author.create!(name: 'Cixin Liu')
    shelved = Book.create!(title: 'The Dark Forest', author_id: author.id)
    unshelved = Book.create!(title: 'Supernova Era')

    assert_equal PlainBook.find(shelved.id).as_json(include: :author),
                 SerializedBook.find(shelved.id).as_json(include: :author)
    assert_equal 'Cixin Liu', SerializedBook.find(shelved.id).as_json(include: :author).dig('author', 'name')

    assert_equal PlainBook.find(unshelved.id).as_json(include: :author),
                 SerializedBook.find(unshelved.id).as_json(include: :author)
    refute_includes SerializedBook.find(unshelved.id).as_json(include: :author), 'author'
  end

  # A collection is never an Option, so an included has_many is untouched.
  def test_an_included_has_many_serializes_untouched
    author = Author.create!(name: 'Cixin Liu')
    Book.create!(title: 'The Dark Forest', author_id: author.id)

    assert_equal PlainAuthor.find(author.id).as_json(include: :books),
                 SerializedAuthor.find(author.id).as_json(include: :books)
    titles = SerializedAuthor.find(author.id).as_json(include: :books)['books'].map { |book| book['title'] }

    assert_equal ['The Dark Forest'], titles
  end

  # methods: reads its value straight off the record rather than through the
  # attribute seam, so a wrapped reader named there unwraps one layer and a
  # method that hands back a plain value is left alone.
  def test_a_serialized_method_unwraps_one_layer
    row = Book.create!(title: 'The Dark Forest', isbn: '9780765377104')

    assert_equal PlainBook.find(row.id).as_json(methods: :display_isbn),
                 SerializedBook.find(row.id).as_json(methods: :display_isbn)
    assert_equal '9780765377104', SerializedBook.find(row.id).as_json(methods: :isbn)['isbn']
    assert_equal '9780765377104', SerializedBook.find(row.id).serializable_hash(methods: :isbn)['isbn']
    assert_nil SerializedBook.create!(title: 'Supernova Era').serializable_hash(methods: :isbn)['isbn']
  end

  # Omission is the opt-in, and it drops only the keys the record has no
  # value for: a Some is a value like any other.
  def test_omit_drops_the_keys_a_record_has_no_value_for
    absent = TerseBook.find(Book.create!(title: 'Supernova Era').id).as_json
    present = TerseBook.find(Book.create!(title: 'The Dark Forest', isbn: '9780765377104').id).as_json

    refute_includes absent, 'isbn'
    refute_includes absent, 'published_at'
    assert_equal 'Supernova Era', absent['title']

    assert_equal '9780765377104', present['isbn']
    refute_includes present, 'published_at'
  end

  # A declaration above the include says the same thing as one below it.
  def test_serialize_none_is_declared_on_either_side_of_the_include
    hash = EarlyTerseBook.find(Book.create!(title: 'Supernova Era').id).as_json

    refute_includes hash, 'isbn'
    assert_equal 'Supernova Era', hash['title']
  end

  # Omission governs by reader name wherever the key came from, so a methods:
  # entry naming a wrapped reader goes the way the reader does.
  def test_omit_governs_a_method_entry_by_reader_name
    hash = TerseBook.find(Book.create!(title: 'Supernova Era').id).as_json(methods: %i[isbn blurb])

    refute_includes hash, 'isbn'
    assert_nil hash.fetch('blurb')
  end

  # A model below the declaration says :null and is back to the default.
  def test_a_subclass_declares_its_way_back_to_null
    row = Book.create!(title: 'Supernova Era')

    assert_equal PlainBook.find(row.id).as_json, VerboseBook.find(row.id).as_json
  end

  # A scoped declaration replaces the one it inherits, so a reader it does
  # not name keeps the default rather than the mode above it.
  def test_omit_scoped_to_named_readers
    row = Book.create!(title: 'Supernova Era')
    only = SelectiveBook.find(row.id).as_json
    except = ExceptedBook.find(row.id).as_json

    refute_includes only, 'isbn'
    assert_nil only.fetch('published_at')

    assert_nil except.fetch('isbn')
    refute_includes except, 'published_at'
  end

  # An absent association is left out of a payload either way, and a present
  # one is its record's hash either way.
  def test_omit_leaves_an_absent_association_out
    author = Author.create!(name: 'Cixin Liu')
    shelved = Book.create!(title: 'The Dark Forest', author_id: author.id)
    unshelved = Book.create!(title: 'Supernova Era')

    refute_includes TerseBook.find(unshelved.id).as_json(include: :author), 'author'
    assert_equal 'Cixin Liu', TerseBook.find(shelved.id).as_json(include: :author).dig('author', 'name')
  end

  # A mode the concern does not know would be a silent no-op, so it is
  # refused where it is written.
  def test_an_unknown_serialize_none_mode_is_refused
    error = assert_raises(ArgumentError) { declare_serialize_none(:skip) }

    assert_match(/:null or :omit/, error.message)
  end

  # Two scopes in one declaration cannot both be the set it applies to.
  def test_only_and_except_together_are_refused
    error = assert_raises(ArgumentError) { declare_serialize_none(:omit, only: %i[isbn], except: %i[genre_id]) }

    assert_match(/not both/, error.message)
  end

  # A declaration replaces the one it inherits, so a scoped :null asks for
  # the default on the readers it names and the default on the rest, which
  # is no request at all.
  def test_a_scoped_null_is_refused
    only = assert_raises(ArgumentError) { declare_serialize_none(:null, only: %i[isbn]) }
    except = assert_raises(ArgumentError) { declare_serialize_none(:null, except: %i[isbn]) }

    assert_match(/declare :omit/, only.message)
    assert_match(/declare :omit/, except.message)
  end

  # A model that keeps value-or-nil throughout has nothing to unwrap.
  def test_an_opted_out_model_serializes_unchanged
    row = Zine.create!(title: 'Wired', issn: '1059-1028')

    assert_equal VendorLedger.find(row.id).as_json, PlainZine.find(row.id).as_json
  end

  # A form helper reads its value off the record through the public reader
  # whenever the value did not come from user input, which is every record an
  # edit form loads from the database. Each tag weighs what it finds there its
  # own way, so a form renders what the unconverted twin renders or not at all.
  def test_form_helpers_render_what_an_unconverted_record_renders
    written = Note.create!(title: 'The Redemption of Time', pinned: true, read_at: Time.utc(2026, 7, 31, 12))
    unwritten = Note.create!

    [written.id, unwritten.id].each do |id|
      assert_equal render_note_form(PlainNote.find(id)), render_note_form(Note.find(id))
    end
  end

  # to_option lifts a value that may be nil. An Option is already lifted, and
  # a second lift nests invisibly: Some(Some(x)) still answers some?, so the
  # mistake surfaces far from where it was made.
  def test_to_option_is_idempotent
    assert_equal Some(1), Some(1).to_option
    assert_equal 1, Some(1).to_option.unwrap!
    assert None().to_option.none?
  end

  # The shape an application reaches for around an unwrapped association:
  # lift it, then reach through it for an attribute that is already an Option.
  def test_to_option_composes_through_an_unwrapped_association
    author = Author.create!(name: 'Cixin Liu', bio: 'writes sci-fi')
    shelved = Book.create!(title: 'The Dark Forest', author_id: author.id)
    unshelved = Book.create!(title: 'Supernova Era')

    assert_equal 'writes sci-fi', shelved.author.to_option.and_then(&:bio).unwrap_or('unknown')
    assert_equal 'unknown', unshelved.author.to_option.and_then(&:bio).unwrap_or('unknown')
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

  # A Symbol or String prefix names the reader, as it does for Rails'
  # delegate, and leaves a method of the bare name where it found it.
  def test_a_symbol_prefix_names_the_delegated_reader
    author = Chronicler.create!(name: 'Cixin Liu')
    almanac = Almanac.create!(title: 'Death\'s End', author_id: author.id)

    assert_equal 'Cixin Liu', almanac.acct_name.unwrap!
    assert_equal 'the almanac itself', almanac.name
  end

  # A target named for a Ruby keyword reads as the keyword in the body the
  # delegation is written into.
  def test_a_target_named_for_a_ruby_keyword_delegates
    first = Edition.create!(title: 'Omelas')
    second = Edition.create!(title: 'Semley')

    assert_equal 'books', first.class_table_name.unwrap!
    assert_equal 'Semley', first.next_title.unwrap!
    assert second.next_title.none?
  end

  # A delegation passes on whatever the caller handed it: positional
  # arguments, keyword arguments and a block.
  def test_a_delegated_call_forwards_arguments_and_a_block
    author = Chronicler.create!(name: 'Cixin Liu')
    compendium = Compendium.create!(title: 'Death\'s End', author_id: author.id)

    assert_equal 'Hello, Cixin Liu.', compendium.author_greeting('Hello').unwrap!
    assert_equal 'Hi, Cixin Liu!', compendium.author_greeting('Hi', punctuation: '!').unwrap!
    assert_equal 'CIXIN LIU', compendium.author_transformed_name(&:upcase).unwrap!
  end

  # The target reader is lifted rather than assumed to be an Option, so a
  # model delegates whether or not it has converted.
  def test_a_delegation_lifts_whatever_the_target_reader_returns
    author = Chronicler.create!(name: 'Cixin Liu')

    assert_equal 'Cixin Liu', Bulletin.create!(title: 'Death\'s End', author_id: author.id).author_name.unwrap!
    assert Bulletin.create!(title: 'Supernova Era').author_name.none?
    assert Book.create!(title: 'Supernova Era').author_name.none?
  end

  # An encrypted attribute is a nullable column like any other, and the
  # ciphertext never reaches the reader.
  def test_an_encrypted_attribute_round_trips_as_an_option
    credential = Credential.create!(access_key: 'abc123', access_secret: 'shhh')

    assert_equal 'shhh', credential.reload.access_secret.unwrap!

    credential.access_secret = Some('rotated')
    credential.save!

    assert_equal 'rotated', credential.reload.access_secret.unwrap!
    assert_equal 'abc123', credential.access_key.unwrap!
  end

  def test_an_absent_encrypted_attribute_reads_as_none
    credential = Credential.create!(access_key: 'abc123')

    assert credential.access_secret.none?
    assert credential.reload.access_secret.none?
  end

  # A deterministic attribute encrypts to a stable ciphertext, so a query
  # against it has to reach the same value the writer stored.
  def test_a_deterministic_encrypted_attribute_is_queryable
    credential = Credential.create!(access_key: 'abc123', access_token: 'tok-42')

    assert_equal 'tok-42', credential.reload.access_token.unwrap!
    assert_equal credential.id, Credential.find_by(access_token: 'tok-42').id
    assert_equal credential.id, Credential.where(access_token: Some('tok-42')).first.id
    assert_equal credential.id, Credential.find_by(access_token: Some('tok-42')).id
    assert_nil Credential.find_by(access_token: 'tok-43')
  end

  # downcase: normalizes on the way in, so what was written mixed-case reads
  # back and matches lowercase.
  def test_a_downcased_encrypted_attribute_normalizes_on_write
    credential = Credential.create!(access_key: 'abc123', handle: Some('MixedCase'))

    assert_equal 'mixedcase', credential.reload.handle.unwrap!
    assert_equal credential.id, Credential.find_by(handle: 'MIXEDCASE').id
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

  # A has_one is absent whenever no row points back, so its reader carries
  # the same absence a nullable column does, whichever side of the include
  # it is declared on.
  def test_has_one_reads_as_an_option
    author = Author.create!(name: 'Cixin Liu')

    assert author.profile.none?
    assert author.award.none?

    author.create_profile!(tagline: 'writes sci-fi')
    author.create_award!(name: 'Hugo')

    assert_equal 'writes sci-fi', author.reload.profile.unwrap!.tagline
    assert_equal 'Hugo', author.award.unwrap!.name
  end

  # Absence is representable, so the association's own machinery has to keep
  # working through the wrapper.
  def test_has_one_writes_and_dependent_destroy_still_work
    author = Author.create!(name: 'Cixin Liu')
    author.profile = Profile.new(tagline: 'writes sci-fi')
    author.save!

    assert_equal 'writes sci-fi', author.reload.profile.unwrap!.tagline

    author.destroy!

    assert_equal 0, Profile.where(author_id: author.id).count
  end

  # touch: reads the associated record back through the public reader and
  # asks it to touch itself.
  def test_a_touching_belongs_to_reaches_the_record_inside_the_option
    author = Author.create!(name: 'Cixin Liu')
    Author.where(id: author.id).update_all(updated_at: Time.at(0))

    TouchingBook.create!(title: 'The Dark Forest', author: Some(author))

    assert_operator author.reload.updated_at, :>, Time.at(0)
  end

  def test_a_dependent_belongs_to_destroys_the_record_inside_the_option
    author = Author.create!(name: 'Cixin Liu')
    book = DependentBook.create!(title: 'The Dark Forest', author: Some(author))

    book.destroy!

    assert_nil Author.find_by(id: author.id)
  end

  # Marking the record a wrapped reader hands back still reaches the save.
  def test_an_autosaved_has_one_marked_for_destruction_is_destroyed
    author = CuratedAuthor.create!(name: 'Cixin Liu')
    author.create_profile!(tagline: 'writes sci-fi')
    author.profile.unwrap!.mark_for_destruction
    author.save!

    assert_equal 0, Profile.where(author_id: author.id).count
  end

  # A wrapped reader on one record is the ordinary source for a writer on
  # another, so the writer takes the Option the reader hands back.
  def test_belongs_to_writer_takes_an_option
    author = Author.create!(name: 'Cixin Liu')
    book = Book.create!(title: 'The Dark Forest')

    book.author = Some(author)
    book.save!

    assert_equal author.id, book.reload.author_id.unwrap!

    book.author = None()
    book.save!

    assert book.reload.author.none?
  end

  # Unwrapping is not a loosening of the type check: the wrong class inside a
  # Some is still the wrong class, and the message says which one arrived.
  def test_belongs_to_writer_rejects_a_some_of_the_wrong_class
    book = Book.create!(title: 'The Dark Forest')
    profile = Profile.create!(tagline: 'writes sci-fi')

    error = assert_raises(ActiveRecord::AssociationTypeMismatch) { book.author = Some(profile) }

    assert_match(/Author/, error.message)
    assert_match(/Profile/, error.message)
    refute_match(/Some/, error.message)
  end

  def test_has_one_writer_takes_an_option
    author = Author.create!(name: 'Cixin Liu')

    author.profile = Some(Profile.new(tagline: 'writes sci-fi'))

    assert_equal 'writes sci-fi', author.reload.profile.unwrap!.tagline

    author.profile = None()

    assert author.reload.profile.none?
  end

  def test_has_one_writer_rejects_a_some_of_the_wrong_class
    author = Author.create!(name: 'Cixin Liu')

    error = assert_raises(ActiveRecord::AssociationTypeMismatch) { author.profile = Some(author) }

    assert_match(/Profile/, error.message)
    refute_match(/Some/, error.message)
  end

  # A polymorphic writer takes two keys from one record, so the record has to
  # be in hand before either is written.
  def test_polymorphic_belongs_to_writer_takes_an_option
    author = Author.create!(name: 'Cixin Liu')
    citation = Citation.create!(note: 'foreword')

    citation.subject = Some(author)
    citation.save!

    assert_equal 'Author', citation.reload.subject_type.unwrap!
    assert_equal author.id, citation.subject_id.unwrap!

    citation.subject = None()
    citation.save!

    assert citation.reload.subject.none?
    assert citation.subject_type.none?
    assert citation.subject_id.none?
  end

  # A has_one :through assigns by writing the join row, and reads the
  # assigned record's key to do it.
  def test_has_one_through_writer_takes_an_option
    contributor = Contributor.create!(name: 'Cixin Liu')
    agency = Agency.create!(name: 'Tor')

    contributor.agency = Some(agency)

    assert_equal agency, contributor.reload.agency.unwrap!
    assert_equal agency.id, Profile.find_by(author_id: contributor.id).agency_id

    contributor.agency = None()

    assert contributor.reload.agency.none?
    assert_nil Profile.find_by(author_id: contributor.id)
  end

  def test_has_one_through_writer_rejects_a_some_of_the_wrong_class
    contributor = Contributor.create!(name: 'Cixin Liu')
    book = Book.create!(title: 'The Dark Forest')

    error = assert_raises(ActiveRecord::AssociationTypeMismatch) { contributor.agency = Some(book) }

    assert_match(/Agency/, error.message)
    assert_match(/Book/, error.message)
    refute_match(/Some/, error.message)
    assert_nil Profile.find_by(author_id: contributor.id)
  end

  # The idiom a conversion runs into everywhere: one record's association
  # copied straight onto another's, through the wrapped reader.
  def test_an_association_copied_from_a_wrapped_reader_round_trips
    author = Author.create!(name: 'Cixin Liu')
    book = Book.create!(title: 'The Dark Forest', author_id: author.id)
    other_book = Book.create!(title: 'Death\'s End')

    other_book.author = book.author
    other_book.save!

    assert_equal author, other_book.reload.author.unwrap!
  end

  # An Option assigned through an attribute writer stores what its inner
  # value stores. Boolean is the type with the sharpest edge: a Some is
  # truthy and is not one of ActiveModel's FALSE_VALUES, so a cast that saw
  # the wrapper would read a wrapped false as true.
  def test_a_boolean_writer_takes_an_option
    note = Note.create!(pinned: Some(false))

    assert_equal false, note.reload.pinned.unwrap!

    note.update!(pinned: Some(true))

    assert_equal true, note.reload.pinned.unwrap!

    note.update!(pinned: None())

    assert note.reload.pinned.none?
  end

  def test_a_string_writer_takes_an_option
    note = Note.create!(title: Some('The Dark Forest'), body: Some('a novel'))

    assert_equal 'The Dark Forest', note.reload.title.unwrap!
    assert_equal 'a novel', note.body.unwrap!

    note.update!(title: Some(''), body: None())

    assert_equal '', note.reload.title.unwrap!
    assert note.body.none?
  end

  def test_a_json_writer_takes_an_option
    note = Note.create!(meta: Some({ 'isbn' => '9780765377104' }))

    assert_equal({ 'isbn' => '9780765377104' }, note.reload.meta.unwrap!)

    note.update!(meta: None())

    assert note.reload.meta.none?
  end

  # A numeric writer reaches its value without the soft-deprecated presence
  # helpers, which nudge on stderr.
  def test_a_numeric_writer_takes_an_option_without_a_deprecation_nudge
    note = nil
    nudges = capture_stderr do
      note = Note.create!(rank: Some(0), score: Some(0.0), price: Some(0))
    end

    assert_equal '', nudges
    assert_equal 0, note.reload.rank.unwrap!
    assert_in_delta 0.0, note.score.unwrap!
    assert_equal 0, note.price.unwrap!

    note.update!(rank: Some(3), score: Some(1.5), price: Some(2.25))

    assert_equal 3, note.reload.rank.unwrap!
    assert_in_delta 1.5, note.score.unwrap!
    assert_equal BigDecimal('2.25'), note.price.unwrap!

    note.update!(rank: None(), score: None(), price: None())

    assert note.reload.rank.none?
    assert note.score.none?
    assert note.price.none?
  end

  # A date cast hands an object it does not recognize back unchanged, so the
  # attribute behind the reader is where a surviving wrapper would show.
  def test_a_date_writer_takes_an_option
    due_on = Date.new(2026, 7, 31)
    read_at = Time.utc(2026, 7, 31, 12, 0, 0)
    note = Note.create!(due_on: Some(due_on), read_at: Some(read_at))

    assert_equal due_on, note.attributes['due_on']
    assert_equal read_at, note.attributes['read_at']
    assert_equal due_on, note.reload.due_on.unwrap!
    assert_equal read_at, note.read_at.unwrap!

    note.update!(due_on: None(), read_at: None())

    assert note.reload.due_on.none?
    assert note.read_at.none?
  end

  # Dirty tracking, the before-type-cast reader and attributes read the
  # attribute rather than the reader, so an Option must not survive as far as
  # the attribute.
  def test_an_option_assignment_leaves_raw_values_behind_the_reader
    note = Note.create!
    note.title = Some("Death's End")
    note.pinned = Some(false)

    assert_equal [nil, "Death's End"], note.changes['title']
    assert_equal [nil, false], note.changes['pinned']
    assert_equal "Death's End", note.read_attribute_before_type_cast('title')
    assert_equal false, note.read_attribute_before_type_cast('pinned')
    assert_equal "Death's End", note.attributes['title']

    note.save!

    assert_equal [nil, "Death's End"], note.saved_changes['title']
  end

  # A wrapped reader hands its value straight to another record's writer,
  # which is the copy idiom a conversion leans on.
  def test_an_attribute_copied_from_a_wrapped_reader_round_trips
    note = Note.create!(title: 'The Dark Forest', body: 'a novel', rank: 3, due_on: Date.new(2026, 7, 31))
    other = Note.create!

    other.title = note.title
    other.rank = note.rank
    other.due_on = note.due_on
    other.assign_attributes(body: note.body)
    other.save!

    assert_equal 'The Dark Forest', other.reload.title.unwrap!
    assert_equal 'a novel', other.body.unwrap!
    assert_equal 3, other.rank.unwrap!
    assert_equal Date.new(2026, 7, 31), other.due_on.unwrap!
  end

  # update_all writes through the bind path rather than an attribute writer.
  def test_update_all_takes_an_option
    note = Note.create!(title: 'Supernova Era')

    nudges = capture_stderr do
      Note.where(id: note.id).update_all(
        title: Some("Death's End"), pinned: Some(false), meta: Some({ 'isbn' => '9780765377104' }),
        rank: Some(0), score: Some(1.5), price: Some(2.25)
      )
    end

    assert_equal '', nudges
    assert_equal "Death's End", note.reload.title.unwrap!
    assert_equal false, note.pinned.unwrap!
    assert_equal({ 'isbn' => '9780765377104' }, note.meta.unwrap!)
    assert_equal 0, note.rank.unwrap!
    assert_in_delta 1.5, note.score.unwrap!
    assert_equal BigDecimal('2.25'), note.price.unwrap!

    Note.where(id: note.id).update_all(title: None(), rank: None(), meta: None())

    assert note.reload.title.none?
    assert note.rank.none?
    assert note.meta.none?
  end

  def test_insert_all_takes_an_option
    nudges = capture_stderr do
      Note.insert_all([{ title: Some('Supernova Era'), pinned: Some(false), meta: Some(%w[a b]),
                         rank: Some(3), score: Some(1.5), price: Some(2.25),
                         created_at: Time.now, updated_at: Time.now }])
    end
    note = Note.order(:id).last

    assert_equal '', nudges
    assert_equal 'Supernova Era', note.title.unwrap!
    assert_equal false, note.pinned.unwrap!
    assert_equal %w[a b], note.meta.unwrap!
    assert_equal 3, note.rank.unwrap!
    assert_in_delta 1.5, note.score.unwrap!
    assert_equal BigDecimal('2.25'), note.price.unwrap!
  end

  def test_upsert_takes_an_option
    note = Note.create!(title: 'Supernova Era')

    nudges = capture_stderr do
      Note.upsert({ id: note.id, title: Some("Death's End"), meta: Some({ 'isbn' => '978' }),
                    rank: Some(0), score: Some(1.5), price: Some(2.25),
                    created_at: Time.now, updated_at: Time.now })
    end

    assert_equal '', nudges
    assert_equal "Death's End", note.reload.title.unwrap!
    assert_equal({ 'isbn' => '978' }, note.meta.unwrap!)
    assert_equal 0, note.rank.unwrap!
    assert_in_delta 1.5, note.score.unwrap!
    assert_equal BigDecimal('2.25'), note.price.unwrap!
  end

  # An attribute takes one value, and an Option of one is that value. An
  # Option inside a collection is a different shape, and stays where it is.
  def test_only_a_top_level_option_is_unwrapped_on_assignment
    note = Note.create!(meta: Some([1, 2]))

    assert_equal [1, 2], note.reload.meta.unwrap!

    assert_raises(Errgonomic::SerializeError) { note.update!(meta: [Some(1), 2]) }
  end

  # A default is cast on its way into a new record, without passing a writer.
  def test_a_proc_attribute_default_may_return_an_option
    note = ProcDefaultedNote.new

    assert_equal 'Wanderer', note.title
    assert_nil note.body
  end

  def test_an_attribute_default_takes_an_option
    note = nil
    nudges = capture_stderr { note = DefaultedNote.new }

    assert_equal '', nudges
    assert_equal false, note.pinned
    assert_equal 0, note.rank
    assert_equal({ 'shelf' => 'new' }, note.meta)
    assert_nil note.title
  end

  # A custom type casts the value update_all binds, so an Option on that
  # column has to be unwrapped before the type sees it.
  def test_update_all_takes_an_option_on_a_custom_type
    ledger = Ledger.create!(memo: 'opening')

    Ledger.where(id: ledger.id).update_all(price: Some(Money.new(500)))

    assert_equal Money.new(500), ledger.reload.price.unwrap!
  end

  def test_insert_all_takes_an_option_on_a_custom_type
    Ledger.insert_all([{ memo: 'inserted', price: Some(Money.new(500)),
                         created_at: Time.now, updated_at: Time.now }])

    assert_equal Money.new(500), Ledger.find_by!(memo: 'inserted').price.unwrap!
  end

  def test_upsert_takes_an_option_on_a_custom_type
    ledger = Ledger.create!(memo: 'opening')

    Ledger.upsert({ id: ledger.id, memo: 'opening', price: Some(Money.new(500)),
                    created_at: Time.now, updated_at: Time.now })

    assert_equal Money.new(500), ledger.reload.price.unwrap!
  end

  # A default reaches the custom type's cast without passing a writer.
  def test_an_attribute_default_on_a_custom_type_takes_an_option
    assert_equal Money.new(500), DefaultedLedger.new.price
    assert_nil UnpricedLedger.new.price
  end

  # find_by serializes through the custom type, which is the one boundary a
  # Some reaches on a query rather than on a write.
  def test_find_by_takes_an_option_on_a_custom_type
    ledger = Ledger.create!(memo: 'closing', price: Money.new(1200))

    assert_equal ledger.id, Ledger.find_by(price: Some(Money.new(1200))).id
  end

  # The predicate builder already unwraps a hash condition; unwrapping on
  # assignment must leave that alone.
  def test_where_still_matches_an_option_condition
    note = Note.create!(title: 'Supernova Era', pinned: false)

    assert_equal [note], Note.where(id: note.id, pinned: Some(false)).to_a
    assert_empty Note.where(id: note.id, pinned: Some(true))
    assert_equal [note], Note.where(id: note.id, read_at: None()).to_a
  end

  # ActiveRecord reads the association, asks it whether it is a new record,
  # and assigns through it, so the reader has to stay plain for the whole
  # nested-attributes cycle: build, update, and destroy.
  def test_nested_attributes_on_a_has_one_keep_working
    editor = Editor.create!(name: 'Cixin Liu')

    editor.update!(profile_attributes: { tagline: 'writes sci-fi' })

    assert_equal 'writes sci-fi', editor.reload.profile.tagline

    editor.update!(profile_attributes: { id: editor.profile.id, tagline: 'revised' })

    assert_equal 'revised', editor.reload.profile.tagline

    editor.update!(profile_attributes: { id: editor.profile.id, _destroy: '1' })

    assert_nil editor.reload.profile
  end

  def test_nested_attributes_on_an_optional_belongs_to_keep_working
    anthology = Anthology.create!(title: 'Wandering Earth', author_attributes: { name: 'Cixin Liu' })

    assert_equal 'Cixin Liu', anthology.reload.author.name
  end

  # The unwrapped set is discoverable, so a converted model can say which
  # readers ActiveRecord kept for itself.
  def test_an_association_with_nested_attributes_is_reported_as_unwrapped
    refute_includes Editor.errgonomic_optionals, 'profile'
    refute_includes Anthology.errgonomic_optionals, 'author'
    assert_includes Anthology.errgonomic_optional_exclusions, 'author'
  end

  # required: true says the record is always there, which is a validation,
  # not an absence to represent.
  def test_a_required_has_one_is_left_unwrapped
    publisher = Publisher.create!(name: 'Tor', profile: Profile.new(tagline: 'imprint'))

    assert_equal 'imprint', publisher.reload.profile.tagline
    assert_raises(ActiveRecord::RecordInvalid) { Publisher.create!(name: 'Baen') }
  end

  # ActionText assigns and reads the rich text record through the association
  # its macro declares, so a wrapper there breaks the attribute outright.
  def test_a_rich_text_association_stays_unwrapped
    member = Member.create!(nickname: 'nz', password: 'hunter2')
    member.body = '<h1>Funny times!</h1>'
    member.save!

    assert_equal 'Funny times!', Member.find(member.id).body.to_plain_text
    refute_includes Member.errgonomic_optionals, 'rich_text_body'
  end

  # ActiveStorage reaches the attachment and the blob through the two
  # associations its macro declares, and hands what it finds to its own code.
  def test_an_attachment_association_stays_unwrapped
    member = Member.create!(nickname: 'nz', password: 'hunter2')
    member.avatar.attach(io: StringIO.new('portrait'), filename: 'nz.txt', content_type: 'text/plain')
    attached = Member.find(member.id)

    assert_predicate attached.avatar, :attached?
    assert_equal 'nz.txt', attached.avatar.filename.to_s
    assert_equal 'portrait', attached.avatar.download
    refute_includes Member.errgonomic_optionals, 'avatar_attachment'
    refute_includes Member.errgonomic_optionals, 'avatar_blob'
  end

  # has_secure_password reads the digest column raw and hands it to BCrypt,
  # which has never heard of an Option.
  def test_a_password_digest_stays_unwrapped
    member = Member.create!(nickname: 'nz', password: 'hunter2', password_confirmation: 'hunter2')

    assert Member.find(member.id).authenticate('hunter2')
    refute Member.find(member.id).authenticate('wrong')
    refute_includes Member.errgonomic_optionals, 'password_digest'
  end

  # The macro is ordinarily declared before anything touches the schema, but
  # a model that has already wrapped the column has to hand the reader back
  # when the declaration arrives.
  def test_a_digest_wrapped_before_the_macro_is_taken_back
    member = EagerMember.create!(nickname: 'nz', password: 'hunter2')

    assert EagerMember.find(member.id).authenticate('hunter2')
    refute_includes EagerMember.errgonomic_optionals, 'password_digest'
  end

  # Only what the framework reads for itself is left alone: an ordinary
  # association and an ordinary column on the same model are wrapped as ever.
  def test_a_framework_exclusion_leaves_the_rest_of_the_model_wrapped
    assert_includes Member.errgonomic_optionals, 'award'
    assert_includes Member.errgonomic_optionals, 'nickname'
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

  # A subclass responds to every reader an ancestor wrapped, so what a model
  # reports as wrapped names those too. The per-class set is what the wrapping
  # itself reads, and it stays per class.
  def test_a_subclass_reports_the_readers_it_inherited
    assert_includes Novel.errgonomic_optionals, 'isbn'
    assert_includes Novel.errgonomic_optionals, 'author'
    assert_equal Book.errgonomic_optionals.sort, Novel.errgonomic_optionals.sort
    assert_empty Novel.errgonomic_optional_names
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

  # A wrapped reader and a model's own def of the same name must coexist:
  # the model's def wins and reaches the wrapper through super, whether it
  # is written above the include or below it.
  def test_a_column_reader_defined_before_the_include_composes_with_the_wrapper
    assert_equal Some('unassigned'), PrefacedBook.create!(title: 'Supernova Era').isbn
    assert_equal Some('9780765377104'), PrefacedBook.create!(title: 'Death\'s End', isbn: '9780765377104').isbn
  end

  def test_a_column_reader_defined_after_the_include_composes_with_the_wrapper
    assert_equal Some('unassigned'), AnnotatedBook.create!(title: 'Supernova Era').isbn
    assert_equal Some('9780765377104'), AnnotatedBook.create!(title: 'Death\'s End', isbn: '9780765377104').isbn
  end

  # An association reader written above its macro composes with the wrapper
  # the same way one written below it does.
  def test_an_association_reader_defined_before_the_macro_composes_with_the_wrapper
    author = Author.create!(name: 'Cixin Liu')

    assert_equal 'Cixin Liu', PrefacedBook.create!(title: 'The Dark Forest', author_id: author.id).author.unwrap!
    assert PrefacedBook.create!(title: 'Supernova Era').author.none?
  end

  def test_an_association_reader_defined_after_the_macro_composes_with_the_wrapper
    author = Author.create!(name: 'Cixin Liu')

    assert_equal 'Cixin Liu', AnnotatedBook.create!(title: 'The Dark Forest', author_id: author.id).author.unwrap!
    assert AnnotatedBook.create!(title: 'Supernova Era').author.none?
  end

  def test_a_has_one_override_composes_with_the_wrapper
    author = AnnotatedAuthor.create!(name: 'Cixin Liu')

    assert author.profile.none?

    Profile.create!(author_id: author.id, tagline: 'writes sci-fi')

    assert_equal 'writes sci-fi', author.reload.profile.unwrap!
  end

  # A def that never calls super owns its return value: the wrapper is
  # still installed beneath it, and nothing reaches it.
  def test_a_reader_that_declines_to_call_super_owns_its_value
    assert_equal 'undisclosed', AnnotatedAuthor.create!(name: 'Cixin Liu', bio: 'writes sci-fi').bio
  end

  # Whether the class body has already touched the schema decides when the
  # column wrappers are generated, and an override composes with them either
  # way.
  def test_an_override_is_unaffected_by_when_the_schema_loads
    assert_equal Some('unassigned'), EagerlyLoadedBook.create!(title: 'Supernova Era').isbn
    assert_equal Some('9780765377104'), EagerlyLoadedBook.create!(title: 'Death\'s End', isbn: '9780765377104').isbn
  end

  def test_a_model_below_the_base_class_can_override_a_wrapped_reader
    assert_equal Some('unregistered'), Broadsheet.create!(title: 'Nature').issn
    assert_equal Some('1937-7843'), Broadsheet.create!(title: 'Clarkesworld', issn: '1937-7843').issn
  end

  # An override does not take a reader out of the wrapped set: what a
  # conversion touched is still what the model reports.
  def test_an_overridden_reader_is_still_reported_as_wrapped
    assert_includes AnnotatedBook.errgonomic_optionals, 'isbn'
    assert_includes AnnotatedBook.errgonomic_optionals, 'author'
    assert_includes AnnotatedAuthor.errgonomic_optionals, 'bio'
  end

  # An attribute is never an optional of an optional, so a value that
  # arrives from beneath the wrapper already lifted passes through as it is.
  def test_the_wrapper_lifts_a_value_exactly_one_layer
    book = TrimmedBook.create!(title: "Death's End", isbn: '  9780765377104  ')

    assert_equal '9780765377104', book.isbn.unwrap!
    assert TrimmedBook.create!(title: 'Supernova Era').isbn.none?
  end

  # The wrapper and the override own different rungs of the ancestor chain,
  # which is what lets super reach one from the other.
  def test_a_wrapper_and_an_override_own_different_rungs
    # A column reader exists once the schema has loaded, and asking which
    # readers were wrapped is what loads it.
    Book.errgonomic_optionals

    assert_equal AnnotatedBook, AnnotatedBook.instance_method(:isbn).owner
    assert_equal Book.errgonomic_optional_readers, Book.instance_method(:isbn).owner
  end

  # A validator compares against the value, not the wrapper: an Option is
  # never a member of the list a model spells out.
  def test_inclusion_validates_the_value_inside_a_some
    assert_predicate Manuscript.new(currency: Some('USD')), :valid?
    refute_predicate Manuscript.new(currency: Some('GBP')), :valid?
    assert_predicate Manuscript.new(currency: None()), :valid?
  end

  def test_exclusion_validates_the_value_inside_a_some
    assert_predicate Manuscript.new(status: Some('draft')), :valid?
    refute_predicate Manuscript.new(status: Some('withdrawn')), :valid?
    assert_predicate Manuscript.new(status: None()), :valid?
  end

  # An empty string is absent as far as presence is concerned, and wrapping
  # it does not make it a value.
  def test_presence_rejects_an_empty_string_inside_a_some
    blank = SubmittedManuscript.new(title: Some(''))

    refute_predicate blank, :valid?
    assert_equal ['can\'t be blank'], blank.errors[:title]

    assert_predicate SubmittedManuscript.new(title: Some('Death\'s End')), :valid?
    refute_predicate SubmittedManuscript.new(title: None()), :valid?
  end

  # Both validators reach the value through to_s.
  def test_length_and_format_validate_the_value_inside_a_some
    assert_predicate Manuscript.new(isbn: Some('9780765377104')), :valid?
    refute_predicate Manuscript.new(isbn: Some('97807653771049')), :valid?
    refute_predicate Manuscript.new(isbn: Some('978-0765377')), :valid?
    assert_predicate Manuscript.new(isbn: None()), :valid?
  end

  def test_numericality_validates_the_value_inside_a_some
    assert_predicate Manuscript.new(pages: Some(400)), :valid?
    refute_predicate Manuscript.new(pages: Some(-1)), :valid?
    refute_predicate Manuscript.new(pages: Some('four hundred')), :valid?
    assert_predicate Manuscript.new(pages: None()), :valid?
  end

  # An empty string casts away to nil on an integer column, which allow_nil
  # skips, and wrapping it changes neither step.
  def test_numericality_gives_an_empty_string_the_same_verdict_wrapped_or_not
    assert_equal Manuscript.new(pages: '').valid?, Manuscript.new(pages: Some('')).valid?
  end

  # An application's own validator reads through the same seam, so it is
  # handed the value like every validator Rails ships.
  def test_a_custom_validator_receives_the_value_inside_a_some
    seen = []
    audited = Class.new(ActiveRecord::Base) do
      def self.name = 'AuditedManuscript'
      self.table_name = 'manuscripts'
      include Errgonomic::Rails::ActiveRecordOptional
    end
    audited.validates_each(:title) { |_record, _attribute, value| seen << value }

    audited.new(title: Some('Death\'s End')).valid?
    audited.new(title: None()).valid?

    assert_equal ["Death's End", nil], seen
  end

  # An empty string amounts to nothing, which is what absence asks about.
  def test_absence_weighs_the_value_inside_a_some
    assert_predicate RetractedManuscript.new(status: Some('')), :valid?
    refute_predicate RetractedManuscript.new(status: Some('withdrawn')), :valid?
    assert_predicate RetractedManuscript.new(status: None()), :valid?
  end

  # Acceptance matches the value against a literal, which no wrapper equals.
  def test_acceptance_matches_the_value_inside_a_some
    assert_predicate RetractedManuscript.new(accepted: Some(true)), :valid?
    refute_predicate RetractedManuscript.new(accepted: Some(false)), :valid?
    assert_predicate RetractedManuscript.new(accepted: None()), :valid?
  end

  # Comparison orders the value against a bound, which an Option cannot be
  # ordered against.
  def test_comparison_orders_the_value_inside_a_some
    assert_predicate RetractedManuscript.new(pages: Some(400)), :valid?
    refute_predicate RetractedManuscript.new(pages: Some(-1)), :valid?
    assert_predicate RetractedManuscript.new(pages: None()), :valid?
  end

  # The presence validation Rails adds for a required belongs_to reads the
  # association through the same seam.
  def test_a_required_belongs_to_reports_a_missing_record
    author = Author.create!(name: 'Cixin Liu')
    missing = AttributedManuscript.new(author: None())

    refute_predicate missing, :valid?
    assert_equal ['must exist'], missing.errors[:author]

    assert_predicate AttributedManuscript.new(author: Some(author)), :valid?
  end

  def test_a_presence_validated_has_one_reports_a_missing_record
    author = ProfiledAuthor.new(name: 'Cixin Liu')

    refute_predicate author, :valid?
    assert_equal ['can\'t be blank'], author.errors[:profile]

    author.profile = Profile.new(tagline: 'writes sci-fi')

    assert_predicate author, :valid?
  end

  # some: asks only whether the value is there, which is what separates it
  # from presence, and it asks it of any model: a plain value is a value.
  def test_some_asks_whether_the_value_is_there
    blank = SubmittedManuscript.new(title: Some(''))
    blank.valid?

    refute_includes blank.errors[:title], 'is invalid'

    absent = SubmittedManuscript.new(title: None())
    absent.valid?

    assert_includes absent.errors[:title], 'is invalid'

    assert_predicate PlainManuscript.new(title: 'Death\'s End'), :valid?
    refute_predicate PlainManuscript.new(title: nil), :valid?
  end

  # Every wrapped column of an unsaved record is None, and validation walks
  # all of them.
  def test_validating_a_converted_record_with_no_validations_does_not_raise
    assert_predicate Note.new, :valid?
  end

  # The nudge names the method the caller wrote, bang and all. It fires once
  # per process, so this asks for it back before listening.
  def test_the_present_or_raise_nudge_names_the_method_with_its_bang
    Errgonomic::Option::Any::NUDGED.delete('present_or_raise!')

    nudges = capture_stderr do
      assert_raises(Errgonomic::NotPresentError) { None().present_or_raise!('no bio') }
    end

    assert_includes nudges, '`present_or_raise!`'
  end

  # ActiveSupport's Object#try asks respond_to?, which an Option answers
  # false for anything it does not define, so try on a wrapper is a silent
  # nil unless the Option sends it to the value it holds.
  def test_try_reaches_the_value_inside_a_some
    book = Book.create!(title: 'The Dark Forest', isbn: ' 9780765377081 ')

    assert_equal '9780765377081', book.isbn.try(:strip)
  end

  # Rails' try answers nil for a method the value does not have, and so does
  # this one.
  def test_try_answers_nil_for_a_method_the_value_does_not_have
    book = Book.create!(title: 'The Dark Forest', isbn: '9780765377081')

    assert_nil book.isbn.try(:no_such_method)
  end

  def test_try_on_a_none_is_nil
    book = Book.create!(title: 'The Dark Forest')

    assert_nil book.isbn.try(:strip)
    assert_nil(book.isbn.try { |isbn| isbn.to_s.strip })
  end

  def test_try_yields_the_value_to_a_block
    assert_equal 'THE DARK FOREST', Some('The Dark Forest').try(&:upcase)
    assert_equal(6, Some(2).try { |pages| pages * 3 })
  end

  def test_try_forwards_arguments_and_keywords_to_the_value
    greeter = Class.new do
      def greeting(salutation, punctuation: '.')
        "#{salutation}, reader#{punctuation}"
      end
    end.new

    assert_equal 'Hello, reader!', Some(greeter).try(:greeting, 'Hello', punctuation: '!')
  end

  # try! is Rails' strict variant: absence is still nil, a missing method is
  # not.
  def test_try_bang_raises_where_try_answers_nil
    assert_equal 'BOB', Some('bob').try!(:upcase)
    assert_nil None().try!(:upcase)
    assert_raises(NoMethodError) { Some('bob').try!(:no_such_method) }
  end

  private

  def declare_serialize_none(mode, **scope)
    Class.new(ActiveRecord::Base) do
      self.table_name = 'books'
      errgonomic_serialize_none(mode, **scope)
    end
  end

  # One tag per way a builder weighs the value it reads: a string rendered
  # into the field, a boolean asked whether it is checked, a time formatted.
  def render_note_form(record)
    ActionView::Base.empty.form_with(model: record, url: '/notes', scope: :note) do |form|
      form.text_field(:title) + form.check_box(:pinned) + form.datetime_local_field(:read_at)
    end
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  def deeper(frames, &block)
    return block.call if frames.zero?

    deeper(frames - 1, &block)
  end
end
