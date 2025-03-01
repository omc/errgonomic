# frozen_string_literal: true

require_relative "errgonomic/version"

# The semantics here borrow heavily from ActiveSupport. Let's prefer that if
# loaded, otherwise just copypasta the bits we like. Or convince me to make that
# gem a dependency.
if !Object.methods.include?(:blank?)
  require_relative "errgonomic/core_ext/blank"
end

class Object
  # Convenience method to indicate whether we are working with a result.
  # TBD whether we implement some stubs for the rest of the Result API; I want
  # to think about how effectively these map to truthiness or presence.
  def result?
    false
  end

  # Lacking static typing, we are going to want to make it easy to enforce at
  # runtime that a given object is a Result.
  def assert_result!
    return true if result?
    raise Errgonomic::ResultRequiredError
  end
end

module Errgonomic
  class Error < StandardError; end

  class NotPresentError < Error; end

  class TypeMismatchError < Error; end

  class UnwrapError < Error; end

  class ExpectError < Error; end

  class ArgumentError < Error; end

  class ResultRequiredError < Error; end

  module Result
    class Any

      # Indicate that this is some kind of result object. Contrast to
      # Object#result? which is false for all other types.
      def result?
        true
      end

      # A lightweight DSL to invoke code for a result based on whether it is an
      # Ok or Err.
      def match(&block)
        matcher = Matcher.new(self)
        matcher.instance_eval(&block)
        matcher.match
      end

      # Return true if the inner value is an Ok and the result of the block is
      # truthy.
      def ok_and?(&block)
        if ok?
          !!block.call(value)
        else
          false
        end
      end

      # Return true if the inner value is an Err and the result of the block is
      # truthy.
      def err_and?(&block)
        if err?
          !!block.call(value)
        else
          false
        end
      end

      # Return the inner value of an Ok, else raise an exception when Err.
      def unwrap!
        if ok?
          @value
        else
          raise Errgonomic::UnwrapError, "value is an Err"
        end
      end

      # Return the inner value of an Ok, else raise an exception with the given
      # message when Err.
      def expect!(msg)
        if ok?
          @value
        else
          raise Errgonomic::ExpectError, msg
        end
      end

      # Return the inner value of an Err, else raise an exception when Ok.
      def unwrap_err!
        if err?
          @value
        else
          raise Errgonomic::UnwrapError, "value is an Ok"
        end
      end

      # Given another result, return it if the inner result is Ok, else return
      # the inner Err.
      def and(other)
        raise Errgonomic::ArgumentError, "other must be a Result" unless other.is_a?(Errgonomic::Result::Any)
        return self if err?
        other
      end

      # Given a block, evaluate it and return its result if the inner result is
      # Ok, else return the inner Err. This is lazy evaluated, and we
      # pedantically check the type of the block's return value at runtime. This
      # is annoying, sorry, but better than an "undefined method" error.
      # Hopefully it gives your test suite a chance to detect incorrect usage.
      def and_then(&block)
        # raise NotImplementedError, "and_then is not implemented yet"
        return self if err?
        res = block.call(self)
        unless res.is_a?(Errgonomic::Result::Any) || Errgonomic.give_me_ambiguous_downstream_errors?
          raise Errgonomic::ArgumentError, "and_then block must return a Result"
        end
        res
      end

      # Return other if self is Ok, else return the original Err. Raises a
      # pedantic runtime exception if other is not a Result.
      def or(other)
        raise Errgonomic::ArgumentError, "other must be a Result; you might want unwrap_or" unless other.is_a?(Errgonomic::Result::Any)
        return self if ok?
        other
      end

      # Return self if it is Ok, else lazy evaluate the block and return its
      # result. Raises a pedantic runtime check that the block returns a Result.
      # Sorry about that, hopefully it helps your tests. Better than ambiguous
      # downstream "undefined method" errors, probably.
      def or_else(&block)
        return self if ok?
        res = block.call(self)
        unless res.is_a?(Errgonomic::Result::Any) || Errgonomic.give_me_ambiguous_downstream_errors?
          raise Errgonomic::ArgumentError, "or_else block must return a Result"
        end
        res
      end

      # Return the inner value if self is Ok, else return the provided default.
      def unwrap_or(other)
        return value if ok?
        other
      end

      # Return the inner value if self is Ok, else lazy evaluate the block and
      # return its result.
      def unwrap_or_else(&block)
        return value if ok?
        block.call(self)
      end
    end

    class Ok < Any
      attr_accessor :value

      def initialize(value)
        @value = value
      end

      def ok?
        true
      end

      def err?
        false
      end
    end

    class Err < Any
      class Arbitrary; end

      attr_accessor :value

      def initialize(value = Arbitrary)
        @value = value
      end

      def err?
        true
      end

      def ok?
        false
      end
    end

    # This is my first stab at a basic DSL for matching and responding to
    # different Result variants.
    class Matcher
      def initialize(result)
        @result = result
      end

      def ok(&block)
        @ok_block = block
      end

      def err(&block)
        @err_block = block
      end

      def match
        case @result
        when Err
          @err_block.call(@result.value)
        when Ok
          @ok_block.call(@result.value)
        else
          raise Errgonomic::MatcherError, "invalid matcher"
        end
      end
    end
  end

  def self.give_me_ambiguous_downstream_errors?
    @give_me_ambiguous_downstream_errors ||= false
  end

  # You can opt out of the pedantic runtime checks for lazy block evaluation,
  # but not quietly.
  def self.with_ambiguous_downstream_errors(&block)
    original_value = @give_me_ambiguous_downstream_errors
    @give_me_ambiguous_downstream_errors = true
    yield
  ensure
    @give_me_ambiguous_downstream_errors = original_value
  end
end

def Ok(value)
  Errgonomic::Result::Ok.new(value)
end

def Err(value)
  Errgonomic::Result::Err.new(value)
end

class Object
  # Returns the receiver if it is present, otherwise raises a NotPresentError.
  # This method is useful to enforce strong expectations, where it is preferable
  # to fail early rather than risk causing an ambiguous error somewhere else.
  #
  # @param message [String] The error message to raise if the receiver is not present.
  # @return [Object] The receiver if it is present, otherwise raises a NotPresentError.
  def present_or_raise(message)
    raise Errgonomic::NotPresentError, message if blank?
    self
  end

  # Returns the receiver if it is present, otherwise returns the given value. If
  # constructing the default value is expensive, consider using
  # +present_or_else+.
  #
  # @param value [Object] The value to return if the receiver is not present.
  # @return [Object] The receiver if it is present, otherwise the given value.
  def present_or(value)
    # TBD whether this is *too* strict
    if value.class != self.class && self.class != NilClass
      raise Errgonomic::TypeMismatchError, "Type mismatch: default value is a #{value.class} but original was a #{self.class}"
    end

    return self if present?

    value
  end

  # Returns the receiver if it is present, otherwise returns the result of the
  # block. Invoking a block may be preferable to returning a default value with
  # +present_or+, if constructing the default value is expensive.
  #
  # @param block [Proc] The block to call if the receiver is not present.
  # @return [Object] The receiver if it is present, otherwise the result of the block.
  def present_or_else(&block)
    return block.call if blank?
    self
  end

  # Returns the receiver if it is blank, otherwise raises a NotPresentError.
  # This method is helpful to enforce expectations where blank objects are required.
  #
  # @param message [String] The error message to raise if the receiver is not blank.
  # @return [Object] The receiver if it is blank, otherwise raises a NotPresentError.
  def blank_or_raise(message)
    raise Errgonomic::NotPresentError, message unless blank?
    self
  end

  # Returns the receiver if it is blank, otherwise returns the given value.
  #
  # @param value [Object] The value to return if the receiver is not blank.
  # @return [Object] The receiver if it is blank, otherwise the given value.
  def blank_or(value)
    # TBD whether this is *too* strict
    if value.class != self.class && self.class != NilClass
      raise Errgonomic::TypeMismatchError, "Type mismatch: default value is a #{value.class} but original was a #{self.class}"
    end

    return self if blank?

    value
  end

  # Returns the receiver if it is blank, otherwise returns the result of the
  # block.
  #
  # @param block [Proc] The block to call if the receiver is not blank.
  # @return [Object] The receiver if it is blank, otherwise the result of the block.
  def blank_or_else(&block)
    return block.call unless blank?
    self
  end
end
