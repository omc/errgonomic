class TrueClass
  # @example
  #   true.then { :hello } #=> Some(:hello)
  #   false.then { :goodbye } #=> None()
  def then(&block)
    Some(block.call)
  end

  # @example
  #   true.then_some(:hello) #=> Some(:hello)
  #   false.then_some(:goodbye) #=> None()
  def then_some(val)
    Some(val)
  end

  # @example
  #   true.ok_or(:ohno) # => Ok(true)
  #   false.ok_or(:ohno) # => Err(:ohno)
  def ok_or(val)
    Ok(true)
  end

  # @example
  #   true.ok_or_else { :ohno } # => Ok(true)
  #   false.ok_or_else { :ohno } # => Err(:ohno)
  def ok_or_else(&block)
    Ok(true)
  end

end

class FalseClass
  # @example
  #   true.then { :hello } #=> Some(:hello)
  #   false.then { :goodbye } #=> None()
  def then(&block)
    None()
  end

  # @example
  #   true.then_some(:hello) #=> Some(:hello)
  #   false.then_some(:goodbye) #=> None()
  def then_some(_val)
    None()
  end

  # @example
  #   true.ok_or(:ohno) # => Ok(true)
  #   false.ok_or(:ohno) # => Err(:ohno)
  def ok_or(err)
    Err(err)
  end

  # @example
  #   true.ok_or_else { :ohno } # => Ok(true)
  #   false.ok_or_else { :ohno } # => Err(:ohno)
  def ok_or_else(&block)
    Err(block.call)
  end
end
