# frozen_string_literal: true

# What a wrapped attribute read costs, against the plain reader it replaces.
#
# Every converted model pays this on every read of a nullable column, so the
# reader is the one place in the library where a few nanoseconds matter. Two
# figures are reported per shape: wall time per read, and objects allocated
# per read, measured as the marginal cost of a second batch so the harness
# itself cancels out.
#
#   rake benchmark:optional_reader

require 'active_record'
require 'benchmark'
require 'logger'

require_relative '../lib/errgonomic/rails'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = Logger.new(File::NULL)

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table 'readings', force: :cascade do |t|
    t.string :note
  end
end

Errgonomic::Rails.setup_before

# The reader ActiveRecord would have given us, as the floor.
class PlainReading < ActiveRecord::Base
  self.table_name = 'readings'
end

# The reader the concern generates, guard and all.
class WrappedReading < ActiveRecord::Base
  self.table_name = 'readings'
  include Errgonomic::Rails::ActiveRecordOptional
end

# Wrapping with no guard at all, as the ceiling on what the guard may cost:
# the difference between this and WrappedReading is the guard's price.
class UnguardedReading < ActiveRecord::Base
  self.table_name = 'readings'

  def note
    val = super
    val.nil? ? Errgonomic::Option::None.new : Errgonomic::Option::Some.new(val)
  end
end

SHAPES = { 'plain' => PlainReading, 'wrapped' => WrappedReading, 'unguarded' => UnguardedReading }.freeze
READS = 200_000

def nanoseconds_per_read(record)
  record.note
  Benchmark.realtime { READS.times { record.note } } / READS * 1e9
end

def allocations_per_read(record)
  record.note
  before = GC.stat(:total_allocated_objects)
  READS.times { record.note }
  one_batch = GC.stat(:total_allocated_objects)
  (READS * 2).times { record.note }
  two_batches = GC.stat(:total_allocated_objects) - one_batch
  (two_batches - (one_batch - before)).fdiv(READS)
end

records = SHAPES.transform_values { |klass| klass.new(note: 'present') }
baseline = nanoseconds_per_read(records.fetch('plain'))

puts format('%-10s %10s %10s %14s', 'shape', 'ns/read', 'vs plain', 'allocs/read')
records.each do |name, record|
  nanoseconds = nanoseconds_per_read(record)
  puts format('%-10s %10.0f %9.1fx %14.1f', name, nanoseconds, nanoseconds / baseline,
              allocations_per_read(record))
end
