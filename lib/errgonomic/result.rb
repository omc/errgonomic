# frozen_string_literal: true

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
      # @param other [Object]
      #
      # @example
      #   Ok(1) == Ok(1) # => true
      #   Ok(1) == Err(1) # => false
      #   Ok(1).object_id == Ok(1).object_id # => false
      #   Ok(1) == 1 # => false
      #   Err() == nil # => false
      def ==(other)
        return false if self.class != other.class

        value == other.value
      end

      # Indicate that this is some kind of result object. Contrast to
      # Object#result? which is false for all other types.
      #
      # @example
      #   Ok("a").result? # => true
      #   Err("a").result? # => true
      #   "a".result? # => false
      def result?
        true
      end

      # Return true if the inner value is an Ok and the result of the block is
      # truthy.
      #
      # @param [Proc] block The block to evaluate if the inner value is an Ok.
      #
      # @example
      #   Ok(1).ok_and?(&:odd?) # => true
      #   Ok(1).ok_and?(&:even?) # => false
      #   Err(:a).ok_and? { |_| true } # => false
      #   Err(:b).ok_and? { |_| false } # => false
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
      #   Ok(1).err_and?(&:odd?) # => false
      #   Ok(1).err_and?(&:even?) # => false
      #   Err(:a).err_and? { |_| true } # => true
      #   Err(:b).err_and? { |_| false } # => false
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
      #   Ok(1).unwrap! # => 1
      #   Err(:c).unwrap! # => raise Errgonomic::UnwrapError, "value is an Err"
      def unwrap!
        raise Errgonomic::UnwrapError, 'value is an Err' unless ok?

        @value
      end

      # Return the inner value of an Ok, else raise an exception with the given
      # message when Err.
      #
      # @param msg [String]
      #
      # @example
      #   Ok(1).expect!("should have worked") # => 1
      #   Err(:d).expect!("should have worked") # => raise Errgonomic::ExpectError, "should have worked"
      def expect!(msg)
        raise Errgonomic::ExpectError, msg unless ok?

        @value
      end

      # Return the inner value of an Err, else raise an exception when Ok.
      #
      # @example
      #   Ok(1).unwrap_err! # => raise Errgonomic::UnwrapError, 1
      #   Err(:e).unwrap_err! # => :e
      def unwrap_err!
        raise Errgonomic::UnwrapError, value unless err?

        @value
      end

      # Given another result, return it if the inner result is Ok, else return
      # the inner Err. Raise an exception if the other value is not a Result.
      #
      # @param other [Errgonomic::Result::Any]
      #
      # @example
      #   Ok(1).and(Ok(2)) # => Ok(2)
      #   Ok(1).and(Err(:f)) # => Err(:f)
      #   Err(:g).and(Ok(1)) # => Err(:g)
      #   Err(:h).and(Err(:i)) # => Err(:h)
      #   Ok(1).and(2) # => raise Errgonomic::ArgumentError, "other must be a Result"
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
      #
      # @param block [Proc]
      #
      # @example
      #   Ok(1).and_then { |x| Ok(x + 1) } # => Ok(2)
      #   Ok(1).and_then { |_| Err(:error) } # => Err(:error)
      #   Err(:error).and_then { |x| Ok(x + 1) } # => Err(:error)
      #   Err(:error).and_then { |x| Err(:error2) } # => Err(:error)
      def and_then(&block)
        return self if err?

        res = block.call(value)
        if !res.is_a?(Errgonomic::Result::Any) && Errgonomic.give_me_ambiguous_downstream_errors?
          raise Errgonomic::ArgumentError, 'and_then block must return a Result'
        end

        res
      end

      # Return other if self is Err, else return the original Option. Raises a
      # pedantic runtime exception if other is not a Result.
      #
      # @param other [Errgonomic::Result::Any]
      #
      # @example
      #   Err(:j).or(Ok(1)) # => Ok(1)
      #   Err(:k).or(Err(:l)) # => Err(:l)
      #   Err(:m).or("oops") # => raise Errgonomic::ArgumentError, "other must be a Result; you might want unwrap_or"
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
      # @param block [Proc]
      #
      # @example
      #   Ok(1).or_else { Ok(2) } # => Ok(1)
      #   Err(:o).or_else { Ok(1) } # => Ok(1)
      #   Err(:q).or_else { Err(:r) } # => Err(:r)
      #   Err(:s).or_else { "oops" } # => raise Errgonomic::ArgumentError, "or_else block must return a Result"
      def or_else(&block)
        return self if ok?

        res = block.call(self)
        if !res.is_a?(Errgonomic::Result::Any) && Errgonomic.give_me_ambiguous_downstream_errors?
          raise Errgonomic::ArgumentError, 'or_else block must return a Result'
        end

        res
      end

      # Return the inner value if self is Ok, else return the provided default.
      #
      # @param other [Object]
      #
      # @example
      #   Ok(1).unwrap_or(2) # => 1
      #   Err(:t).unwrap_or(:u) # => :u
      def unwrap_or(other)
        return value if ok?

        other
      end

      # Return the inner value if self is Ok, else lazy evaluate the block and
      # return its result.
      #
      # @param block [Proc]
      #
      # @example
      #   Ok(1).unwrap_or_else { 2 } # => 1
      #   Err(:v).unwrap_or_else { :w } # => :w
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
      #   Ok(1).ok? # => true
      def ok?
        true
      end

      # Ok is never err
      #
      # @example
      #   Ok(1).err? # => false
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
      #   Err(:y).value # => :y
      #   Err().value # => Arbitrary
      def initialize(value = Arbitrary)
        super(value)
      end

      # Err is always err
      #
      # @example
      #   Err(:z).err? # => true
      def err?
        true
      end

      # Err is never ok
      #
      # @example
      #   Err(:A).ok? # => false
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
