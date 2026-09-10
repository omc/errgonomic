# frozen_string_literal: true

require 'set'
require 'stringio'
require_relative 'variant_name'

module Errgonomic
  module Option
    # The base class for all options. Some and None are subclasses.
    #
    # An Option is an object, so it is always truthy. A None does not stand
    # in for nil in a conditional, and `||` hands back the wrapper rather
    # than the fallback. Reach for a combinator to get at the inner value.
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

      # Names already nudged about. A soft deprecation is a message to a
      # developer, and one per process says it; one per call turns a hot
      # path into a stderr flood.
      NUDGED = Set.new

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
      # value. Comparing it with anything that is not an Option raises
      # Errgonomic::TypeMismatchError, naming both sides and the spelling to
      # reach for. Some(5) == 5 is the comparison Rust rejects at compile
      # time, and a quiet false there is a silent wrong branch, the same
      # failure as a wrapper written into a string. The raise reaches ==, !=,
      # eql? and ===, and through them every collection operation that
      # compares pairwise. Ruby's hashing compares hash values first and asks
      # eql? only of a candidate whose hash matches, so a Hash lookup, a Set
      # and uniq stay quiet with a wrong-typed key: strict equality never
      # answers wrong, it only sometimes fails to catch. nil == Some(1) is
      # answered by NilClass and cannot be intercepted.
      #
      # None() == nil raises too: None is a value that represents absence,
      # not an absence Ruby can see, and the message points at none?. (The
      # Rails integration separately makes None#nil? answer true, as an
      # ActiveRecord compromise; equality does not follow it.)
      #
      # @example
      #   Some(1) == Some(1) # => true
      #   Some(1) == Some(2) # => false
      #   Some(1) == None() # => false
      #   None() == None() # => true
      #
      # @example a cross-type comparison is an error, never a quiet false
      #   Some(5) == 5 # => raise Errgonomic::TypeMismatchError, "Errgonomic::Option::Some == Integer, which strict equality refuses.\nCompare Options (opt == Some(5)), test the inner value (opt.some_and? { |v| v == 5 }), or unwrap_or a fallback first."
      #   Some(5) != 5 # => raise Errgonomic::TypeMismatchError, "Errgonomic::Option::Some != Integer, which strict equality refuses.\nCompare Options (opt == Some(5)), test the inner value (opt.some_and? { |v| v == 5 }), or unwrap_or a fallback first."
      #   Some(5) === 5 # => raise Errgonomic::TypeMismatchError, "Errgonomic::Option::Some === Integer, which strict equality refuses.\nCompare Options (opt == Some(5)), test the inner value (opt.some_and? { |v| v == 5 }), or unwrap_or a fallback first."
      #   Some(5) === Some(5) # => true
      #   1 == Some(1) # => raise Errgonomic::TypeMismatchError, "Errgonomic::Option::Some == Integer, which strict equality refuses.\nCompare Options (opt == Some(1)), test the inner value (opt.some_and? { |v| v == 1 }), or unwrap_or a fallback first."
      #
      # @example a Result is another container, not another Option
      #   Some(1) == Ok(1) # => raise Errgonomic::TypeMismatchError, "Errgonomic::Option::Some == Errgonomic::Result::Ok, which strict equality refuses.\nAn Option and a Result are different containers, and neither is the other. Unwrap the one you meant (opt.unwrap_or(nil) == res.unwrap_or(nil))."
      #
      # @example nil is another type, and absence here is the discriminant
      #   None() == nil # => raise Errgonomic::TypeMismatchError, "Errgonomic::Option::None == NilClass, which strict equality refuses.\nAbsence here is the discriminant: ask none?, or nil? under the Rails integration."
      #
      # @example the raise reaches every operation that compares pairwise
      #   begin
      #     [Some(1)].include?(1)
      #   rescue Errgonomic::TypeMismatchError => e
      #     e.class
      #   end # => Errgonomic::TypeMismatchError
      #   begin
      #     [Some(1)] == [1]
      #   rescue Errgonomic::TypeMismatchError => e
      #     e.class
      #   end # => Errgonomic::TypeMismatchError
      #   begin
      #     [Some(1), 1] - [1]
      #   rescue Errgonomic::TypeMismatchError => e
      #     e.class
      #   end # => Errgonomic::TypeMismatchError
      #   begin
      #     { a: Some(1) } == { a: 1 }
      #   rescue Errgonomic::TypeMismatchError => e
      #     e.class
      #   end # => Errgonomic::TypeMismatchError
      #   begin
      #     case 5
      #     when Some(5) then :hit
      #     end
      #   rescue Errgonomic::TypeMismatchError => e
      #     e.class
      #   end # => Errgonomic::TypeMismatchError
      #
      # @example hashing compares hash values first, so these stay quiet
      #   { Some(1) => :v }[1] # => nil
      #   Set[Some(1)].include?(1) # => false
      #   [Some(1), 1].uniq # => [Some(1), 1]
      #   [Some(1)] | [1] # => [Some(1), 1]
      #
      # @example nil and String answer for themselves, and never ask the Option
      #   nil == Some(1) # => false
      #   "a" == Some("a") # => false
      def ==(other)
        strict_equality!(other, '==')
        return false if self.class != other.class
        return true if none?

        value == other.value
      end

      # Object#=== is ==, so a `case value when Some(5)` and a pinned pattern
      # reach the same check, named for the operator that was written.
      def ===(other)
        strict_equality!(other, '===')
        self == other
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
      #
      # @example a cross-type eql? raises as == does, and hash is untouched
      #   Some(5).eql?(5) # => raise Errgonomic::TypeMismatchError, "Errgonomic::Option::Some eql? Integer, which strict equality refuses.\nCompare Options (opt == Some(5)), test the inner value (opt.some_and? { |v| v == 5 }), or unwrap_or a fallback first."
      #   Some(5).hash == Some(5).hash # => true
      def eql?(other)
        strict_equality!(other, 'eql?')
        return false if self.class != other.class
        return true if none?

        value.eql?(other.value)
      end

      # Ruby derives != from ==, so a strict-equality message would name the
      # operator the caller did not write.
      def !=(other)
        strict_equality!(other, '!=')
        super
      end

      # @example
      #   Some(5).hash == Some(5).hash # => true
      #   None().hash == None().hash # => true
      #   Some(5).hash == None().hash # => false
      def hash
        return self.class.hash if none?

        [self.class, value].hash
      end

      # The Rust shape: a Some deconstructs to its one payload and a None to
      # nothing, so `in Some(v)` binds the value and `in None` matches. There
      # is no deconstruct_keys, because a one-payload sum type has no named
      # field; a Some wrapping a Hash nests as `in Some({id:})` through the
      # Hash's own protocol.
      #
      # @example
      #   Some(1).deconstruct # => [1]
      #   None().deconstruct # => []
      #   Some(1).respond_to?(:deconstruct_keys) # => false
      #
      # @example a two-branch case/in with no else is exhaustive
      #   measurement = Some(1)
      #   case measurement
      #   in Some(value)
      #     "Measurement is #{value}"
      #   in None
      #     "Measurement is not available"
      #   end # => "Measurement is 1"
      #   case None()
      #   in Some(value)
      #     "Measurement is #{value}"
      #   in None
      #     "Measurement is not available"
      #   end # => "Measurement is not available"
      #
      # @example the wrong type falls through to Ruby's own exhaustiveness check
      #   begin
      #     case 1
      #     in Some(value) then value
      #     in None then nil
      #     end
      #   rescue NoMatchingPatternError => e
      #     [e.class, e.message]
      #   end # => [NoMatchingPatternError, "1"]
      #
      # @example a Result that falls through carries a message that refuses to print
      #   begin
      #     case Ok(1)
      #     in Some(value) then value
      #     in None then nil
      #     end
      #   rescue NoMatchingPatternError => e
      #     [e.class, (e.message rescue $!.class)]
      #   end # => [NoMatchingPatternError, Errgonomic::SerializeError]
      #
      # @example patterns nest through the inner value's own protocol
      #   case Ok(Some(1))
      #   in Ok(Some(value)) then value
      #   end # => 1
      #   case Some({ id: 7, name: 'x' })
      #   in Some({ id: }) then id
      #   end # => 7
      #   case Some(1)
      #   in Errgonomic::Option::Some(value) then "bound #{value}"
      #   else "not matched"
      #   end # => "bound 1"
      def deconstruct
        to_a
      end

      # Options order like Rust's: None sorts before any Some, and Somes
      # order by their inner values. Two Options whose inner values do not
      # themselves compare follow Ruby's convention and answer nil. A
      # non-Option operand raises instead: Comparable turns a nil here into
      # an ArgumentError that names the Option as the operand at fault, where
      # what went wrong is that a wrapper was ordered against a bare value.
      #
      # @example
      #   (Some(5) <=> Some(6)) # => -1
      #   (None() <=> Some(5)) # => -1
      #   (Some(5) <=> None()) # => 1
      #   (None() <=> None()) # => 0
      #   (Some(1) <=> Some("x")) # => nil
      #   [Some(2), None(), Some(1)].sort # => [None(), Some(1), Some(2)]
      #   [Some(2), Some(1)].min # => Some(1)
      #
      # @example a bare value is not ordered against an Option
      #   Some(5) <= 6 # => raise Errgonomic::TypeMismatchError, "cannot compare Some(5) with Integer; test the inner value (some_and? { |v| v <= other }) or reach for it (map, unwrap_or)"
      #   Some(5).some_and? { |v| v <= 6 } # => true
      #   Some(5).map { |v| v <= 6 } # => Some(true)
      def <=>(other)
        unless other.is_a?(Errgonomic::Option::Any)
          raise Errgonomic::TypeMismatchError,
                "cannot compare #{inspect} with #{other.class}; test the inner value " \
                '(some_and? { |v| v <= other }) or reach for it (map, unwrap_or)'
        end

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

      # The presence helpers on Object keep their receiver; on an Option that
      # would hand back the wrapper where the caller asked for a value. Here
      # the present side unwraps instead, so a name that reads like an
      # accessor behaves like one. The +_or+ spellings are soft-deprecated on
      # Options in favor of the combinators and nudge via stderr; `presence`
      # is the Rails idiom for unwrap_or(nil) and stays. The blank side, which
      # has no working call sites to preserve, teaches rather than guesses at
      # semantics.

      # Returns the inner value of a Some, and raises on a None. Presence
      # follows the discriminant, so Some(nil) yields nil. A block is called
      # only on the None branch, as it is for expect!.
      #
      # @param message [String] The error message to raise on a None.
      # @return [Object] The inner value of a Some.
      #
      # @example
      #   Some("secret").present_or_raise!("no secret") # => "secret"
      #   Some(nil).present_or_raise!("no secret") # => nil
      #   None().present_or_raise!("no secret") # => raise Errgonomic::NotPresentError, "no secret"
      #   None().present_or_raise! { "no secret for #{7}" } # => raise Errgonomic::NotPresentError, "no secret for 7"
      def present_or_raise!(message = nil, &block)
        presence_nudge('present_or_raise!', 'expect!')
        raise Errgonomic::NotPresentError, block ? block.call : message if none?

        value
      end

      alias present_or_raise present_or_raise!

      # Returns the inner value of a Some, and the given default on a None.
      # No pedantic type check on the default: this family is deprecated on
      # Options, and unwrap_or, which the nudge points to, has none either.
      #
      # @param default [Object] The value to return on a None.
      # @return [Object] The inner value of a Some, otherwise the default.
      #
      # @example
      #   Some("secret").present_or("fallback") # => "secret"
      #   None().present_or("fallback") # => "fallback"
      #
      # @example the nudge fires once per process, so a hot path stays quiet
      #   Some(1).present_or(2)
      #   nudges = StringIO.new
      #   original = $stderr
      #   begin
      #     $stderr = nudges
      #     Some(1).present_or(2)
      #   ensure
      #     $stderr = original
      #   end
      #   nudges.string # => ""
      def present_or(default)
        presence_nudge('present_or', 'unwrap_or')
        return default if none?

        value
      end

      # Returns the inner value of a Some, and the result of the block on a
      # None.
      #
      # @param block [Proc] The block to call on a None.
      # @return [Object] The inner value of a Some, otherwise the block's value.
      #
      # @example
      #   Some("secret").present_or_else { "fallback" } # => "secret"
      #   None().present_or_else { "fallback" } # => "fallback"
      def present_or_else(&block)
        presence_nudge('present_or_else', 'unwrap_or_else')
        return block.call if none?

        value
      end

      # Returns the inner value of a Some, and nil on a None, so the Rails
      # +presence || default+ idiom reaches the value rather than the wrapper.
      # Presence follows the discriminant, so a blank inner value is still a
      # value: Some("").presence is "", where Object#presence answers nil.
      #
      # @return [Object, nil] The inner value of a Some, otherwise nil.
      #
      # @example
      #   Some("secret").presence # => "secret"
      #   Some("").presence # => ""
      #   None().presence # => nil
      #   None().presence || "fallback" # => "fallback"
      #
      # @example the Rails spelling of unwrap_or(nil), and no nudge with it
      #   nudges = StringIO.new
      #   original = $stderr
      #   begin
      #     $stderr = nudges
      #     captured = Some("").presence
      #     None().presence
      #   ensure
      #     $stderr = original
      #   end
      #   captured # => ""
      #   nudges.string # => ""
      def presence
        return nil if none?

        value
      end

      # @example the blank side of the presence family teaches the combinators
      #   begin
      #     None().blank_or("x")
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      def blank_or(_default)
        raise_blank_side_teaching(:blank_or)
      end

      # @example
      #   begin
      #     Some(1).blank_or_else { :x }
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      def blank_or_else(&_block)
        raise_blank_side_teaching(:blank_or_else)
      end

      # @example
      #   begin
      #     None().blank_or_raise!("msg")
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      def blank_or_raise!(_message)
        raise_blank_side_teaching(:blank_or_raise!)
      end

      alias blank_or_raise blank_or_raise!

      # return an Array with the contained value, if any
      # @example
      #   Some(1).to_a # => [1]
      #   None().to_a # => []
      def to_a
        return [] if none?

        [value]
      end

      # Yields the inner value once for a Some and not at all for a None, so
      # an Option reads as the zero-or-one collection it is, and answers an
      # Enumerator without a block. Option does not include Enumerable: its
      # own filter and first answer Options, where Enumerable's answer plain
      # values, and one name cannot mean both.
      #
      # @example
      #   seen = []
      #   Some(1).each { |x| seen << x } # => Some(1)
      #   seen # => [1]
      #   None().each { |x| seen << x } # => None()
      #   seen # => [1]
      #   Some(1).each.to_a # => [1]
      #   None().each.to_a # => []
      #   Some(2).each.map { |x| x * 3 } # => [6]
      #   Some(1).each.size # => 1
      #   None().each.size # => 0
      def each(&block)
        return to_enum(:each) { some? ? 1 : 0 } unless block

        block.call(value) if some?
        self
      end

      # returns the inner value if present, else raises an error
      # @example
      #   Some(1).unwrap! # => 1
      #   None().unwrap! # => raise Errgonomic::UnwrapError, "cannot unwrap None"
      def unwrap!
        raise Errgonomic::UnwrapError, 'cannot unwrap None' if none?

        value
      end

      # Returns the inner value of a Some, else raises with the given message.
      # A block is called only on the None branch, so a message that
      # interpolates costs nothing on the path that succeeds.
      #
      # @example
      #   Some(1).expect!("msg") # => 1
      #   None().expect!("here's why this failed") # => raise Errgonomic::ExpectError, "here's why this failed"
      #   Some(1).expect! { "built only where it is raised" } # => 1
      #   None().expect! { "no tier for #{7}" } # => raise Errgonomic::ExpectError, "no tier for 7"
      def expect!(msg = nil, &block)
        raise Errgonomic::ExpectError, block ? block.call : msg if none?

        value
      end

      # returns the inner value if present, else returns the default value.
      # This is the spelling `opt || default` cannot give you: an Option is
      # truthy, so `||` never reaches the fallback.
      # @example
      #   Some(1).unwrap_or(2) # => 1
      #   None().unwrap_or(2) # => 2
      #   None() || 2 # => None()
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
      # contained value (if Some) or returns None. Whatever the block returns
      # is wrapped, as in Rust: a block that returns an Option gives
      # Some(Some(x)). and_then is the spelling for a block that returns an
      # Option.
      #
      # @example
      #   Some(1).map { |x| x + 1 } # => Some(2)
      #   None().map { |x| x + 1 } # => None()
      #   Some(1).map { |x| Some(x + 1) } # => Some(Some(2))
      #   Some(1).and_then { |x| Some(x + 1) } # => Some(2)
      def map(&block)
        return self if none?

        Some(block.call(value))
      end

      # Returns the provided default (if none), or the block applied to the
      # contained value (if some). Both come back bare, as Rust's map_or
      # gives: this is the exit from the Option, where map stays inside it.
      # Use +map_or_else+ when the default is expensive to build.
      #
      # @example
      #   None().map_or(1) { 100 } # => 1
      #   Some(1).map_or(100) { |x| x + 1 } # => 2
      #   Some("foo").map_or(0) { |str| str.length } # => 3
      #   Some(2).map_or(0) { |x| x * 2 } # => 4
      def map_or(default, &block)
        return default if none?

        block.call(value)
      end

      # Computes a default from the given Proc if None, or applies the block to
      # the contained value (if Some). Both come back bare, as map_or's do.
      #
      # @example
      #   None().map_or_else(-> { :foo }) { :bar } # => :foo
      #   Some("str").map_or_else(-> { 100 }) { |str| str.length } # => 3
      #   None().map_or_else(-> { nil }) { |str| str.length } # => nil
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

      # Returns the option if it contains a value, otherwise returns the provided Option. Returns an Option.
      #
      # @example
      #   None().or(Some(1)) # => Some(1)
      #   Some(2).or(Some(3)) # => Some(2)
      #   None().or(2) # => raise Errgonomic::ArgumentError, "other must be an Option, was Integer"
      #   Some(1).or(2) # => raise Errgonomic::ArgumentError, "other must be an Option, was Integer"
      def or(other)
        option_operand!(other)
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

      # If self is Some, return the provided other Option. The operand is
      # checked on both variants, so a None-heavy path still learns that it
      # was handed a bare value.
      #
      # @example
      #   None().and(Some(1)) # => None()
      #   Some(2).and(Some(3)) # => Some(3)
      #   Some(2).and(3) # => raise Errgonomic::ArgumentError, "other must be an Option, was Integer"
      #   None().and(3) # => raise Errgonomic::ArgumentError, "other must be an Option, was Integer"
      def and(other)
        option_operand!(other)
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
      #   Some(1).zip(2) # => raise Errgonomic::ArgumentError, "other must be an Option, was Integer"
      #   None().zip(2) # => raise Errgonomic::ArgumentError, "other must be an Option, was Integer"
      def zip(other)
        option_operand!(other)
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
      #   Some(1).zip_with(2) { |a, b| a + b } # => raise Errgonomic::ArgumentError, "other must be an Option, was Integer"
      #   None().zip_with(2) { |a, b| a + b } # => raise Errgonomic::ArgumentError, "other must be an Option, was Integer"
      def zip_with(other, &block)
        option_operand!(other)
        return None() unless some? && other.some?

        other = block.call(value, other.value)
        Some(other)
      end

      # Refuse to render as a String. Rust gives Option a Debug and no
      # Display: a wrapper that reaches a string went unhandled, and a string
      # is where it turns into data, a hostname, a hash key or a page. The
      # refusal names the value and says how to log it or take it.
      #
      # @example
      #   Some(1).to_s # => raise Errgonomic::SerializeError, "Some(1) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   None().to_s # => raise Errgonomic::SerializeError, "None refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   "value: #{Some(1)}" # => raise Errgonomic::SerializeError, "Some(1) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   [Some("org"), Some("metrics")].join("/") # => raise Errgonomic::SerializeError, "Some(\"org\") refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   format("%s", None()) # => raise Errgonomic::SerializeError, "None refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   String(Some(1)) # => raise Errgonomic::SerializeError, "Some(1) refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   Some("a" * 100).to_s # => raise Errgonomic::SerializeError, "Some(\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa... refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      #   Some(1).inspect # => "Some(1)"
      def to_s
        raise Errgonomic::SerializeError, to_s_refusal
      end

      # Refuse to serialize an unwrapped Option as JSON. Not only should we
      # require that options be correctly handled to access their inner value,
      # but without this we will get undefined structures from default
      # Object#to_json implementations.
      #
      # @example
      #   None().to_json # => raise Errgonomic::SerializeError, 'cannot serialize an unwrapped None'
      #   begin
      #     Some('a' * 100).to_json
      #   rescue Errgonomic::SerializeError => e
      #     e.message.end_with?('...')
      #   end # => true
      def to_json(*_args)
        raise Errgonomic::SerializeError, serialize_refusal
      end

      # ActiveSupport's Hash#as_json and Array#as_json recurse through their
      # members with as_json rather than to_json, so an Option nested in a
      # payload reaches Object#as_json and serializes as its instance
      # variables. Refuse there too, and the guard holds wherever an Option
      # travels.
      def as_json(*_args)
        raise Errgonomic::SerializeError, serialize_refusal
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
      #   Some(:left).xor(:right) # => raise Errgonomic::ArgumentError, "other must be an Option, was Symbol"
      #   None().xor(:right) # => raise Errgonomic::ArgumentError, "other must be an Option, was Symbol"
      def xor(other)
        option_operand!(other)
        return self if some? && other.none?
        return other if other.some? && none?

        None()
      end

      private

      # Checked before the discriminant is consulted, so a None-heavy path
      # learns about a bare operand as soon as a Some-heavy one would.
      def option_operand!(other)
        return if other.is_a?(Errgonomic::Option::Any)

        raise Errgonomic::ArgumentError, "other must be an Option, was #{other.class.name}"
      end

      def to_s_refusal
        "#{bounded_inspect} refuses to_s; use inspect for a log line, or unwrap_or / expect! for the value"
      end

      def serialize_refusal
        "cannot serialize an unwrapped #{bounded_inspect}"
      end

      # Name the value the caller failed to handle, bounded: an inspect of a
      # record or a long payload would bury the message carrying it.
      def bounded_inspect
        rendered = inspect
        rendered.length > 60 ? "#{rendered[0, 57]}..." : rendered
      end

      def presence_nudge(from, to)
        return unless NUDGED.add?(from)

        warn "Errgonomic: `#{from}` on an Option is soft-deprecated; prefer `#{to}`."
      end

      def strict_equality!(other, operator)
        return if other.is_a?(Errgonomic::Option::Any)

        raise Errgonomic::TypeMismatchError,
              "#{self.class} #{operator} #{other.class}, which strict equality refuses.\n" \
              "#{strict_equality_remedy(other)}"
      end

      def strict_equality_remedy(other)
        case other
        when Errgonomic::Result::Any
          'An Option and a Result are different containers, and neither is the other. ' \
            'Unwrap the one you meant (opt.unwrap_or(nil) == res.unwrap_or(nil)).'
        when nil
          'Absence here is the discriminant: ask none?, or nil? under the Rails integration.'
        else
          "Compare Options (opt == Some(#{other.inspect})), test the inner value " \
            "(opt.some_and? { |v| v == #{other.inspect} }), or unwrap_or a fallback first."
        end
      end

      def raise_blank_side_teaching(name)
        raise Errgonomic::UnwrappedAccessError.new(<<~MSG, name)
          `#{name}` is not supported on an Option, whose blankness is its discriminant.
          Test it with none?, or supply a fallback with unwrap_or / unwrap_or_else.
        MSG
      end
    end

    # Represent a value
    class Some < Any
      # A Some is a value, not a slot: nothing outside reads the inner value
      # without handling the None branch, and nothing swaps it out from under
      # another reference or a Hash key.
      #
      # @example the inner value is reached through a combinator, never a reader
      #   begin
      #     Some(1).value
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      #   Some(1).respond_to?(:value) # => false
      #
      # @example a Some cannot be mutated through an alias
      #   a = Some(1)
      #   b = a
      #   begin
      #     b.value = 99
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      #   a # => Some(1)
      #   Some(1).frozen? # => true
      #   begin
      #     Some(1).instance_variable_set(:@value, 2)
      #   rescue FrozenError => e
      #     e.class
      #   end # => FrozenError
      #
      # @example a Some keeps its place as a Hash key
      #   k = Some(1)
      #   h = { k => :v }
      #   begin
      #     k.value = 2
      #   rescue NoMethodError
      #     nil
      #   end
      #   h[k] # => :v
      def initialize(value)
        super()
        @value = value
        freeze
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

      protected

      # Sibling instances read each other's value for equality, ordering and
      # zip; nothing else does.
      attr_reader :value
    end

    # Represent the absence of a value.
    class None < Any
      # @example a None has no value to read, and says so the same way a Some does
      #   begin
      #     None().value
      #   rescue NoMethodError => e
      #     e.class
      #   end # => Errgonomic::UnwrappedAccessError
      #   None().frozen? # => true
      def initialize
        super
        freeze
      end

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

# The variants under their short names, so a pattern reads as it does in
# Rust: `in Some(v)`, `in None`.
Errgonomic::VariantName.define(:Some, Errgonomic::Option::Some)
Errgonomic::VariantName.define(:None, Errgonomic::Option::None)
