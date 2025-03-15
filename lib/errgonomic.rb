# frozen_string_literal: true

require_relative 'errgonomic/version' unless defined?(Errgonomic::VERSION)

# A more opinionated blend with Rails presence.
require_relative 'errgonomic/presence'

# Bring in our Option and Result.
require_relative 'errgonomic/option'
require_relative 'errgonomic/result'

# Errgonomic adds opinionated abstractions to handle errors in a way that blends
# Rust and Ruby ergonomics. This library leans on Rails conventions for some
# presence-related methods; when in doubt, make those feel like Rails. It also
# has an implementation of Option and Result; when in doubt, make those feel
# more like Rust.
module Errgonomic
  class Error < StandardError; end

  class NotPresentError < Error; end

  class TypeMismatchError < Error; end

  class UnwrapError < Error; end

  class ExpectError < Error; end

  class ArgumentError < Error; end

  class ResultRequiredError < Error; end

  class NotComparableError < StandardError; end

  # A little bit of control over how pedantic we are in our runtime type checks.
  def self.give_me_ambiguous_downstream_errors?
    @give_me_ambiguous_downstream_errors ||= false
  end

  # You can opt out of the pedantic runtime checks for lazy block evaluation,
  # but not quietly.
  def self.with_ambiguous_downstream_errors
    original_value = @give_me_ambiguous_downstream_errors
    @give_me_ambiguous_downstream_errors = true
    yield
  ensure
    @give_me_ambiguous_downstream_errors = original_value
  end

  # Lenient inner value comparison means the inner value of a Some or Ok can be
  # compared to some other non-Result or non-Option value.
  def self.lenient_inner_value_comparison?
    @lenient_inner_value_comparison ||= true
  end

  def self.give_me_lenient_inner_value_comparison=(value)
    @lenient_inner_value_comparison = value
  end
end
