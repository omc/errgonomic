# frozen_string_literal: true

require_relative '../option'

module Errgonomic
  module Enumerable
    # Optional Hash
    #
    # Implements a hash where fetching returns an +Option+ instead of nil. We
    # focus on the #[] operator and #dig function, because #fetch will raise
    # KeyError when the key is not present.
    #
    class OptionalHash < ::Hash
      # Retrieve a value with a given key, wrapping the value in an Option. The
      # +nil+ value is replaced with a +None+ and anything else is wrapped in
      # +Some+.
      #
      # @example
      #   h = Errgonomic::Enumerable::OptionalHash.new
      #   h[:color] = :blue
      #   h[:color] #=> Some(:blue)
      def [](key)
        obj = super(key)
        obj.nil? ? None() : Some(obj)
      end

      # Similar to +Hash#dig+ but wrapped in an Option.
      #
      # @example
      #   h = Errgonomic::Enumerable::OptionalHash.new
      #   h[:description] = Errgonomic::Enumerable::OptionalHash.new
      #   h[:description].unwrap![:short] = "It's a thing"
      #   h.dig(:description, :short) # => Some("It's a thing")
      #   h.dig(:description, :long) # => None()
      #
      # @example
      #   h = Errgonomic::Enumerable::OptionalHash.new
      #   h[:description] = { short: { text: "Nested hash" } }
      #   h.dig(:description, :short, :text) # => Some("Nested hash")
      #   h.dig(:description, :long) # => None()
      def dig(*args)
        obj = super(*args)

        return None() if obj.nil? || obj.is_a?(Errgonomic::Option::None)

        obj = obj.unwrap! while obj.is_a?(Errgonomic::Option::Some)

        Some(obj)
      end
    end
  end
end
