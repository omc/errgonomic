# frozen_string_literal: true

require_relative 'variant_name'

module Errgonomic
  module Result
    # The base class for Result's Ok and Err class variants. We implement as
    # much logic as possible here, and let Ok and Err handle their
    # initialization and self identification.
    class Any
      include Comparable

      # A Result is a value, not a slot: the inner value is reached through a
      # combinator that handles the other variant, and nothing swaps it out
      # from under another reference.
      #
      # @example
      #   begin
      #     Ok(1).value
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      #   begin
      #     Err(:x).value = :y
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      #   Ok(1).respond_to?(:value) # => false
      #   Ok(1).frozen? # => true
      #   Err(:x).frozen? # => true
      def initialize(value)
        @value = value
        freeze
      end

      # Results order like Rust's: Ok sorts before any Err, and same variants
      # order by their inner values. Two Results whose inner values do not
      # themselves compare follow Ruby's convention and answer nil. A
      # non-Result operand raises instead: Comparable turns a nil here into an
      # ArgumentError that names the Result as the operand at fault, where
      # what went wrong is that a wrapper was ordered against a bare value.
      #
      # @example
      #   (Ok(1) <=> Ok(2)) # => -1
      #   (Ok(1) <=> Err(:a)) # => -1
      #   (Err(:a) <=> Ok(1)) # => 1
      #   (Err(:a) <=> Err(:b)) # => -1
      #   [Err(:a), Ok(2), Ok(1)].sort # => [Ok(1), Ok(2), Err(:a)]
      #
      # @example a bare value is not ordered against a Result
      #   Ok(1) <= 2 # => raise Errgonomic::TypeMismatchError, "cannot compare Ok(1) with Integer; test the inner value (ok_and? { |v| v <= other }) or reach for it (map, unwrap_or)"
      #   Ok(1).ok_and? { |v| v <= 2 } # => true
      #   Ok(1).map { |v| v <= 2 } # => Ok(true)
      def <=>(other)
        unless other.is_a?(Errgonomic::Result::Any)
          raise Errgonomic::TypeMismatchError,
                "cannot compare #{inspect} with #{other.class}; test the inner value " \
                '(ok_and? { |v| v <= other }) or reach for it (map, unwrap_or)'
        end

        return ok? ? -1 : 1 if self.class != other.class

        value <=> other.value
      end

      # Rust spellings we accept but do not advertise: they delegate to the
      # Ruby-idiomatic predicate and nudge the caller there via stderr.
      RUST_SPELLINGS = {
        is_ok: :ok?,
        is_err: :err?,
        is_ok_and: :ok_and?,
        is_err_and: :err_and?
      }.freeze

      # A Result deliberately forwards nothing to its inner value, so a miss
      # here is almost always someone treating the container as its contents.
      # Teach the route out instead of leaving a bare NoMethodError. Rust
      # spellings of the predicates delegate, with a nudge on stderr.
      #
      # @example
      #   begin
      #     Ok(5) + 1
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      #   Ok(5).respond_to?(:+) # => false
      #   Ok(1).is_ok_and(&:odd?) # => true
      #   Err(:a).is_err # => true
      #   Ok(1).respond_to?(:is_ok) # => true
      def method_missing(name, *args, &block)
        if (canonical = RUST_SPELLINGS[name])
          warn "Errgonomic: `#{name}` is the Rust spelling; prefer `#{canonical}`. Delegating."
          return public_send(canonical, *args, &block)
        end

        raise Errgonomic::UnwrappedAccessError.new(<<~MSG, name)
          undefined method `#{name}' for #{inspect}, a Result, which does not forward methods to its inner value.
          Reach for a combinator instead:
            map, map_err, and_then, or_else: transform the value or the error
            unwrap_or, unwrap_or_else: supply a fallback
            ok_and?, err_and?: test a predicate against the inner value
          unwrap!, unwrap_err!, and expect! also exist, but are intended for tests rather than application code.
        MSG
      end

      def respond_to_missing?(name, include_private = false)
        RUST_SPELLINGS.key?(name) || super
      end

      # A Result equals another Result of the same variant with an equal
      # inner value. Comparing it with anything that is not a Result raises
      # Errgonomic::TypeMismatchError, on the terms Option#== states: the
      # raise reaches ==, !=, eql? and ===, hashing stays quiet, and a bare
      # value on the left answers for itself.
      #
      # @param other [Object]
      #
      # @example
      #   Ok(1) == Ok(1) # => true
      #   Ok(1) == Err(1) # => false
      #   Ok(1).object_id == Ok(1).object_id # => false
      #
      # @example a cross-type comparison is an error, never a quiet false
      #   Ok(1) == 1 # => raise Errgonomic::TypeMismatchError, "Errgonomic::Result::Ok == Integer, which strict equality refuses.\nCompare Results (res == Ok(1)), test the inner value (res.ok_and? { |v| v == 1 }), or unwrap_or a fallback first."
      #   Ok(1) != 1 # => raise Errgonomic::TypeMismatchError, "Errgonomic::Result::Ok != Integer, which strict equality refuses.\nCompare Results (res == Ok(1)), test the inner value (res.ok_and? { |v| v == 1 }), or unwrap_or a fallback first."
      #   Ok(1) === 1 # => raise Errgonomic::TypeMismatchError, "Errgonomic::Result::Ok === Integer, which strict equality refuses.\nCompare Results (res == Ok(1)), test the inner value (res.ok_and? { |v| v == 1 }), or unwrap_or a fallback first."
      #   Err(:x) == nil # => raise Errgonomic::TypeMismatchError, "Errgonomic::Result::Err == NilClass, which strict equality refuses.\nCompare Results (res == Ok(nil)), test the inner value (res.ok_and? { |v| v == nil }), or unwrap_or a fallback first."
      #   Ok(1) === Ok(1) # => true
      #   begin
      #     [Ok(1)].include?(1)
      #   rescue Errgonomic::TypeMismatchError => e
      #     e.class
      #   end # => Errgonomic::TypeMismatchError
      #   { Ok(1) => :v }[1] # => nil
      #   nil == Err(:x) # => false
      #
      # @example an Option is another container, not another Result
      #   Ok(1) == Some(1) # => raise Errgonomic::TypeMismatchError, "Errgonomic::Result::Ok == Errgonomic::Option::Some, which strict equality refuses.\nA Result and an Option are different containers, and neither is the other.\nUnwrap the one you meant (res.unwrap_or(nil) == opt.unwrap_or(nil))."
      def ==(other)
        strict_equality!(other, '==')
        return false if self.class != other.class

        value == other.value
      end

      # Object#=== is ==, so a `case value when Ok(1)` and a pinned pattern
      # reach the same check, named for the operator that was written.
      def ===(other)
        strict_equality!(other, '===')
        self == other
      end

      # Hash-based collections (Hash keys, Set, uniq, group_by) use eql? and
      # hash, not ==. Follow the inner value's own eql? semantics, so Results
      # behave as keys exactly like their inner values.
      #
      # @example
      #   Ok(5).eql?(Ok(5)) # => true
      #   Ok(1).eql?(Ok(1.0)) # => false
      #   Ok(1).eql?(Err(1)) # => false
      #   { Ok(5) => 1 }[Ok(5)] # => 1
      #   [Err(:a), Err(:a)].uniq # => [Err(:a)]
      #
      # @example a cross-type eql? raises as == does, and hash is untouched
      #   Ok(5).eql?(5) # => raise Errgonomic::TypeMismatchError, "Errgonomic::Result::Ok eql? Integer, which strict equality refuses.\nCompare Results (res == Ok(5)), test the inner value (res.ok_and? { |v| v == 5 }), or unwrap_or a fallback first."
      #   Ok(5).hash == Ok(5).hash # => true
      def eql?(other)
        strict_equality!(other, 'eql?')
        self.class == other.class && value.eql?(other.value)
      end

      # Ruby derives != from ==, so a strict-equality message would name the
      # operator the caller did not write.
      def !=(other)
        strict_equality!(other, '!=')
        super
      end

      # @example
      #   Ok(5).hash == Ok(5).hash # => true
      #   Ok(5).hash == Err(5).hash # => false
      def hash
        [self.class, value].hash
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
        return false if err?

        !!block.call(value)
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
      #   Err(:c).unwrap! # => raise Errgonomic::UnwrapError.new("value is an Err", :c)
      def unwrap!
        raise Errgonomic::UnwrapError.new('value is an Err', @value) unless ok?

        @value
      end

      # Return the inner value of an Ok, else raise an exception with the given
      # message when Err. A block is called only on the Err branch, so a
      # message that interpolates costs nothing on the path that succeeds.
      #
      # @param msg [String]
      #
      # @example
      #   Ok(1).expect!("should have worked") # => 1
      #   Err(:d).expect!("should have worked") # => raise Errgonomic::ExpectError, "should have worked"
      #   Err(:d).expect! { "no rate for #{7}" } # => raise Errgonomic::ExpectError, "no rate for 7"
      def expect!(msg = nil, &block)
        raise Errgonomic::ExpectError, block ? block.call : msg unless ok?

        @value
      end

      # Return the inner value of an Err, else raise an exception when Ok.
      # The message is the Ok's value as inspect renders it, bounded, so an
      # Ok holding an Option or a Result still has a message to print.
      #
      # @example
      #   Ok(1).unwrap_err! # => raise Errgonomic::UnwrapError, "1"
      #   Ok(Some(1)).unwrap_err! # => raise Errgonomic::UnwrapError, "Some(1)"
      #   Ok("a" * 100).unwrap_err! # => raise Errgonomic::UnwrapError, "\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..."
      #   Err(:e).unwrap_err! # => :e
      def unwrap_err!
        raise Errgonomic::UnwrapError.new(bounded_inspect(value), value) unless err?

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
        if !res.is_a?(Errgonomic::Result::Any) && !Errgonomic.give_me_ambiguous_downstream_errors?
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
      #   Ok(1).or_else { |e| Ok(2) } # => Ok(1)
      #   Err(:o).or_else { |e| Ok(1) } # => Ok(1)
      #   Err(:q).or_else { |e| Err(:r) } # => Err(:r)
      #   Err(:s).or_else { |e| "oops" } # => raise Errgonomic::ArgumentError, "or_else block must return a Result"
      def or_else(&block)
        return self if ok?

        res = block.call(value)
        if !res.is_a?(Errgonomic::Result::Any) && !Errgonomic.give_me_ambiguous_downstream_errors?
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
      #   Err("foo").unwrap_or_else { |s| s.length } # => 3
      def unwrap_or_else(&block)
        return value if ok?

        block.call(value)
      end

      # Calls the function with the inner error value, if Err, but returns the
      # original Result.
      #
      # @example
      #   tapped = false
      #   Ok(1).tap_err { |err| tapped = err } # => Ok(1)
      #   tapped # => false
      #   Err(:nope).tap_err { |err| tapped = err } # => Err(:nope)
      #   tapped # => :nope
      def tap_err(&block)
        block.call(value) if err?
        self
      end

      # Calls the function with the inner ok value, if Ok, while returning the
      # original Result.
      def tap_ok(&block)
        block.call(value) if ok?
        self
      end

      # Map the Ok(a) to an Ok(b), preserving the Err
      #
      # @example
      #   Err(:broken).map { |_val| :nominal } # => Err(:broken)
      #   Ok(:plausible).map { |_val| :success } # => Ok(:success)
      def map(&block)
        return self if err?

        Ok(block.call(value))
      end

      # Map the Err(e) to an Err(f), preserving the Ok
      #
      # @example
      #   Ok(:Alice).map_err { |_e| :Bob } # => Ok(:Alice)
      #   Err(:bob).map_err { |e| e.capitalize } # => Err(:Bob)
      def map_err(&block)
        return self if ok?

        Err(block.call(value))
      end

      # Refuse to render as a String. Rust gives Result a Debug and no
      # Display: a wrapper that reaches a string went unhandled, and a string
      # is where it turns into data, a hostname, a hash key or a page. The
      # refusal names the value and says how to log it or take it.
      #
      # @example
      #   Ok(1).to_s # => raise Errgonomic::SerializeError, "Ok(1) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   Err(:nope).to_s # => raise Errgonomic::SerializeError, "Err(:nope) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   "outcome: #{Ok(1)}" # => raise Errgonomic::SerializeError, "Ok(1) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   [Ok(1), Err(:x)].join(",") # => raise Errgonomic::SerializeError, "Ok(1) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   format("%s", Err(:x)) # => raise Errgonomic::SerializeError, "Err(:x) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   String(Ok(1)) # => raise Errgonomic::SerializeError, "Ok(1) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   Err("a" * 100).to_s # => raise Errgonomic::SerializeError, "Err(\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa... refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   Err(:nope).inspect # => "Err(:nope)"
      def to_s
        raise Errgonomic::SerializeError, to_s_refusal
      end

      # Refuse to serialize an unwrapped Result as JSON. Not only should we
      # require that Results be correctly handled to access their inner value,
      # but without this we will get undefined structures from default
      # Object#to_json implementations.
      #
      # @example
      #   Ok("").to_json # => raise Errgonomic::SerializeError, "cannot serialize an unwrapped Result"
      #   Err("").to_json # => raise Errgonomic::SerializeError, "cannot serialize an unwrapped Result"
      def to_json(*_args)
        raise Errgonomic::SerializeError, 'cannot serialize an unwrapped Result'
      end

      # ActiveSupport's Hash#as_json and Array#as_json recurse through their
      # members with as_json rather than to_json, so a Result nested in a
      # payload reaches Object#as_json and serializes as its instance
      # variables. Refuse there too, and the guard holds wherever a Result
      # travels.
      def as_json(*_args)
        raise Errgonomic::SerializeError, 'cannot serialize an unwrapped Result'
      end

      # pp uses its own object dump unless told otherwise; keep it consistent
      # with inspect.
      def pretty_print(pp)
        pp.text(inspect)
      end

      # The Rust shape: each variant deconstructs to its one payload, so
      # `in Ok(v)` binds the value and `in Err(e)` binds the error.
      #
      # @example
      #   Ok(1).deconstruct # => [1]
      #   Err(:x).deconstruct # => [:x]
      #   Ok(1).respond_to?(:deconstruct_keys) # => false
      #
      # @example every Err carries an error, so `in Err()` matches none of them
      #   case Err(:x)
      #   in Err() then :empty
      #   in Err(e) then e
      #   end # => :x
      #   case Err(:x)
      #   in Err then :any_err
      #   end # => :any_err
      #   case Err(:x)
      #   in Err(_) then :any_err
      #   end # => :any_err
      #
      # @example a two-branch case/in with no else is exhaustive
      #   case Ok(1)
      #   in Ok(value)
      #     "Measurement is #{value}"
      #   in Err(err)
      #     "Measurement is not available"
      #   end # => "Measurement is 1"
      #
      # @example the wrong type falls through to Ruby's own exhaustiveness check
      #   begin
      #     case :done
      #     in Ok(value) then value
      #     in Err(err) then err
      #     end
      #   rescue NoMatchingPatternError => e
      #     [e.class, e.message]
      #   end # => [NoMatchingPatternError, "done"]
      #
      # @example an Option that falls through carries a message that refuses to print
      #   begin
      #     case Some(1)
      #     in Ok(value) then value
      #     in Err(err) then err
      #     end
      #   rescue NoMatchingPatternError => e
      #     [e.class, (e.message rescue $!.class)]
      #   end # => [NoMatchingPatternError, Errgonomic::SerializeError]
      #
      # @example a pattern reaches the kind of value inside the variant
      #   result = Err(StandardError.new("nope"))
      #   case result
      #   in Ok(value)
      #     "Measurement is #{value}"
      #   in Err(String => msg)
      #     "Measurement failed with a message: #{msg}"
      #   in Err(Exception => e)
      #     "Measurement produced an exception -- #{e.class}: #{e}"
      #   end # => "Measurement produced an exception -- StandardError: nope"
      def deconstruct
        return [] if value.equal?(Err::Arbitrary)

        [value]
      end

      protected

      # Sibling instances read each other's value for equality and ordering;
      # nothing else does.
      attr_reader :value

      private

      def to_s_refusal
        "#{bounded_inspect} refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      end

      # Name the value the caller failed to handle, bounded: an inspect of a
      # record or a long payload would bury the message carrying it.
      def bounded_inspect(object = self)
        rendered = object.inspect
        rendered.length > 60 ? "#{rendered[0, 57]}..." : rendered
      end

      def strict_equality!(other, operator)
        return if other.is_a?(Errgonomic::Result::Any)

        raise Errgonomic::TypeMismatchError,
              "#{self.class} #{operator} #{other.class}, which strict equality refuses.\n" \
              "#{strict_equality_remedy(other)}"
      end

      def strict_equality_remedy(other)
        return <<~MSG.chomp if other.is_a?(Errgonomic::Option::Any)
          A Result and an Option are different containers, and neither is the other.
          Unwrap the one you meant (res.unwrap_or(nil) == opt.unwrap_or(nil)).
        MSG

        "Compare Results (res == Ok(#{other.inspect})), test the inner value " \
          "(res.ok_and? { |v| v == #{other.inspect} }), or unwrap_or a fallback first."
      end
    end

    # The Ok variant.
    class Ok < Any
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

      # Render like Rust's Debug, delegating to the inner value's inspect.
      #
      # @example
      #   Ok(1).inspect # => "Ok(1)"
      #   Ok("x").inspect # => "Ok(\"x\")"
      def inspect
        "Ok(#{value.inspect})"
      end
    end

    # The Err variant. It always carries an error, so unwrap_err! and a
    # pattern variable bind what the caller put there.
    #
    # @example an Err without an error raises
    #   Err(:e).unwrap_err! # => :e
    #   Err() # => raise ArgumentError, "wrong number of arguments (given 0, expected 1)"
    #   Err.new # => raise ArgumentError, "wrong number of arguments (given 0, expected 1)"
    #   Errgonomic::Result::Err.new # => raise ArgumentError, "wrong number of arguments (given 0, expected 1)"
    class Err < Any
      class Arbitrary; end

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

      # Render like Rust's Debug, delegating to the inner value's inspect.
      #
      # @example
      #   Err(:nope).inspect # => "Err(:nope)"
      #   Err(Some(1)).inspect # => "Err(Some(1))"
      def inspect
        return 'Err()' if value.equal?(Arbitrary)

        "Err(#{value.inspect})"
      end
    end
  end
end

# Introduce result-ness helpers into the Object class. No doctests here:
# several files reopen Object, and YARD keeps only one docstring for it, so
# examples on the class itself can be silently dropped. Each method carries
# its own examples instead.
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
def Err(value)
  Errgonomic::Result::Err.new(value)
end

# The variants under their short names, so a pattern reads as it does in
# Rust: `in Ok(v)`, `in Err(e)`.
Errgonomic::VariantName.define(:Ok, Errgonomic::Result::Ok)
Errgonomic::VariantName.define(:Err, Errgonomic::Result::Err)
