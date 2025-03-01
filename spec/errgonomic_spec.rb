# frozen_string_literal: true

Ok = Errgonomic::Result::Ok
Err = Errgonomic::Result::Err

RSpec.describe Errgonomic do
  it 'has a version number' do
    expect(Errgonomic::VERSION).not_to be nil
  end

  describe 'present_or_raise' do
    it 'raises an error for various blank objects' do
      expect { nil.present_or_raise('foo') }.to raise_error(Errgonomic::NotPresentError)
      expect { [].present_or_raise('foo') }.to raise_error(Errgonomic::NotPresentError)
      expect { {}.present_or_raise('foo') }.to raise_error(Errgonomic::NotPresentError)
    end

    it 'returns the value itself for present types' do
      expect('bar'.present_or_raise('foo')).to eq('bar')
      expect(['baz'].present_or_raise('foo')).to eq(['baz'])
      expect({ foo: 'bar' }.present_or_raise('foo')).to eq({ foo: 'bar' })
    end
  end

  describe 'present_or' do
    it 'returns the default value for various blank objects' do
      expect(nil.present_or('foo')).to eq('foo')
      expect([].present_or(['foo'])).to eq(['foo'])
      expect({}.present_or({ foo: 'bar' })).to eq({ foo: 'bar' })
    end

    it 'rather strictly requires the value to match the starting type, except for nil' do
      expect(nil.present_or('foo')).to eq('foo')
      expect { [].present_or('bar') }.to raise_error(Errgonomic::TypeMismatchError)
      expect { {}.present_or('bar') }.to raise_error(Errgonomic::TypeMismatchError)
    end

    it 'even more strictly will fail when default value is not the same type as the original non-blank value' do
      expect { ['foo'].present_or('bad') }.to raise_error(Errgonomic::TypeMismatchError)
      expect { { foo: 'bar' }.present_or('bad') }.to raise_error(Errgonomic::TypeMismatchError)
    end

    it 'returns the value itself for present types' do
      expect('bar'.present_or('foo')).to eq('bar')
      expect(['baz'].present_or(['foo'])).to eq(['baz'])
      expect({ foo: 'bar' }.present_or({ foo: 'baz' })).to eq({ foo: 'bar' })
    end
  end

  describe 'blank_or_raise' do
    it 'raises an error for present objects' do
      expect { 'bar'.blank_or_raise('foo') }.to raise_error(Errgonomic::NotPresentError)
      expect { ['baz'].blank_or_raise('foo') }.to raise_error(Errgonomic::NotPresentError)
      expect { { foo: 'bar' }.blank_or_raise('foo') }.to raise_error(Errgonomic::NotPresentError)
    end

    it 'returns the value itself for blank types' do
      expect(nil.blank_or_raise('foo')).to eq(nil)
      expect([].blank_or_raise('foo')).to eq([])
      expect({}.blank_or_raise('foo')).to eq({})
    end
  end

  describe 'blank_or' do
    it 'returns the receiver for blank objects' do
      expect(nil.blank_or('foo')).to eq(nil)
      expect([].blank_or(['foo'])).to eq([])
      expect({}.blank_or({ foo: 'bar' })).to eq({})
    end

    it 'returns the default value for present objects' do
      expect('bar'.blank_or('foo')).to eq('foo')
      expect(['baz'].blank_or(['foo'])).to eq(['foo'])
      expect({ foo: 'bar' }.blank_or({ foo: 'baz' })).to eq({ foo: 'baz' })
    end

    it 'enforces type checks similar to present_or' do
      expect { 'bar'.blank_or(['foo']) }.to raise_error(Errgonomic::TypeMismatchError)
      expect { [].blank_or('foo') }.to raise_error(Errgonomic::TypeMismatchError)
    end
  end

  describe 'blank_or_else' do
    it 'returns the receiver for blank objects' do
      expect(nil.blank_or_else { 'foo' }).to eq(nil)
      expect([].blank_or_else { ['foo'] }).to eq([])
      expect({}.blank_or_else { { foo: 'bar' } }).to eq({})
    end

    it 'returns the result of the block for present objects' do
      expect('bar'.blank_or_else { 'foo' }).to eq('foo')
      expect(['baz'].blank_or_else { ['foo'] }).to eq(['foo'])
      expect({ foo: 'bar' }.blank_or_else { { foo: 'baz' } }).to eq({ foo: 'baz' })
    end
  end

  describe 'Result' do
    describe 'Ok' do
      it 'must be constructed with an inner value' do
        expect { Ok.new }.to raise_error(ArgumentError)
      end
    end

    describe 'Err' do
      it 'can be constructed with or without an inner value' do
        expect(Err.new).to be_err
        expect(Err.new('foo')).to be_err
      end

      it 'is err' do
        result = Errgonomic::Result::Err.new
        expect(result).to be_err
      end

      it 'is not ok' do
        result = Errgonomic::Result::Err.new
        expect(result).not_to be_ok
      end

      it 'raises exception on unwrap' do
        result = Errgonomic::Result::Err.new('foo')
        expect { result.unwrap! }.to raise_error(Errgonomic::UnwrapError)
      end

      it 'raises an exception with a given message on expect' do
        result = Errgonomic::Result::Err.new('foo')
        expect { result.expect!('bar') }.to raise_error(Errgonomic::ExpectError)
      end
    end

    it 'has a basic dsl for match' do
      result = Errgonomic::Result::Err.new('foo')
      matched = result.match do
        ok { |val| :foo }
        err { |err| :bar }
      end
      expect(matched).to eq(:bar)

      result = Errgonomic::Result::Ok.new('foo')
      matched = result.match do
        ok { |val| :foo }
        err { |err| :bar }
      end
      expect(matched).to eq(:foo)
    end

    describe 'ok_and' do
      it 'returns true if ok and the inner block evals to truthy, else false' do
        expect(Ok.new('foo').ok_and? { true }).to be true
        expect(Ok.new('foo').ok_and? { false }).to be false
        expect(Err.new('foo').ok_and? { true }).to be false
        expect(Err.new('foo').ok_and? { false }).to be false
      end
    end

    describe 'err_and?' do
      it 'returns true if err and the inner block evals to truthy, else false' do
        expect(Err.new('foo').err_and? { true }).to be true
        expect(Err.new('foo').err_and? { false }).to be false
        expect(Ok.new('foo').err_and? { true }).to be false
        expect(Ok.new('foo').err_and? { false }).to be false
      end
    end

    describe 'and' do
      it 'returns the result of the block if the original value is ok, else returns the err value' do
        result = Ok.new('foo')
        expect(result.and(Ok.new(:bar)).unwrap!).to eq(:bar)

        result = Err.new('foo')
        expect(result.and(Ok.new(:bar))).to be_err
      end

      it 'must take a block that returns a result; ew' do
        result = Ok.new('foo')
        expect { result.and(:bar) }.to raise_error(Errgonomic::ArgumentError)
      end
    end

    describe 'and_then' do
      it 'returns the result from the block if the original is an ok' do
        result = Ok.new('foo')
        expect(result.and_then { Ok.new(:bar) }.unwrap!).to eq(:bar)
        result = Err.new('foo')
        expect(result.and_then { Ok.new(:bar) }).to eq(result)
      end

      it 'is lazy' do
        inner = Err.new('foo')
        result = inner.and_then { raise 'noisy' }
        expect(result).to be_err
        expect(result).to eq(inner)
      end

      it 'enforces the return type of the block at runtime, ew' do
        inner = Ok.new('foo')
        expect { inner.and_then { :bar } }.to raise_error(Errgonomic::ArgumentError)
      end

      it 'can skip that runtime enforcement, which is so much worse' do
        inner = Ok.new('foo')
        Errgonomic.with_ambiguous_downstream_errors do
          expect { inner.and_then { :bar } }.not_to raise_error
          expect(inner.and_then { :baz }).to eq(:baz)
        end
      end
    end

    describe 'or' do
      it 'returns the original result when it is Ok' do
        expect(Ok.new(:foo).or(Ok.new(:bar)).unwrap!).to eq(:foo)
      end

      it 'returns the other result when the original is Err' do
        expect(Err.new('foo').or(Ok.new(:bar)).unwrap!).to eq(:bar)
      end

      it 'enforces that the other value is a result' do
        expect { Err.new('foo').or(:bar) }.to raise_error(Errgonomic::ArgumentError)
      end

      it 'cannot opt out of runtime enforcement' do
        Errgonomic.with_ambiguous_downstream_errors do
          expect { Err.new('foo').or(:bar) }.to raise_error(Errgonomic::ArgumentError)
        end
      end
    end

    describe 'or_else' do
      it 'returns the original result when it is Ok' do
        expect(Ok.new(:foo).or_else { Ok.new(:bar) }.unwrap!).to eq(:foo)
      end

      it 'returns the other result when the original is Err' do
        expect(Err.new('foo').or_else { Ok.new(:bar) }.unwrap!).to eq(:bar)
      end

      it 'enforces that the other value is a result' do
        expect { Err.new('foo').or_else { :bar } }.to raise_error(Errgonomic::ArgumentError)
      end

      it 'can opt out of runtime result type enforcement' do
        Errgonomic.with_ambiguous_downstream_errors do
          expect { Err.new('foo').or_else { :bar } }.not_to raise_error
        end
      end
    end

    describe 'unwrap_or' do
      it 'returns the contained Ok value or the provided default' do
        expect(Ok.new(:foo).unwrap_or(:bar)).to eq(:foo)
        expect(Err.new(:foo).unwrap_or(:bar)).to eq(:bar)
      end
    end

    describe 'unwrap_or_else' do
      it 'returns the contained Ok value or the result of the provided block' do
        expect(Ok.new(:foo).unwrap_or_else { raise 'noisy' }).to eq(:foo)
        expect(Err.new(:foo).unwrap_or_else { :bar }).to eq(:bar)
      end
    end

    describe 'Ok()' do
      it 'creates an Ok' do
        expect(Ok(:foo)).to be_a(Errgonomic::Result::Ok)
      end
    end

    describe 'Err()' do
      it 'creates an Err' do
        expect(Err(:foo)).to be_a(Errgonomic::Result::Err)
      end
    end

    describe 'Object#assert_result!' do
      it 'raises an exception if the object is not a Result' do
        expect { :foo.assert_result! }.to raise_error(Errgonomic::ResultRequiredError)
        expect { Ok(:foo).assert_result! }.not_to raise_error
        expect { Err(:foo).assert_result! }.not_to raise_error
      end
    end
  end
end
