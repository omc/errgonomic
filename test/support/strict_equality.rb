# frozen_string_literal: true

# The Rails integration suite with cross-type equality raising, so a
# comparison between a wrapper and a plain value anywhere under ActiveRecord
# fails the run rather than quietly answering false.
require_relative '../../lib/errgonomic'

Errgonomic.strict_equality = true

require_relative '../rails_test'
