module Enumerable
  # Collect an Enumerable of Results into a Result of an Array. Or collects the
  # Enumerable of Options into an Option of an Array. Short-circuits on the
  # first Err or None.
  #
  # @example
  #   [].sequence                      # => Ok([])
  #   [Ok(1), Ok(2), Ok(3)].sequence   # => Ok([1, 2, 3])
  #   [Ok(1), Err(:x), Ok(3)].sequence # => Err(:x)
  #   [Ok(1), "oops", Ok(3)].sequence  # => raise Errgonomic::ArgumentError, "sequence expects every element to be a Result, got String"
  #   [Ok(1), Some(2), Ok(3)].sequence # => raise Errgonomic::ArgumentError, "sequence expects every element to be the same kind of Result or Option"
  #   ["shrug"].sequence               # => raise Errgonomic::ArgumentError, "sequence must be called on an enumerable of Results or Options"
  #
  # @return [Errgonomic::Result::Any]
  def sequence
    return Ok([]) if empty?

    values = []

    sequence_inner_type = find { |e| e.is_a?(Errgonomic::Result::Any) || e.is_a?(Errgonomic::Option::Any) }
    if sequence_inner_type.nil?
      raise Errgonomic::ArgumentError, "sequence must be called on an enumerable of Results or Options"
    end
    sequence_inner_type = sequence_inner_type.class.superclass
    each do |element|
      # defensive runtime checks about the contents of the enumerable
      if Errgonomic.give_me_ambiguous_downstream_errors?
        # must be
        if !element.is_a?(sequence_inner_type) && (element.is_a?(Errgonomic::Result::Any) || element.is_a?(Errgonomic::Option::Any))
          raise Errgonomic::ArgumentError, "sequence expects every element to be the same kind of Result or Option"
        end

        if !element.is_a?(sequence_inner_type)
          result_or_option = sequence_inner_type == Errgonomic::Result::Any ? "Result" : "Option"
          raise Errgonomic::ArgumentError, "sequence expects every element to be a #{result_or_option}, got #{element.class}"
        end
      end

      return element if element.is_a?(Errgonomic::Result::Any) && element.err?
      return element if element.is_a?(Errgonomic::Option::Any) && element.none?

      values << element.value
    end
    Ok(values)
  end


  # # WIP
  # def traverse
  # end
end
