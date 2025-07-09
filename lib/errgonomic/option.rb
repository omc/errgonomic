# frozen_string_literal: true

module Errgonomic
  module Option
    # The base class for all options. Some and None are subclasses.
    #
    class Any
      # def method_missing(_name, *_args)
      #   raise 'do it right noob'
      # end

      # An option of the same type with an equal inner value is equal.
      #
      # Because we're going to monkey patch this into other libraries Rails, we
      # allow some "pass through" functionality into the inner value of a Some,
      # such as comparability here.
      #
      # TODO: does None == null?
      #
      # strict:
      #   Some(1) == 1 # => raise Errgonomic::NotComparableError, "Cannot compare Errgonomic::Option::Some with Integer"
      #
      # @example
      #   Some(1) == Some(1) # => true
      #   Some(1) == Some(2) # => false
      #   Some(1) == None() # => false
      #   None() == None() # => true
      #   Some(1) == 1 # => false
      #   None() == nil # => false
      def ==(other)
        return false if self.class != other.class
        return true if none?

        value == other.value
      end

      # @example
      #   measurement = Errgonomic::Option::Some.new(1)
      #   case measurement
      #   in Errgonomic::Option::Some, value
      #     "Measurement is #{measurement.value}"
      #   in Errgonomic::Option::None
      #     "Measurement is not available"
      #   else
      #     "not matched"
      #   end # => "Measurement is 1"
      def deconstruct
        return [self, value] if some?

        [Errgonomic::Option::None]
      end

      # return true if the contained value is Some and the block returns truthy
      #
      # @example
      #   Some(1).some_and { |x| x > 0 } # => true
      #   Some(0).some_and { |x| x > 0 } # => false
      #   None().some_and { |x| x > 0 } # => false
      def some_and(&block)
        return false if none?

        !!block.call(value)
      end

      alias some_and? some_and

      # return true if the contained value is None or the block returns truthy
      #
      # @example
      #   None().none_or { false } # => true
      #   Some(1).none_or { |x| x > 0 } # => true
      #   Some(1).none_or { |x| x < 0 } # => false
      def none_or(&block)
        return true if none?

        !!block.call(value)
      end

      alias none_or? none_or

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
        raise Errgonomic::UnwrapError, 'cannot unwrap None' if none?

        value
      end

      # returns the inner value if pressent, else raises an error with the given
      # message
      # @example
      #   Some(1).expect!("msg") # => 1
      #   None().expect!("here's why this failed") # => raise Errgonomic::ExpectError, "here's why this failed"
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

      # # returns the inner value if present, else returns the default value
      # # @example
      # #   Some(1).unwrap_or(2) # => 1
      # #   None().unwrap_or(2) # => 2
      # def unwrap_or_default
      #   self.class.respond_to?(:default) or raise
      #   return self.class.default if none?
      #   value
      # end

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
      #
      # @example
      #   Some(1).map { |x| x + 1 } # => Some(2)
      #   None().map { |x| x + 1 } # => None()
      def map(&block)
        return self if none?

        Some(block.call(value))
      end

      # Returns the provided default (if none), or applies a function to the
      # contained value (if some). If you want lazy evaluation for the provided
      # value, use +map_or_else+.
      #
      # @example
      #   None().map_or(1) { 100 } # => Some(1)
      #   Some(1).map_or(100) { |x| x + 1 } # => Some(2)
      #   Some("foo").map_or(0) { |str| str.length } # => Some(3)
      def map_or(default, &block)
        return Some(default) if none?

        Some(block.call(value))
      end

      # Computes a default from the given Proc if None, or applies the block to
      # the contained value (if Some).
      #
      # @example
      #   None().map_or_else(-> { :foo }) { :bar } # => Some(:foo)
      #   Some("str").map_or_else(-> { 100 }) { |str| str.length } # => Some(3)
      #   None().map_or_else( -> { nil }) { |str| str.length } # => None()
      def map_or_else(proc, &block)
        if none?
          val = proc.call
          return val ? Some(val) : None()
        end

        Some(block.call(value))
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
      #   Some("foo").ok_or_else { "such err" } # => Ok("foo")
      def ok_or_else(&block)
        return Errgonomic::Result::Ok.new(value) if some?

        Errgonomic::Result::Err.new(block.call)
      end

      # Returns the option if it contains a value, otherwise returns the provided Option. Returns an Option.
      #
      # @example
      #   None().or(Some(1)) # => Some(1)
      #   Some(2).or(Some(3)) # => Some(2)
      #   None().or(2) # => raise Errgonomic::ArgumentError.new, "other must be an Option, was Integer"
      def or(other)
        raise ArgumentError, "other must be an Option, was #{other.class.name}" unless other.is_a?(Any)

        return self if some?

        other
      end

      # Returns the option if it contains a value, otherwise calls the block and returns the result. Returns an Option.
      #
      # @example
      #   None().or_else { Some(1) } # => Some(1)
      #   Some(2).or_else { Some(3) } # => Some(2)
      #   None().or_else { 2 } # => raise Errgonomic::ArgumentError.new, "block must return an Option, was Integer"
      def or_else(&block)
        return self if some?

        val = block.call
        if !val.is_a?(Errgonomic::Option::Any) && Errgonomic.give_me_ambiguous_downstream_errors?
          raise Errgonomic::ArgumentError.new, "block must return an Option, was #{val.class.name}"
        end

        val
      end

      # If self is Some, return the provided other Option.
      #
      # @example
      #   None().and(Some(1)) # => None()
      #   Some(2).and(Some(3)) # => Some(3)
      def and(other)
        return self if none?

        other
      end

      # If self is Some, call the given block and return its value. Block most return an Option.
      #
      # @example
      #   None().and_then { Some(1) } # => None()
      #   Some(2).and_then { Some(3) } # => Some(3)
      def and_then(&block)
        return self if none?

        val = block.call
        if Errgonomic.give_me_ambiguous_downstream_errors? && !val.is_a?(Errgonomic::Option::Any)
          raise Errgonomic::ArgumentError.new, "block must return an Option, was #{val.class.name}"
        end

        val
      end

      # Zips self with another Option.
      #
      # If self is Some(s) and other is Some(o), this method returns
      # Some([s, o]). Otherwise, None is returned.
      #
      # @example
      #   None().zip(Some(1)) # => None()
      #   Some(1).zip(None()) # => None()
      #   Some(2).zip(Some(3)) # => Some([2, 3])
      def zip(other)
        return None() unless some? && other.some?

        Some([value, other.value])
      end

      # Zip two options using the block passed. If self is Some and Other is
      # some, yield both of their values to the block and return its value as
      # Some. Else return None.
      #
      # @example
      #   None().zip_with(Some(1)) { |a, b| a + b } # => None()
      #   Some(1).zip_with(None()) { |a, b| a + b } # => None()
      #   Some(2).zip_with(Some(3)) { |a, b| a + b } # => Some(5)
      def zip_with(other, &block)
        return None() unless some? && other.some?

        other = block.call(value, other.value)
        Some(other)
      end

      # filter
      # xor
      # insert
      # get_or_insert
      # get_or_insert_with
      # take
      # take_if
      # replace
    end

    # Represent a value
    class Some < Any
      attr_accessor :value

      def initialize(value)
        @value = value
      end

      def some?
        true
      end

      def none?
        false
      end
    end

    class None < Any
      def some?
        false
      end

      def none?
        true
      end
    end
  end
end

# Global convenience for constructing a Some value.
def Some(value)
  Errgonomic::Option::Some.new(value)
end

# Global convenience for constructing a None value.
def None
  Errgonomic::Option::None.new
end
