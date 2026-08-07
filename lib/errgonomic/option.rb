# frozen_string_literal: true

module Errgonomic
  module Option
    # The base class for all options. Some and None are subclasses.
    #
    class Any
      include Comparable

      # Rust spellings we accept but do not advertise: they delegate to the
      # Ruby-idiomatic predicate and nudge the caller there via stderr.
      RUST_SPELLINGS = {
        is_some: :some?,
        is_none: :none?,
        is_some_and: :some_and?,
        is_none_or: :none_or?
      }.freeze

      # An Option deliberately forwards nothing to its inner value, so a miss
      # here is almost always someone treating the container as its contents.
      # Teach the route out instead of leaving a bare NoMethodError. Rust
      # spellings of the predicates delegate, with a nudge on stderr.
      #
      # @example
      #   begin
      #     Some(5) + 1
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      #   Some(5).respond_to?(:+) # => false
      #   Some(1).is_some_and { |x| x > 0 } # => true
      #   None().is_none # => true
      #   Some(5).respond_to?(:is_some) # => true
      def method_missing(name, *args, &block)
        if (canonical = RUST_SPELLINGS[name])
          warn "Errgonomic: `#{name}` is the Rust spelling; prefer `#{canonical}`. Delegating."
          return public_send(canonical, *args, &block)
        end

        raise Errgonomic::UnwrappedAccessError.new(<<~MSG, name)
          undefined method `#{name}' for #{inspect}, an Option, which does not forward methods to its inner value.
          Reach for a combinator instead:
            map, and_then, filter: transform the value if present
            unwrap_or, unwrap_or_else: supply a fallback
            ok_or, ok_or_else: convert to a Result
            some_and?, none_or?: test a predicate against the inner value
          unwrap! and expect! also exist, but are intended for tests rather than application code.
        MSG
      end

      def respond_to_missing?(name, include_private = false)
        RUST_SPELLINGS.key?(name) || super
      end

      # An Option equals another Option of the same class with an equal inner
      # value. Anything else, including nil and the raw inner value, is not
      # equal: quietly false, never an error. Rust rejects Some(5) == 5 at
      # compile time; Ruby cannot, and raising here would break the many
      # places Ruby compares heterogeneous operands (Array#include?,
      # assertion diffs, dirty tracking). Compare Options (opt == Some(5)) or
      # test the inner value (opt.some_and? { |v| v == 5 }) instead.
      #
      # None() == nil is likewise false: None is a value that represents
      # absence, not an absence Ruby can see. (The Rails integration
      # separately makes None#nil? answer true, as an ActiveRecord
      # compromise; equality does not follow it.)
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

      # Hash-based collections (Hash keys, Set, uniq, group_by) use eql? and
      # hash, not ==. Follow the inner value's own eql? semantics, so Options
      # behave as keys exactly like their inner values: Some(1) and Some(1.0)
      # are distinct keys, just as 1 and 1.0 are.
      #
      # @example
      #   Some(5).eql?(Some(5)) # => true
      #   Some(1).eql?(Some(1.0)) # => false
      #   None().eql?(None()) # => true
      #   { Some(5) => 1 }[Some(5)] # => 1
      #   [Some(1), Some(1), None(), None()].uniq # => [Some(1), None()]
      def eql?(other)
        return false if self.class != other.class
        return true if none?

        value.eql?(other.value)
      end

      # @example
      #   Some(5).hash == Some(5).hash # => true
      #   None().hash == None().hash # => true
      #   Some(5).hash == None().hash # => false
      def hash
        return self.class.hash if none?

        [self.class, value].hash
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

      # Options order like Rust's: None sorts before any Some, and Somes
      # order by their inner values. Follows Ruby's <=> convention of
      # returning nil for incomparable operands, whether the other object is
      # not an Option or the inner values do not themselves compare.
      #
      # @example
      #   (Some(5) <=> Some(6)) # => -1
      #   (None() <=> Some(5)) # => -1
      #   (Some(5) <=> None()) # => 1
      #   (None() <=> None()) # => 0
      #   (Some(1) <=> Some("x")) # => nil
      #   (Some(1) <=> 1) # => nil
      #   [Some(2), None(), Some(1)].sort # => [None(), Some(1), Some(2)]
      #   [Some(2), Some(1)].min # => Some(1)
      def <=>(other)
        return nil unless other.is_a?(Errgonomic::Option::Any)
        return none? ? 0 : 1 if other.none?
        return -1 if none?

        value <=> other.value
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

      # Presence follows the discriminant, not the inner value: Some is
      # present, None is blank. So Some(false) and Some(nil) are present,
      # unlike their unwrapped values.
      #
      # @example
      #   Some(1).present? # => true
      #   Some(false).present? # => true
      #   Some("").present? # => true
      #   None().present? # => false
      def present?
        some?
      end

      # @example
      #   None().blank? # => true
      #   Some(1).blank? # => false
      #   Some(nil).blank? # => false
      def blank?
        none?
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
        if !val.is_a?(Errgonomic::Option::Any) && !Errgonomic.give_me_ambiguous_downstream_errors?
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

      # If self is Some, call the given block with the inner value and return
      # its result. Block must return an Option.
      #
      # @example
      #   None().and_then { |x| Some(x + 1) } # => None()
      #   Some(2).and_then { |x| Some(x + 1) } # => Some(3)
      def and_then(&block)
        return self if none?

        val = block.call(value)
        if !Errgonomic.give_me_ambiguous_downstream_errors? && !val.is_a?(Errgonomic::Option::Any)
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

      # Refuse to serialize an unwrapped Option as a String. Options must be
      # correctly handled to access their inner value.
      #
      # @example
      #   None().to_s # => raise Errgonomic::SerializeError, "cannot serialize an unwrapped Option"
      def to_s
        raise Errgonomic::SerializeError, 'cannot serialize an unwrapped Option'
      end

      # Refuse to serialize an unwrapped Option as JSON. Not only should we
      # require that options be correctly handled to access their inner value,
      # but without this we will get undefined structures from default
      # Object#to_json implementations.
      #
      # @example
      #   None().to_json # => raise Errgonomic::SerializeError, "cannot serialize an unwrapped Option"
      def to_json(*_args)
        raise Errgonomic::SerializeError, 'cannot serialize an unwrapped Option'
      end

      # pp uses its own object dump unless told otherwise; keep it consistent
      # with inspect.
      def pretty_print(pp)
        pp.text(inspect)
      end

      # Return self if the predicate is truthy for the inner value, else None.
      # None passes through.
      #
      # @example
      #   Some(1).filter(&:odd?) # => Some(1)
      #   Some(2).filter(&:odd?) # => None()
      #   None().filter(&:odd?) # => None()
      def filter(&block)
        return self if none?

        block.call(value) ? self : None()
      end

      # Remove one level of Option nesting. Pedantically raises when the inner
      # value is not itself an Option, which in Rust would not have compiled.
      #
      # @example
      #   Some(Some(1)).flatten # => Some(1)
      #   Some(None()).flatten # => None()
      #   None().flatten # => None()
      #   Some(Some(Some(1))).flatten # => Some(Some(1))
      #   Some(1).flatten # => raise Errgonomic::TypeMismatchError, "cannot flatten Integer; it is not an Option"
      def flatten
        return self if none?

        unless value.is_a?(Errgonomic::Option::Any)
          raise Errgonomic::TypeMismatchError,
                "cannot flatten #{value.class}; it is not an Option"
        end

        value
      end

      # Return Some when either self or other are Some, otherwise return None
      # when both are None or both are Some.
      #
      # @example
      #   Some(:left).xor(Some(:right)) # => None()
      #   Some(:left).xor(None()) #=> Some(:left)
      #   None().xor(Some(:right)) #=> Some(:right)
      #
      def xor(other)
        return self if some? && other.none?
        return other if other.some? && none?

        None()
      end

      # Rust's mutating combinators (insert, get_or_insert, take, replace)
      # are deliberately omitted: an Option here is a value, not a slot.
    end

    # Represent a value
    class Some < Any
      attr_accessor :value

      def initialize(value)
        super()
        @value = value
      end

      def some?
        true
      end

      def none?
        false
      end

      # Render like Rust's Debug, delegating to the inner value's inspect so
      # nesting stays unambiguous.
      #
      # @example
      #   Some(5).inspect # => "Some(5)"
      #   Some("x").inspect # => "Some(\"x\")"
      #   Some(nil).inspect # => "Some(nil)"
      #   Some(Some(1)).inspect # => "Some(Some(1))"
      def inspect
        "Some(#{value.inspect})"
      end
    end

    # Represent the absence of a value.
    class None < Any
      def some?
        false
      end

      def none?
        true
      end

      # @example
      #   None().inspect # => "None"
      def inspect
        'None'
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
