# frozen_string_literal: true

require_relative 'option'

module Errgonomic
  # The presence-checking walk behind OptionalHash#dig and OptionalArray#dig:
  # every step checks key or bounds presence, so an absent path (None) stays
  # distinct from a present nil (Some(nil)), which the core dig methods
  # conflate. A nested wrapper handles the rest of the walk itself, by
  # recursion. Digging into a non-collection raises, pedantically, where
  # core dig would raise TypeError.
  module OptionalDig
    private

    def optional_dig(start, keys)
      current = start
      keys.each_with_index do |key, idx|
        case current
        when OptionalHash, OptionalArray
          return current.dig(key, *keys[(idx + 1)..])
        when ::Hash
          return None() unless current.key?(key)
        when ::Array
          return None() unless key.is_a?(Integer) && (-current.length...current.length).cover?(key)
        else
          raise Errgonomic::TypeMismatchError, "cannot dig into #{current.class}"
        end
        current = current[key]
      end
      Some(current)
    end
  end
end
