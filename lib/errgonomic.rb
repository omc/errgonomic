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
  #
  # @example
  #   "foo".result? # => false
  #   Ok("foo").result? # => true
  def result?
    false
  end

  # Lacking static typing, we are going to want to make it easy to enforce at
  # runtime that a given object is a Result.
  #
  # @example
  #   "foo".assert_result! # => raise Errgonomic::ResultRequiredError
  #   Ok("foo").assert_result! # => true
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

      # Equality comparison for Result objects is based on value not reference.
      #
      # @example
      #   Ok("foo") == Ok("foo") # => true
      #   Ok("foo") == Err("foo") # => false
      #   Ok("foo").object_id != Ok("foo").object_id # => true
      def ==(other)
        self.class == other.class && self.value == other.value
      end

      # Indicate that this is some kind of result object. Contrast to
      # Object#result? which is false for all other types.
      # @example
      #   Ok("foo").result? # => true
      #   Err("foo").result? # => true
      #   "foo".result? # => false
      def result?
        true
      end

      # A lightweight DSL to invoke code for a result based on whether it is an
      # Ok or Err.
      #
      # @example
      #   Ok("foo").match do
      #     ok { :foo }
      #     err { :bar }
      #   end # => :foo
      #
      #   Err("foo").match do
      #     ok { :foo }
      #     err { :bar }
      #   end # => :bar
      def match(&block)
        matcher = Matcher.new(self)
        matcher.instance_eval(&block)
        matcher.match
      end

      # Return true if the inner value is an Ok and the result of the block is
      # truthy.
      #
      # @example
      #   Ok("foo").ok_and? { |_| true } # => true
      #   Ok("foo").ok_and? { |_| false } # => false
      #   Err("foo").ok_and? { |_| true } # => false
      #   Err("foo").ok_and? { |_| false } # => false
      def ok_and?(&block)
        if ok?
          !!block.call(value)
        else
          false
        end
      end

      # Return true if the inner value is an Err and the result of the block is
      # truthy.
      #
      # @example
      #   Ok("foo").err_and? { |_| true } # => false
      #   Ok("foo").err_and? { |_| false } # => false
      #   Err("foo").err_and? { |_| true } # => true
      #   Err("foo").err_and? { |_| false } # => false
      def err_and?(&block)
        if err?
          !!block.call(value)
        else
          false
        end
      end

      # Return the inner value of an Ok, else raise an exception when Err.
      #
      # @example
      #   Ok("foo").unwrap! # => "foo"
      #   Err("foo").unwrap! # => raise Errgonomic::UnwrapError, "value is an Err"
      def unwrap!
        if ok?
          @value
        else
          raise Errgonomic::UnwrapError, "value is an Err"
        end
      end

      # Return the inner value of an Ok, else raise an exception with the given
      # message when Err.
      #
      # @example
      #   Ok("foo").expect!("foo") # => "foo"
      #   Err("foo").expect!("foo") # => raise Errgonomic::ExpectError, "foo"
      def expect!(msg)
        if ok?
          @value
        else
          raise Errgonomic::ExpectError, msg
        end
      end

      # Return the inner value of an Err, else raise an exception when Ok.
      #
      # @example
      #   Ok("foo").unwrap_err! # => raise Errgonomic::UnwrapError, "value is an Ok"
      #   Err("foo").unwrap_err! # => "foo"
      def unwrap_err!
        if err?
          @value
        else
          raise Errgonomic::UnwrapError, "value is an Ok"
        end
      end

      # Given another result, return it if the inner result is Ok, else return
      # the inner Err. Raise an exception if the other value is not a Result.
      #
      # @example
      #   Ok("foo").and(Ok("bar")) # => Ok("bar")
      #   Ok("foo").and(Err("bar")) # => Err("bar")
      #   Err("foo").and(Ok("bar")) # => Err("foo")
      #   Err("foo").and(Err("bar")) # => Err("foo")
      #   Ok("foo").and("bar") # => raise Errgonomic::ArgumentError, "other must be a Result"
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

      # Return other if self is Err, else return the original Option. Raises a
      # pedantic runtime exception if other is not a Result.
      #
      # @example
      #   Err("foo").or(Ok("bar")) # => Ok("bar")
      #   Err("foo").or(Err("baz")) # => Err("baz")
      #   Err("foo").or("bar") # => raise Errgonomic::ArgumentError, "other must be a Result; you might want unwrap_or"
      def or(other)
        raise Errgonomic::ArgumentError, "other must be a Result; you might want unwrap_or" unless other.is_a?(Errgonomic::Result::Any)
        return other if err?
        self
      end

      # Return self if it is Ok, else lazy evaluate the block and return its
      # result. Raises a pedantic runtime check that the block returns a Result.
      # Sorry about that, hopefully it helps your tests. Better than ambiguous
      # downstream "undefined method" errors, probably.
      #
      # @example
      #   Ok("foo").or_else { Ok("bar") } # => Ok("foo")
      #   Err("foo").or_else { Ok("bar") } # => Ok("bar")
      #   Err("foo").or_else { Err("baz") } # => Err("baz")
      #   Err("foo").or_else { "bar" } # => raise Errgonomic::ArgumentError, "or_else block must return a Result"
      def or_else(&block)
        return self if ok?
        res = block.call(self)
        unless res.is_a?(Errgonomic::Result::Any) || Errgonomic.give_me_ambiguous_downstream_errors?
          raise Errgonomic::ArgumentError, "or_else block must return a Result"
        end
        res
      end

      # Return the inner value if self is Ok, else return the provided default.
      #
      # @example
      #   Ok("foo").unwrap_or("bar") # => "foo"
      #   Err("foo").unwrap_or("bar") # => "bar"
      def unwrap_or(other)
        return value if ok?
        other
      end

      # Return the inner value if self is Ok, else lazy evaluate the block and
      # return its result.
      #
      # @example
      #   Ok("foo").unwrap_or_else { "bar" } # => "foo"
      #   Err("foo").unwrap_or_else { "bar" } # => "bar"
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

      # Ok is always ok
      #
      # @example
      #   Ok("foo").ok? # => true
      def ok?
        true
      end

      # Ok is never err
      #
      # @example
      #   Ok("foo").err? # => false
      def err?
        false
      end
    end

    class Err < Any
      class Arbitrary; end

      attr_accessor :value

      # Err may be constructed without a value, if you want.
      #
      # @example
      #   Err("foo").value # => "foo"
      #   Err().value # => Arbitrary
      def initialize(value = Arbitrary)
        @value = value
      end

      # Err is always err
      #
      # @example
      #   Err("foo").err? # => true
      def err?
        true
      end

      # Err is never ok
      #
      # @example
      #   Err("foo").ok? # => false
      def ok?
        false
      end
    end

    # This is my first stab at a basic DSL for matching and responding to
    # different Result variants.
    #
    # @example
    #   Err("foo").match do
    #     ok { :ok }
    #     err { :err }
    #   end # => :err
    #
    #   Ok("foo").match do
    #     ok { :ok }
    #     err { :err }
    #   end # => :ok
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

  module Option
    class Any

      def ==(other)
        return true if self.none? && other.none?
        return true if self.some? && other.some? && self.value == other.value
        false
      end

      # return true if the contained value is Some and the block returns truthy
      #
      # @example
      #   Some(1).some_and { |x| x > 0 } # => true
      #   Some(0).some_and { |x| x > 0 } # => false
      #   None().some_and { |x| x > 0 } # => false
      def some_and(&block)
        return false if none?
        !! block.call(self.value)
      end

      # return true if the contained value is None or the block returns truthy
      #
      # @example
      #   None().none_or { false } # => true
      #   Some(1).none_or { |x| x > 0 } # => true
      #   Some(1).none_or { |x| x < 0 } # => false
      def none_or(&block)
        return true if none?
        !! block.call(self.value)
      end

      # return an Array with the contained value, if any
      # @example
      #   Some(1).to_a # => [1]
      #   None().to_a # => []
      def to_a
        return [] if none?
        [value]
      end

      # returns the inner value if present, else raises an error
      # @example
      #   Some(1).unwrap! # => 1
      #   None().unwrap! # => raise Errgonomic::UnwrapError, "cannot unwrap None"
      def unwrap!
        raise Errgonomic::UnwrapError, "cannot unwrap None" if none?
        value
      end

      # returns the inner value if pressent, else raises an error with the given
      # message
      # @example
      #   Some(1).expect!("msg") # => 1
      #   None().expect!("msg") # => raise Errgonomic::ExpectError, "msg"
      def expect!(msg)
        raise Errgonomic::ExpectError, msg if none?
        value
      end

      # returns the inner value if present, else returns the default value
      # @example
      #   Some(1).unwrap_or(2) # => 1
      #   None().unwrap_or(2) # => 2
      def unwrap_or(default)
        return default if none?
        value
      end

      # returns the inner value if present, else returns the result of the
      # provided block
      # @example
      #   Some(1).unwrap_or_else { 2 } # => 1
      #   None().unwrap_or_else { 2 } # => 2
      def unwrap_or_else(&block)
        return block.call if none?
        value
      end

      # Calls a function with the inner value, if Some, but returns the original
      # option. In Rust, this is "inspect" but that clashes with Ruby
      # conventions. We call this "tap_some" to avoid further clashing with
      # "tap."
      #
      # @example
      #   tapped = false
      #   Some(1).tap_some { |x| tapped = x } # => Some(1)
      #   tapped # => 1
      #   tapped = false
      #   None().tap_some { tapped = true } # => None()
      #   tapped # => false
      def tap_some(&block)
        block.call(value) if some?
        self
      end

      # Maps the Option to another Option by applying a function to the
      # contained value (if Some) or returns None. Raises a pedantic exception
      # if the return value of the block is not an Option.
      # @example
      #   Some(1).map { |x| Some(x + 1) } # => Some(2)
      #   Some(1).map { |x| None() } # => None()
      #   None().map { Some(1) } # => None()
      #   Some(1).map { :foo } # => raise Errgonomic::ArgumentError, "block must return an Option"
      def map(&block)
        return self if none?
        res = block.call(value)
        unless res.is_a?(Errgonomic::Option::Any) || Errgonomic.give_me_ambiguous_downstream_errors?
          raise ArgumentError, "block must return an Option"
        end
        res
      end

      # Returns the provided default (if none), or applies a function to the
      # contained value (if some). If you want lazy evaluation for the provided
      # value, use +map_or_else+.
      #
      # @example
      #   None().map_or(1) { 100 } # => 1
      #   Some(1).map_or(1) { |x| x + 1 } # => 2
      #   Some("foo").map_or(0) { |str| str.length } # => 3
      def map_or(default, &block)
        return default if none?
        block.call(value)
      end

      # Computes a default from the given Proc if None, or applies the block to
      # the contained value (if Some).
      #
      # @example
      #   None().map_or_else(-> { :foo }) { :bar } # => :foo
      #   Some("str").map_or_else(-> { 100 }) { |str| str.length } # => 3
      def map_or_else(proc, &block)
        return proc.call if none?
        block.call(value)
      end

      # convert the option into a result where Some is Ok and None is Err
      # @example
      #   None().ok # => Err()
      #   Some(1).ok # => Ok(1)
      def ok
        return Errgonomic::Result::Ok.new(value) if some?
        Errgonomic::Result::Err.new
      end

      # Transforms the option into a result, mapping Some(v) to Ok(v) and None to Err(err)
      #
      # @example
      #   None().ok_or("wow") # => Err("wow")
      #   Some(1).ok_or("such err") # => Ok(1)
      def ok_or(err)
        return Errgonomic::Result::Ok.new(value) if some?
        Errgonomic::Result::Err.new(err)
      end

      # Transforms the option into a result, mapping Some(v) to Ok(v) and None to Err(err).
      # TODO: block or proc?
      #
      # @example
      #   None().ok_or_else { "wow" } # => Err("wow")
      #   Some(1).ok_or_else { "such err" } # => Ok(1)
      def ok_or_else(&block)
        return Errgonomic::Result::Ok.new(value) if some?
        Errgonomic::Result::Err.new(block.call)
      end

      # TODO:
      # and
      # and_then
      # filter
      # or
      # or_else
      # xor
      # insert
      # get_or_insert
      # get_or_insert_with
      # take
      # take_if
      # replace
      # zip
      # zip_with

    end

    class Some < Any
      attr_accessor :value
      def initialize(value)
        @value = value
      end
      def some?; true; end
      def none?; false; end
    end
    class None < Any
      def some?; false; end
      def none?; true; end
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

def Err(value = Errgonomic::Result::Err::Arbitrary)
  Errgonomic::Result::Err.new(value)
end

def Some(value)
  Errgonomic::Option::Some.new(value)
end

def None()
  Errgonomic::Option::None.new()
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
