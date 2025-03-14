module Errgonomic
  module Result
    # The base class for Result's Ok and Err class variants. We implement as
    # much logic as possible here, and let Ok and Err handle their
    # initialization and self identification.
    class Any
      attr_reader :value

      def initialize(value)
        @value = value
      end

      # Equality comparison for Result objects is based on value not reference.
      #
      # @example
      #   Ok("foo") == Ok("foo") # => true
      #   Ok("foo") == Err("foo") # => false
      #   Ok("foo").object_id != Ok("foo").object_id # => true
      #   Ok(1) == 1 # => true
      def ==(other)
        unless other.is_a?(Any)
          if Errgonomic.lenient_inner_value_comparison?
            return true if ok? && value == other
          else
            raise Errgonomic::NotComparableError, "Cannot compare #{self.class} to #{other.class}"
          end
        end
        # trivial comparison of a Result to another Result
        return false if self.class != other.class
        value == other.value
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
        raise Errgonomic::UnwrapError, 'value is an Err' unless ok?

        @value
      end

      # Return the inner value of an Ok, else raise an exception with the given
      # message when Err.
      #
      # @example
      #   Ok("foo").expect!("foo") # => "foo"
      #   Err("foo").expect!("foo") # => raise Errgonomic::ExpectError, "foo"
      def expect!(msg)
        raise Errgonomic::ExpectError, msg unless ok?

        @value
      end

      # Return the inner value of an Err, else raise an exception when Ok.
      #
      # @example
      #   Ok("foo").unwrap_err! # => raise Errgonomic::UnwrapError, "value is an Ok"
      #   Err("foo").unwrap_err! # => "foo"
      def unwrap_err!
        raise Errgonomic::UnwrapError, 'value is an Ok' unless err?

        @value
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
        raise Errgonomic::ArgumentError, 'other must be a Result' unless other.is_a?(Errgonomic::Result::Any)
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
          raise Errgonomic::ArgumentError, 'and_then block must return a Result'
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
        unless other.is_a?(Errgonomic::Result::Any)
          raise Errgonomic::ArgumentError,
                'other must be a Result; you might want unwrap_or'
        end
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
          raise Errgonomic::ArgumentError, 'or_else block must return a Result'
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

    # The Ok variant.
    class Ok < Any
      attr_accessor :value

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
        super(value)
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

  end
end

# Introduce certain helper methods into the Object class.
#
# @example
#   "foo".result? # => false
#   "foo".assert_result! # => raise Errgonomic::ResultRequiredError
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


# Global convenience method for constructing an Ok result.
def Ok(value)
  Errgonomic::Result::Ok.new(value)
end

# Global convenience method for constructing an Err result.
def Err(value = Errgonomic::Result::Err::Arbitrary)
  Errgonomic::Result::Err.new(value)
end
