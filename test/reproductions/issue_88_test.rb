# frozen_string_literal: true

# The Rails integration test owns the connection, the schema and the engine
# wiring for this process; the reproduction adds a table of its own to it.
require_relative '../rails_test'

ActiveRecord::Schema.define do
  create_table 'staff_records', force: :cascade do |t|
    t.boolean :staff_access
    t.integer :credits
    t.string :handle
  end
end

class PlainStaffRecord < ActiveRecord::Base
  self.table_name = 'staff_records'
end

class WrappedStaffRecord < ActiveRecord::Base
  self.table_name = 'staff_records'
  include Errgonomic::Rails::ActiveRecordOptional
end

# Issue #88 claims the Rails-generated `attr?` query method answers true for a
# wrapped `Some(false)` and a wrapped `Some(0)`, because ActiveRecord's
# `query_attribute` reads the wrapped reader and falls through to
# `!value.blank?`, and an Option's blankness is its discriminant. The expected
# value in each case is what an unconverted model answers.
class Issue88QueryAttributeTest < Minitest::Test
  def test_plain_active_record_answers_false_for_an_explicit_false
    refute_predicate PlainStaffRecord.new(staff_access: false), :staff_access?
  end

  def test_a_wrapped_nullable_boolean_false_answers_false
    refute_predicate WrappedStaffRecord.new(staff_access: false), :staff_access?
  end

  def test_plain_active_record_answers_false_for_a_stored_zero
    refute_predicate PlainStaffRecord.new(credits: 0), :credits?
  end

  def test_a_wrapped_nullable_integer_zero_answers_false
    refute_predicate WrappedStaffRecord.new(credits: 0), :credits?
  end

  def test_plain_active_record_answers_false_for_an_empty_string
    refute_predicate PlainStaffRecord.new(handle: ''), :handle?
  end

  def test_a_wrapped_empty_string_answers_false
    refute_predicate WrappedStaffRecord.new(handle: ''), :handle?
  end

  def test_plain_active_record_answers_false_for_nil
    refute_predicate PlainStaffRecord.new, :staff_access?
  end

  def test_a_wrapped_nil_answers_false
    refute_predicate WrappedStaffRecord.new, :staff_access?
  end

  def test_a_wrapped_true_still_answers_true
    assert_predicate WrappedStaffRecord.new(staff_access: true), :staff_access?
  end

  # The generated `attr?` methods dispatch through the private `attribute?`
  # alias rather than `query_attribute`, so both are read here.
  def test_the_private_query_attribute_reader_answers_false
    refute WrappedStaffRecord.new(staff_access: false).send(:query_attribute, 'staff_access')
  end

  def test_the_private_attribute_query_alias_answers_false
    refute WrappedStaffRecord.new(staff_access: false).send(:attribute?, 'staff_access')
  end
end
