module Enumerable
  # Collect an Enumerable of Results into a Result of an Array. Short-circuits
  # on the first Err.
  #
  # @example
  #   [].collect_results                      # => Ok([])
  #   [Ok(1), Ok(2), Ok(3)].collect_results   # => Ok([1, 2, 3])
  #   [Ok(1), Err(:x), Ok(3)].collect_results # => Err(:x)
  #   [Ok(1), "oops", Ok(3)].collect_results  # => raise Errgonomic::ArgumentError, "collect_results expects every element to be a Result, got String"
  #   [Ok(1), Some(2), Ok(3)].collect_results # => raise Errgonomic::ArgumentError, "collect_results expects every element to be a Result, got Errgonomic::Option::Some"
  #
  # @return [Errgonomic::Result::Any]
  def collect_results
    return Ok([]) if empty?

    values = []

    each do |element|
      if Errgonomic.give_me_ambiguous_downstream_errors?
        # defensive runtime checks about the contents of the enumerable
        if !element.is_a?(Errgonomic::Result::Any)
          raise Errgonomic::ArgumentError, "collect_results expects every element to be a Result, got #{element.class}"
        end
      end

      return element if element.err?

      values << element.value
    end

    Ok(values)
  end

  # Collect an Enumerable of Options into an Option of an Array. Short-circuits
  # on the first None.
  #
  # @example
  #   [].collect_options                          # => Some([])
  #   [Some(1), Some(2), Some(3)].collect_options # => Some([1, 2, 3])
  #   [Some(1), None(), Some(3)].collect_options  # => None()
  #   [Some(1), "oops", Some(3)].collect_options  # => raise Errgonomic::ArgumentError, "collect_options expects every element to be a Option, got String"
  #   [Some(1), Ok(2), Some(3)].collect_options   # => raise Errgonomic::ArgumentError, "collect_options expects every element to be a Option, got Errgonomic::Result::Ok"
  #
  # @return [Errgonomic::Result::Any]
  def collect_options
    return Some([]) if empty?

    values = []

    each do |element|
      if Errgonomic.give_me_ambiguous_downstream_errors?
        # defensive runtime checks about the contents of the enumerable
        if !element.is_a?(Errgonomic::Option::Any)
          raise Errgonomic::ArgumentError, "collect_options expects every element to be a Option, got #{element.class}"
        end
      end

      return element if element.none?

      values << element.value
    end

    Some(values)
  end


  # # WIP
  # def traverse
  # end
end
