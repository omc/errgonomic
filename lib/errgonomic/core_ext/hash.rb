# frozen_string_literal: true

require_relative '../option'
require_relative '../optional_hash'

# Two additive lookups; no existing Hash behavior changes. This is as deep as
# the gem reaches into Hash: the wider Ruby ecosystem leans on Hash semantics
# too heavily to patch them, so richer behavior lives in
# Errgonomic::OptionalHash instead.
class Hash
  # Retrieve the value for a key, wrapped in an Option, following key
  # presence as Rust's HashMap#get does: a present key with a nil value is
  # Some(nil); only a missing key is None.
  #
  # @example
  #   h = { color: :blue, shade: nil }
  #   h.fetch_option(:color) # => Some(:blue)
  #   h.fetch_option(:shade) # => Some(nil)
  #   h.fetch_option(:smell) # => None()
  def fetch_option(key)
    return None() unless key?(key)

    Some(self[key])
  end

  # Wrap this hash in an Errgonomic::OptionalHash view. The wrapper reads and
  # writes this same hash; use its to_h for a detached copy.
  #
  # @example
  #   h = { color: :blue }.into_optional
  #   h[:color] # => Some(:blue)
  #   h[:smell] # => None()
  def into_optional
    Errgonomic::OptionalHash.new(self)
  end
end
