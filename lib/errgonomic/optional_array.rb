# frozen_string_literal: true

require_relative 'option'
require_relative 'optional_dig'

module Errgonomic
  # A companion to Array whose lookups return Options, composed around a
  # plain Array for the same reasons OptionalHash composes around a Hash.
  # Lookups follow element presence: an element holding nil is Some(nil),
  # and only an out-of-bounds index is None, as with Rust's slice get.
  class OptionalArray
    include OptionalDig

    def initialize(array = [])
      unless array.is_a?(::Array)
        raise Errgonomic::TypeMismatchError,
              "OptionalArray wraps an Array, got #{array.class}"
      end

      @array = array
    end

    # Retrieve the element at an integer index, wrapped in an Option.
    # Negative indexes count from the end, as usual. A non-integer index
    # raises, pedantically: the silent nil of Array#[] with a bad argument is
    # the ambiguity this class exists to remove.
    #
    # @example
    #   a = [:a, nil].into_optional
    #   a[0] # => Some(:a)
    #   a[1] # => Some(nil)
    #   a[2] # => None()
    #   a[-1] # => Some(nil)
    #   a[:nope] # => raise Errgonomic::TypeMismatchError, "index must be an Integer, got Symbol"
    def [](index)
      unless index.is_a?(::Integer)
        raise Errgonomic::TypeMismatchError,
              "index must be an Integer, got #{index.class}"
      end
      return None() unless (-@array.length...@array.length).cover?(index)

      Some(@array[index])
    end

    # Write through to the underlying array.
    #
    # @example
    #   a = [].into_optional
    #   a[0] = :a
    #   a[0] # => Some(:a)
    def []=(index, value)
      @array[index] = value
    end

    # Like Array#dig, but every step checks presence, so an absent path
    # (None) stays distinct from a present nil (Some(nil)).
    #
    # @example
    #   a = [{ name: 'Ada' }].into_optional
    #   a.dig(0, :name) # => Some("Ada")
    #   a.dig(0, :nickname) # => None()
    #   a.dig(1, :name) # => None()
    def dig(index, *rest)
      optional_dig(@array, [index, *rest])
    end

    # The first element as an Option, as with Rust's slice first.
    #
    # @example
    #   [1, 2].into_optional.first # => Some(1)
    #   [nil].into_optional.first # => Some(nil)
    #   [].into_optional.first # => None()
    def first
      return None() if @array.empty?

      Some(@array.first)
    end

    # The last element as an Option, as with Rust's slice last.
    #
    # @example
    #   [1, 2].into_optional.last # => Some(2)
    #   [].into_optional.last # => None()
    def last
      return None() if @array.empty?

      Some(@array.last)
    end

    # @example
    #   [].into_optional.empty? # => true
    #   [1].into_optional.empty? # => false
    def empty?
      @array.empty?
    end

    # @example
    #   [1, 2].into_optional.size # => 2
    def size
      @array.size
    end

    # The escape hatch back to a plain Array: a shallow copy, so array-shaped
    # code cannot mutate the wrapped state behind the Option semantics.
    #
    # @example
    #   [1].into_optional.to_a # => [1]
    def to_a
      @array.dup
    end

    # Equal to another OptionalArray wrapping an equal array; never equal to
    # a plain Array, mirroring how Some(x) is never equal to x.
    #
    # @example
    #   [1].into_optional == [1].into_optional # => true
    #   [1].into_optional == [2].into_optional # => false
    #   [1].into_optional == [1] # => false
    def ==(other)
      other.is_a?(OptionalArray) && inner == other.inner
    end

    # @example
    #   [1].into_optional.eql?([1].into_optional) # => true
    #   { [1].into_optional => :hit }[[1].into_optional] # => :hit
    def eql?(other)
      other.is_a?(OptionalArray) && inner.eql?(other.inner)
    end

    def hash
      [self.class, inner].hash
    end

    # @example
    #   [1].into_optional.inspect # => "OptionalArray([1])"
    def inspect
      "OptionalArray(#{@array.inspect})"
    end

    protected

    def inner
      @array
    end
  end
end
