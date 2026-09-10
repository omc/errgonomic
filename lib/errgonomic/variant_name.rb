# frozen_string_literal: true

module Errgonomic
  # What a bare `Some`, `None`, `Ok` or `Err` evaluates to. Rust writes a
  # value as `return None`, where here the value is `None()`; the bare name
  # is for patterns. It matches as the class it names, and refuses to become
  # a string, so a missing pair of parentheses raises rather than writing a
  # class name into a column. It is not a class, so an application's own
  # `class None` fails where it is written instead of reopening the gem's.
  #
  # @example
  #   case Some(1)
  #   in Some(value) then value
  #   end # => 1
  #   None === None() # => true
  #   None === Some(1) # => false
  #   None.inspect # => "Errgonomic::Option::None"
  #   "tier-#{None}" # => raise Errgonomic::SerializeError, "bare None names a variant for a pattern, not a value; build one with parentheses"
  #   [Ok].join # => raise Errgonomic::SerializeError, "bare Ok names a variant for a pattern, not a value; build one with parentheses"
  #   Some(1).is_a?(Some) # => raise TypeError, "class or module required"
  #   Some(1).is_a?(Errgonomic::Option::Some) # => true
  class VariantName
    # Name a variant at top level, refusing a constant the application
    # already holds there rather than replacing it.
    def self.define(name, variant)
      if Object.const_defined?(name, false)
        existing = Object.const_get(name)
        return if existing.is_a?(VariantName) && existing.names?(variant)

        raise NameError.new("#{name} is already defined as #{existing.inspect}; errgonomic defines #{name} " \
                            "at top level to name #{variant} in patterns, so rename the application's constant", name)
      end
      Object.const_set(name, new(name, variant))
    end

    def initialize(name, variant)
      @name = name
      @variant = variant
      freeze
    end

    def names?(variant)
      @variant.equal?(variant)
    end

    def ===(other)
      @variant === other # rubocop:disable Style/CaseEquality
    end

    def inspect
      @variant.inspect
    end

    # Refuse to stand in for a value.
    def refuse!(*_args)
      raise Errgonomic::SerializeError,
            "bare #{@name} names a variant for a pattern, not a value; build one with parentheses"
    end
    alias to_s refuse!
    alias to_json refuse!
    alias as_json refuse!
  end
end
