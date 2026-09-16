# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/errgonomic'

# An Option implements no coercion protocol, so Ruby's own numeric coercion
# refuses it rather than reaching the inner value. Defining coerce, to_str or
# to_ary would make Array(), splat, flatten and arithmetic treat a wrapper as
# its payload, which is the silent unwrap the library exists to prevent.
class OptionCoercionTest < Minitest::Test
  TIME_COERCION_MESSAGE = "can't convert Errgonomic::Option::Some into an exact number"
  INTEGER_COERCION_MESSAGE = "Errgonomic::Option::Some can't be coerced into Integer"

  def test_time_arithmetic_raises_a_type_error_naming_the_class
    error = assert_raises(TypeError) { Time.at(0) - Some(Time.at(0)) }

    assert_equal TIME_COERCION_MESSAGE, error.message
  end

  def test_integer_arithmetic_raises_a_type_error_naming_the_class
    error = assert_raises(TypeError) { 1 - Some(1) }

    assert_equal INTEGER_COERCION_MESSAGE, error.message
  end

  def test_an_option_defines_none_of_the_coercion_protocols
    refute_respond_to Some(1), :coerce
    refute_respond_to Some('x'), :to_str
    refute_respond_to Some([1]), :to_ary
  end
end
