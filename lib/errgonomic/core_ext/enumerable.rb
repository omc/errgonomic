# frozen_string_literal: true

require_relative '../option'
require_relative '../result'

# The all-or-nothing collection, which Rust spells as a collect into
# Option<Vec<T>> or Result<Vec<T>, E>. On Enumerable rather than Array so it
# composes with map, and so anything that yields wrappers can be sequenced.
module Enumerable
  # Collect an Enumerable of Options into an Option of an Array, stopping at
  # the first None. A member that is not an Option raises unconditionally:
  # with_ambiguous_downstream_errors relaxes what a block returned, not what
  # a caller passed in.
  #
  # @return [Errgonomic::Option::Any]
  #
  # @example
  #   [Some(1), Some(2)].sequence_options # => Some([1, 2])
  #
  # @example
  #   [Some(1), None(), Some(3)].sequence_options # => None()
  #
  # @example
  #   [].sequence_options # => Some([])
  #
  # @example a lazy enumerable is read only as far as the first None
  #   seen = []
  #   lazy = [Some(1), None(), Some(3)].lazy.map { |o| seen << o; o }
  #   lazy.sequence_options # => None()
  #   seen.size # => 2
  #
  # @example
  #   [Some(1), 2].sequence_options # => raise Errgonomic::TypeMismatchError, "cannot sequence_options Integer; it is not an Option"
  #
  # @example a Hash yields pairs, which are Arrays
  #   { a: Some(1) }.sequence_options # => raise Errgonomic::TypeMismatchError, "cannot sequence_options Array; it is not an Option"
  #
  # @example sequence a Hash by its values
  #   { a: Some(1), b: Some(2) }.values.sequence_options # => Some([1, 2])
  def sequence_options
    values = []
    each do |member|
      unless member.is_a?(Errgonomic::Option::Any)
        raise Errgonomic::TypeMismatchError,
              "cannot sequence_options #{member.class}; it is not an Option"
      end
      return None() if member.none?

      values << member.value
    end
    Some(values)
  end

  # Collect an Enumerable of Results into a Result of an Array, stopping at
  # the first Err, which is returned as it stands so it keeps its error.
  # A member that is not a Result raises on the same terms as
  # sequence_options.
  #
  # @return [Errgonomic::Result::Any]
  #
  # @example
  #   [Ok(1), Ok(2)].sequence_results # => Ok([1, 2])
  #
  # @example
  #   [Ok(1), Err(:nope), Ok(3)].sequence_results # => Err(:nope)
  #
  # @example
  #   [].sequence_results # => Ok([])
  #
  # @example a lazy enumerable is read only as far as the first Err
  #   seen = []
  #   lazy = [Ok(1), Err(:nope), Ok(3)].lazy.map { |r| seen << r; r }
  #   lazy.sequence_results # => Err(:nope)
  #   seen.size # => 2
  #
  # @example
  #   [Ok(1), Some(2)].sequence_results # => raise Errgonomic::TypeMismatchError, "cannot sequence_results Errgonomic::Option::Some; it is not a Result"
  #
  # @example sequence a Hash by its values
  #   { a: Ok(1), b: Ok(2) }.values.sequence_results # => Ok([1, 2])
  def sequence_results
    values = []
    each do |member|
      unless member.is_a?(Errgonomic::Result::Any)
        raise Errgonomic::TypeMismatchError,
              "cannot sequence_results #{member.class}; it is not a Result"
      end
      return member if member.err?

      values << member.value
    end
    Ok(values)
  end
end
