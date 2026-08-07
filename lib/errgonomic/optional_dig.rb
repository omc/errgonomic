# frozen_string_literal: true

require_relative 'option'

module Errgonomic
  # The presence-checking walk behind OptionalHash#dig and OptionalArray#dig:
  # every step checks key or bounds presence, so an absent path (None) stays
  # distinct from a present nil (Some(nil)), which the core dig methods
  # conflate. Digging into a non-collection raises, pedantically, where core
  # dig would raise TypeError.
  module OptionalDig
    private

    def optional_dig(start, keys)
      current = start
      keys.each do |key|
        current = current.to_h if current.is_a?(OptionalHash)
        current = current.to_a if current.is_a?(OptionalArray)
        case current
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
