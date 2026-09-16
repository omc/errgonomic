# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/errgonomic'

# An Option implements no coercion protocol, so Ruby's own numeric coercion
# refuses it rather than reaching the inner value. Array() and splat already
# reach the value, through to_a. Defining to_ary would extend that to flatten,
# multiple assignment, Array#+ and block destructuring, and defining coerce or
# to_str would extend it to arithmetic and to string conversion. Each of those
# is the silent unwrap the library exists to prevent.
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

  def test_array_conversion_reaches_the_value_through_to_a
    assert_equal [1], Array(Some(1))
  end

  def test_an_option_defines_none_of_the_coercion_protocols
    refute_respond_to Some(1), :coerce
    refute_respond_to Some('x'), :to_str
    refute_respond_to Some([1]), :to_ary
  end
end
