# frozen_string_literal: true

# The Rails integration test owns the connection, the schema and the engine
# wiring for this process; the reproduction adds tables of its own to it.
require_relative '../rails_test'

ActiveRecord::Schema.define do
  create_table 'probe_tiers', force: :cascade do |t|
    t.boolean :enterprise
  end

  create_table 'probe_accounts', force: :cascade do |t|
    t.references :probe_tier
  end
end

class ProbeTier < ActiveRecord::Base
  self.table_name = 'probe_tiers'
end

class ProbeAccount < ActiveRecord::Base
  self.table_name = 'probe_accounts'
  belongs_to :probe_tier, optional: true
  include Errgonomic::Rails::ActiveRecordOptional
  delegate_optional :enterprise?, to: :probe_tier
end

# The contract delegate_optional is a swap for, on a model that is not
# converted, so the two answers for the same shape sit side by side.
class PlainProbeAccount < ActiveRecord::Base
  self.table_name = 'probe_accounts'
  belongs_to :probe_tier, optional: true
  delegate :enterprise?, to: :probe_tier, allow_nil: true
end

# Issue #89 claims a delegated predicate answers Some(false) for a false
# target and None for an absent one, both of which are truthy, so
# `if account.enterprise?` takes the true branch with no exception raised.
class Issue89DelegatedPredicateTest < Minitest::Test
  def setup
    @enterprise = ProbeTier.create!(enterprise: true)
    @hobby = ProbeTier.create!(enterprise: false)
  end

  def test_the_issues_example_on_a_true_target
    assert_equal 'Some(true)', ProbeAccount.new(probe_tier: @enterprise).enterprise?.inspect
  end

  def test_the_issues_example_on_a_false_target
    assert_equal 'Some(false)', ProbeAccount.new(probe_tier: @hobby).enterprise?.inspect
  end

  def test_the_issues_example_on_an_absent_target
    assert_equal 'None', ProbeAccount.new.enterprise?.inspect
  end

  def test_a_delegated_predicate_on_a_false_target_is_falsey
    account = ProbeAccount.new(probe_tier: @hobby)

    refute account.enterprise?, "took the true branch; the predicate answered #{account.enterprise?.inspect}"
  end

  def test_a_delegated_predicate_on_an_absent_target_is_falsey
    account = ProbeAccount.new

    refute account.enterprise?, "took the true branch; the predicate answered #{account.enterprise?.inspect}"
  end

  def test_a_delegated_predicate_on_a_true_target_is_truthy
    assert ProbeAccount.new(probe_tier: @enterprise).enterprise?
  end

  def test_rails_delegate_allow_nil_answers_a_bare_boolean_for_a_true_target
    assert_equal true, PlainProbeAccount.new(probe_tier: @enterprise).enterprise?
  end

  def test_rails_delegate_allow_nil_answers_a_bare_boolean_for_a_false_target
    assert_equal false, PlainProbeAccount.new(probe_tier: @hobby).enterprise?
  end

  def test_rails_delegate_allow_nil_answers_nil_for_an_absent_target
    assert_nil PlainProbeAccount.new.enterprise?
  end

  # The spelling Sprout fell back to, and the shape the issue's thread
  # proposes the predicate form take.
  def test_some_and_answers_a_bare_boolean_for_every_shape
    assert ProbeAccount.new(probe_tier: @enterprise).probe_tier.some_and?(&:enterprise?)
    refute ProbeAccount.new(probe_tier: @hobby).probe_tier.some_and?(&:enterprise?)
    refute ProbeAccount.new.probe_tier.some_and?(&:enterprise?)
  end
end
