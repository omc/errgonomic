# frozen_string_literal: true

require_relative "errgonomic/version"

# The semantics here borrow heavily from ActiveSupport. Let's prefer that if
# loaded, otherwise just copypasta the bits we like. Or convince me to make that
# gem a dependency.
if !Object.methods.include?(:blank?)
  require_relative "errgonomic/core_ext/blank"
end

module Errgonomic
  class Error < StandardError; end

  class NotPresentError < Error; end

  class TypeMismatchError < Error; end
end

class Object
  # Returns the receiver if it is present, otherwise raises a NotPresentError.
  # This method is useful to enforce strong expectations, where it is preferable
  # to fail early rather than risk causing an ambiguous error somewhere else.
  #
  # @param message [String] The error message to raise if the receiver is not present.
  # @return [Object] The receiver if it is present, otherwise raises a NotPresentError.
  def present_or_raise(message)
    raise Errgonomic::NotPresentError, message if blank?
    self
  end

  # Returns the receiver if it is present, otherwise returns the given value. If
  # constructing the default value is expensive, consider using
  # +present_or_else+.
  #
  # @param value [Object] The value to return if the receiver is not present.
  # @return [Object] The receiver if it is present, otherwise the given value.
  def present_or(value)
    # TBD whether this is *too* strict
    if value.class != self.class && self.class != NilClass
      raise Errgonomic::TypeMismatchError, "Type mismatch: default value is a #{value.class} but original was a #{self.class}"
    end

    return self if present?

    value
  end

  # Returns the receiver if it is present, otherwise returns the result of the
  # block. Invoking a block may be preferable to returning a default value with
  # +present_or+, if constructing the default value is expensive.
  #
  # @param block [Proc] The block to call if the receiver is not present.
  # @return [Object] The receiver if it is present, otherwise the result of the block.
  def present_or_else(&block)
    return block.call if blank?
    self
  end
end
