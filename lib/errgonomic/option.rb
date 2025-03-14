module Errgonomic
  module Option
    class Any
      def ==(other)
        return true if none? && other.none?
        return true if some? && other.some? && value == other.value

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

        !!block.call(value)
      end

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
          raise ArgumentError, 'block must return an Option'
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
      #   Some("foo").ok_or_else { "such err" } # => Ok("foo")
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
