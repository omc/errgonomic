# frozen_string_literal: true

require 'active_record'
require 'logger'

require_relative 'lib/errgonomic'
require_relative 'lib/errgonomic/rails'

# The Rails integration patches ActiveRecord as it loads, so examples under
# lib/errgonomic/rails need a live connection and a model to run against.
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = Logger.new(File::NULL)

# One nullable column per type the cast boundary has to map.
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table 'authors', force: :cascade do |t|
    t.string :name
    t.text :bio
  end

  create_table 'articles', force: :cascade do |t|
    t.string :title
    t.references :author
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
  end
end

Errgonomic::Rails.setup_before

class Note < ActiveRecord::Base
  include Errgonomic::Rails::ActiveRecordOptional
end

# An unconverted delegation target: its readers hand back plain values, and
# two of its methods take an argument, a keyword and a block.
class Author < ActiveRecord::Base
  def greeting(salutation, punctuation: '.')
    "#{salutation}, #{name}#{punctuation}"
  end

  def styled_name
    yield(name)
  end
end

# A converted model reads its association as an Option.
class Article < ActiveRecord::Base
  include Errgonomic::Rails::ActiveRecordOptional
  belongs_to :author, optional: true
  delegate_optional :name, to: :author, prefix: true
  delegate_optional :name, to: :author, prefix: :writer
  delegate_optional :bio, to: :author
  delegate_optional :greeting, :styled_name, to: :author, prefix: true
end

# The same records read through a converted model, so the target's own
# reader is already an Option.
class Byline < ActiveRecord::Base
  self.table_name = 'authors'
  include Errgonomic::Rails::ActiveRecordOptional
end

# Unconverted, so the association reader hands back a plain record or nil.
class Draft < ActiveRecord::Base
  self.table_name = 'articles'
  belongs_to :author, optional: true
  belongs_to :byline, class_name: 'Byline', foreign_key: :author_id, optional: true
  delegate_optional :name, to: :author, prefix: true
  delegate_optional :name, to: :byline, prefix: true
end

# Two validators that answer differently for the same wrapped value.
class Memo < ActiveRecord::Base
  self.table_name = 'notes'
  include Errgonomic::Rails::ActiveRecordOptional
  validates :title, presence: true
  validates :body, some: true
end

# yard-doctest sends any expectation that answers nil? to assert_nil, and
# under the Rails integration None() answers it. Compare an expected Option by
# value, so `# => None()` keeps meaning what it says.
module DoctestOptionEquality
  def assert_example(example, expected, actual, bind)
    # An expectation is a literal in the example's own binding, so leaving
    # the other branches to super costs nothing but evaluating it twice.
    return super unless evaluate_with_assertion(expected, bind).is_a?(Errgonomic::Option::Any)

    assert_equal(evaluate_with_assertion(expected, bind), evaluate_with_assertion(actual, bind))
  rescue Minitest::Assertion => e
    add_filepath_to_backtrace(e, example.filepath)
    raise e
  end
end

YARD::Doctest::Example.prepend(DoctestOptionEquality)

# A declared default is cast on its way into a new record rather than assigned
# through a writer.
class DefaultedNote < ActiveRecord::Base
  self.table_name = 'notes'
  attribute :rank, :integer, default: Some(0)
  attribute :title, :string, default: None()
end

# A Proc default is called when the record is built, so what it returns meets
# the column type exactly where a literal default does.
class ProcDefaultedNote < ActiveRecord::Base
  self.table_name = 'notes'
  attribute :title, :string, default: -> { Some('Wanderer') }
end
