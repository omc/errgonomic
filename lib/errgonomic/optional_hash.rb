# frozen_string_literal: true

require_relative 'option'
require_relative 'optional_dig'

module Errgonomic
  # A companion to Hash whose lookups return Options, composed around a plain
  # Hash rather than subclassing it. Subclassing cannot keep Option semantics:
  # since Ruby 3, most Hash methods return plain Hash instances, so wrapped
  # behavior silently drops off in pipelines. Composition with a small, closed
  # API keeps the semantics honest; reach the plain Hash back with to_h.
  #
  # Lookups follow key presence, not value truthiness, so a key holding nil is
  # Some(nil). This matches Option presence semantics: the discriminant tells
  # you whether the key was there, and the inner value is yours to judge.
  class OptionalHash
    include OptionalDig

    def initialize(hash = {})
      unless hash.is_a?(::Hash)
        raise Errgonomic::TypeMismatchError,
              "OptionalHash wraps a Hash, got #{hash.class}"
      end

      @hash = hash
    end

    # Retrieve the value for a key, wrapped in an Option. A present key with
    # a nil value is Some(nil); only a missing key is None.
    #
    # @example
    #   h = { color: :blue, shade: nil }.into_optional
    #   h[:color] # => Some(:blue)
    #   h[:shade] # => Some(nil)
    #   h[:smell] # => None()
    def [](key)
      return None() unless @hash.key?(key)

      Some(@hash[key])
    end

    # Write through to the underlying hash.
    #
    # @example
    #   h = {}.into_optional
    #   h[:color] = :blue
    #   h[:color] # => Some(:blue)
    def []=(key, value)
      @hash[key] = value
    end

    # Like Hash#dig, but every step checks presence, so the result
    # distinguishes an absent path (None) from a present nil (Some(nil)),
    # which Hash#dig conflates. Walks nested Hashes, Arrays, and
    # OptionalHashes; digging into anything else raises, pedantically, where
    # Hash#dig would raise TypeError.
    #
    # @example
    #   h = { person: { name: 'Ada', middle_name: nil } }.into_optional
    #   h.dig(:person, :name) # => Some("Ada")
    #   h.dig(:person, :middle_name) # => Some(nil)
    #   h.dig(:person, :nickname) # => None()
    #   h.dig(:company, :name) # => None()
    #
    # @example arrays participate, with bounds checked
    #   h = { people: [{ name: 'Ada' }] }.into_optional
    #   h.dig(:people, 0, :name) # => Some("Ada")
    #   h.dig(:people, 1, :name) # => None()
    #
    # @example a nested wrapper walks the rest of the path itself
    #   h = { person: { name: 'Ada' }.into_optional }.into_optional
    #   h.dig(:person, :name) # => Some("Ada")
    #   h.dig(:person, :nickname) # => None()
    #
    # @example digging into a non-collection is an error, not a None
    #   h = { name: 'Ada' }.into_optional
    #   h.dig(:name, :length) # => raise Errgonomic::TypeMismatchError, "cannot dig into String"
    def dig(key, *rest)
      optional_dig(@hash, [key, *rest])
    end

    # @example
    #   h = { shade: nil }.into_optional
    #   h.key?(:shade) # => true
    #   h.key?(:color) # => false
    def key?(key)
      @hash.key?(key)
    end

    # @example
    #   {}.into_optional.empty? # => true
    #   { a: 1 }.into_optional.empty? # => false
    def empty?
      @hash.empty?
    end

    # @example
    #   { a: 1 }.into_optional.size # => 1
    def size
      @hash.size
    end

    # The escape hatch back to a plain Hash: a shallow copy, so hash-shaped
    # code cannot mutate the wrapped state behind the Option semantics.
    #
    # @example
    #   { a: 1 }.into_optional.to_h # => { a: 1 }
    def to_h
      @hash.dup
    end

    # Equal to another OptionalHash wrapping an equal hash; never equal to a
    # plain Hash, mirroring how Some(x) is never equal to x.
    #
    # @example
    #   { a: 1 }.into_optional == { a: 1 }.into_optional # => true
    #   { a: 1 }.into_optional == { a: 2 }.into_optional # => false
    #   { a: 1 }.into_optional == { a: 1 } # => false
    def ==(other)
      other.is_a?(OptionalHash) && inner == other.inner
    end

    # @example
    #   { a: 1 }.into_optional.eql?({ a: 1 }.into_optional) # => true
    #   h = { a: 1 }.into_optional
    #   { h => :hit }[{ a: 1 }.into_optional] # => :hit
    def eql?(other)
      other.is_a?(OptionalHash) && inner.eql?(other.inner)
    end

    def hash
      [self.class, inner].hash
    end

    # @example
    #   {}.into_optional.inspect # => "OptionalHash({})"
    def inspect
      "OptionalHash(#{@hash.inspect})"
    end

    protected

    def inner
      @hash
    end
  end
end
