# frozen_string_literal: true

require_relative '../option'
require_relative '../result'

# Lift booleans into Option and Result, following Rust's bool: then_some,
# and ok_or/ok_or_else from nightly. Rust splits the lazy form into `then`,
# but that name is core Ruby (Kernel#then), so then_some takes either a
# value or a block. Rust's ok_or returns Result<(), E>; Ruby has no unit
# type, so Ok carries true.
class TrueClass
  # @example
  #   true.then_some(:hello) # => Some(:hello)
  #   true.then_some { :hello } # => Some(:hello)
  #   true.then_some(nil) # => Some(nil)
  #   true.then_some # => raise Errgonomic::ArgumentError, "then_some takes either a value or a block"
  def then_some(*args, &block)
    if args.length == 1 && !block
      Some(args[0])
    elsif args.empty? && block
      Some(block.call)
    else
      raise Errgonomic::ArgumentError, 'then_some takes either a value or a block'
    end
  end

  # @example
  #   true.ok_or(:ohno) # => Ok(true)
  def ok_or(_err)
    Ok(true)
  end

  # @example
  #   true.ok_or_else { :ohno } # => Ok(true)
  def ok_or_else
    Ok(true)
  end
end

# The false halves of the conversions above.
class FalseClass
  # The block is never called; arguments are validated all the same, so a
  # misuse fails regardless of which way the flag happens to point.
  #
  # @example
  #   false.then_some(:hello) # => None()
  #   false.then_some { :hello } # => None()
  #   false.then_some # => raise Errgonomic::ArgumentError, "then_some takes either a value or a block"
  def then_some(*args, &block)
    unless (args.length == 1 && !block) || (args.empty? && block)
      raise Errgonomic::ArgumentError, 'then_some takes either a value or a block'
    end

    None()
  end

  # @example
  #   false.ok_or(:ohno) # => Err(:ohno)
  def ok_or(err)
    Err(err)
  end

  # @example
  #   false.ok_or_else { :ohno } # => Err(:ohno)
  def ok_or_else(&block)
    Err(block.call)
  end
end
