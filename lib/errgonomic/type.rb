# frozen_string_literal: true

class Object
  # Returns the receiver if it matches the expected type, otherwise raises a TypeMismatchError.
  # This is useful for enforcing type expectations in method arguments.
  #
  # @param type [Class] The expected type or module the receiver should be.
  # @param message [String] Optional error message to raise if type doesn't match.
  # @return [Object] The receiver if it is of the expected type.
  # @example
  #   "hello".type_or_raise!(String)   # => "hello"
  #   123.type_or_raise!(String)       # => raises TypeMismatchError
  #   123.type_or_raise!(String, "Not a string")  # => raises TypeMismatchError with custom message
  def type_or_raise!(type, message = nil)
    message ||= "Expected #{type} but got #{self.class}"
    raise Errgonomic::TypeMismatchError, message unless is_a?(type)

    self
  end

  alias type_or_raise type_or_raise!

  # Returns the receiver if it matches the expected type, otherwise returns the default value.
  #
  # @param type [Class] The expected type or module the receiver should be.
  # @param default [Object] The value to return if type doesn't match.
  # @return [Object] The receiver if it is of the expected type, otherwise the default value.
  # @example
  #   "hello".type_or(String, "default")  # => "hello"
  #   123.type_or(String, "default")      # => "default"
  def type_or(type, default)
    return self if is_a?(type)

    default
  end

  # Returns the receiver if it matches the expected type, otherwise returns the result of the block.
  # Useful when constructing the default value is expensive.
  #
  # @param type [Class] The expected type or module the receiver should be.
  # @param block [Proc] The block to call if type doesn't match.
  # @return [Object] The receiver if it is of the expected type, otherwise the block result.
  # @example
  #   "hello".type_or_else(String) { "default" }  # => "hello"
  #   123.type_or_else(String) { "default" }      # => "default"
  def type_or_else(type, &block)
    return self if is_a?(type)

    block.call
  end

  # Returns the receiver if it does not match the expected type, otherwise raises a TypeMismatchError.
  #
  # @param type [Class] The type or module the receiver should not be.
  # @param message [String] Optional error message to raise if type matches.
  # @return [Object] The receiver if it is not of the specified type.
  # @example
  #   "hello".not_type_or_raise!(Integer)  # => "hello"
  #   123.not_type_or_raise!(Integer)      # => raises TypeMismatchError
  #   123.not_type_or_raise!(Integer, "Not an integer")  # => raises TypeMismatchError with custom message
  def not_type_or_raise!(type, message = nil)
    message ||= "Expected anything but #{type} but got #{self.class}"
    raise Errgonomic::TypeMismatchError, message if is_a?(type)

    self
  end
end
