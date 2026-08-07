# frozen_string_literal: true

require_relative '../option'
require_relative '../optional_array'

# Two additive lookups; no existing Array behavior changes, for the same
# reasons given in core_ext/hash.rb.
class Array
  # Retrieve the element at an integer index, wrapped in an Option,
  # following element presence as Rust's slice get does: an element holding
  # nil is Some(nil); only an out-of-bounds index is None.
  #
  # @example
  #   a = [:a, nil]
  #   a.fetch_option(0) # => Some(:a)
  #   a.fetch_option(1) # => Some(nil)
  #   a.fetch_option(2) # => None()
  def fetch_option(index)
    unless index.is_a?(::Integer)
      raise Errgonomic::TypeMismatchError,
            "index must be an Integer, got #{index.class}"
    end
    return None() unless (-length...length).cover?(index)

    Some(self[index])
  end

  # Wrap this array in an Errgonomic::OptionalArray view. The wrapper reads
  # and writes this same array; use its to_a for a detached copy.
  #
  # @example
  #   a = [:a].into_optional
  #   a[0] # => Some(:a)
  #   a[1] # => None()
  def into_optional
    Errgonomic::OptionalArray.new(self)
  end
end
