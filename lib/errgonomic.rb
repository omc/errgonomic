# frozen_string_literal: true

require_relative 'errgonomic/version' unless defined?(Errgonomic::VERSION)

# A more opinionated blend with Rails presence.
require_relative 'errgonomic/presence'

# Bring in a subtle and manual type checker.
require_relative 'errgonomic/type'

# Bring in our Option and Result.
require_relative 'errgonomic/option'
require_relative 'errgonomic/result'

# Option-returning lookups for the collections.
require_relative 'errgonomic/core_ext/hash'
require_relative 'errgonomic/core_ext/array'

# Lift booleans into Option and Result.
require_relative 'errgonomic/core_ext/bool'

# Rails fu
require_relative 'errgonomic/rails' if defined?(Rails::Railtie)

# Errgonomic adds opinionated abstractions to handle errors in a way that blends
# Rust and Ruby ergonomics. This library leans on Rails conventions for some
# presence-related methods; when in doubt, make those feel like Rails. It also
# has an implementation of Option and Result; when in doubt, make those feel
# more like Rust.
module Errgonomic
  class Error < StandardError; end

  class TypeError < ::TypeError; end

  class NotPresentError < Error; end

  class TypeMismatchError < Error; end

  # Raised when unwrap! is called on a None or an Err. Carries the Err's
  # inner value so diagnostics can show what actually went wrong.
  class UnwrapError < Error
    attr_reader :value

    def initialize(msg, value = nil)
      super(msg)
      @value = value
    end
  end

  class ExpectError < Error; end

  class ArgumentError < Error; end

  class ResultRequiredError < Error; end

  # Raised when a wrapped ActiveRecord attribute reader re-enters itself on
  # the same record, catching runaway recursion at the first repeated frame
  # instead of a SystemStackError thousands of frames later.
  class RecursiveOptionalReadError < Error; end

  class NotComparableError < StandardError; end

  # Raised when a method missing from Option or Result is called, with a
  # message that teaches the combinators. Subclasses NoMethodError so every
  # rescue path and Ruby-internal probe that expects one keeps working.
  class UnwrappedAccessError < ::NoMethodError; end

  class SerializeError < TypeError; end

  # A little bit of control over how pedantic we are in our runtime type checks.
  # Default is false: we are pedantic and raise errors on type mismatches.
  def self.give_me_ambiguous_downstream_errors?
    !!@give_me_ambiguous_downstream_errors
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
