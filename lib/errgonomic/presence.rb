# frozen_string_literal: true

# The semantics here borrow heavily from ActiveSupport. Let's prefer that if
# loaded, otherwise just copypasta the bits we like. Or convince me to make that
# gem a dependency.
require_relative './core_ext/blank' unless Object.methods.include?(:blank?)

class Object
  # Returns the receiver if it is present, otherwise raises a NotPresentError.
  # This method is useful to enforce strong expectations, where it is preferable
  # to fail early rather than risk causing an ambiguous error somewhere else.
  #
  # @param message [String] The error message to raise if the receiver is not present.
  # @return [Object] The receiver if it is present, otherwise raises a NotPresentError.
  def present_or_raise!(message)
    raise Errgonomic::NotPresentError, message if blank?

    self
  end

  alias_method :present_or_raise, :present_or_raise!

  # Returns the receiver if it is present, otherwise returns the given value. If
  # constructing the default value is expensive, consider using
  # +present_or_else+.
  #
  # @param value [Object] The value to return if the receiver is not present.
  # @return [Object] The receiver if it is present, otherwise the given value.
  def present_or(value)
    # TBD whether this is *too* strict
    if value.class != self.class && self.class != NilClass
      raise Errgonomic::TypeMismatchError,
            "Type mismatch: default value is a #{value.class} but original was a #{self.class}"
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

  # Returns the receiver if it is blank, otherwise raises a NotPresentError.
  # This method is helpful to enforce expectations where blank objects are required.
  #
  # @param message [String] The error message to raise if the receiver is not blank.
  # @return [Object] The receiver if it is blank, otherwise raises a NotPresentError.
  def blank_or_raise!(message)
    raise Errgonomic::NotPresentError, message unless blank?

    self
  end

  alias_method :blank_or_raise, :blank_or_raise!

  # Returns the receiver if it is blank, otherwise returns the given value.
  #
  # @param value [Object] The value to return if the receiver is not blank.
  # @return [Object] The receiver if it is blank, otherwise the given value.
  def blank_or(value)
    # TBD whether this is *too* strict
    if value.class != self.class && self.class != NilClass
      raise Errgonomic::TypeMismatchError,
            "Type mismatch: default value is a #{value.class} but original was a #{self.class}"
    end

    return self if blank?

    value
  end

  # Returns the receiver if it is blank, otherwise returns the result of the
  # block.
  #
  # @param block [Proc] The block to call if the receiver is not blank.
  # @return [Object] The receiver if it is blank, otherwise the result of the block.
  def blank_or_else(&block)
    return block.call unless blank?

    self
  end
end
