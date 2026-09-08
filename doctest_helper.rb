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

# yard-doctest sends any expectation that answers nil? to assert_nil, and
# under the Rails integration None() answers it. Compare an expected Option by
# value, so `# => None()` keeps meaning what it says.
module DoctestOptionEquality
  def assert_example(example, expected, actual, bind)
    value = evaluate_with_assertion(expected, bind)
    return super unless value.is_a?(Errgonomic::Option::Any)

    assert_equal(value, evaluate_with_assertion(actual, bind))
  rescue Minitest::Assertion => e
    add_filepath_to_backtrace(e, example.filepath)
    raise e
  end
end

YARD::Doctest::Example.prepend(DoctestOptionEquality)
