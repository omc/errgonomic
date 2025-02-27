# frozen_string_literal: true

RSpec.describe Errgonomic do
  it "has a version number" do
    expect(Errgonomic::VERSION).not_to be nil
  end

  describe "present_or_raise" do
    it "raises an error for various blank objects" do
      expect { nil.present_or_raise("foo") }.to raise_error(Errgonomic::NotPresentError)
      expect { [].present_or_raise("foo") }.to raise_error(Errgonomic::NotPresentError)
      expect { {}.present_or_raise("foo") }.to raise_error(Errgonomic::NotPresentError)
    end

    it "returns the value itself for present types" do
      expect("bar".present_or_raise("foo")).to eq("bar")
      expect(["baz"].present_or_raise("foo")).to eq(["baz"])
      expect({foo: "bar"}.present_or_raise("foo")).to eq({foo: "bar"})
    end
  end

  describe "present_or" do
    it "returns the default value for various blank objects" do
      expect(nil.present_or("foo")).to eq("foo")
      expect([].present_or(["foo"])).to eq(["foo"])
      expect({}.present_or({foo: "bar"})).to eq({foo: "bar"})
    end

    it "rather strictly requires the value to match the starting type, except for nil" do
      expect(nil.present_or("foo")).to eq("foo")
      expect { [].present_or("bar") }.to raise_error(Errgonomic::TypeMismatchError)
      expect { {}.present_or("bar") }.to raise_error(Errgonomic::TypeMismatchError)
    end

    it "even more strictly will fail when default value is not the same type as the original non-blank value" do
      expect { ["foo"].present_or("bad") }.to raise_error(Errgonomic::TypeMismatchError)
      expect { {foo: "bar"}.present_or("bad") }.to raise_error(Errgonomic::TypeMismatchError)
    end

    it "returns the value itself for present types" do
      expect("bar".present_or("foo")).to eq("bar")
      expect(["baz"].present_or(["foo"])).to eq(["baz"])
      expect({foo: "bar"}.present_or({foo: "baz"})).to eq({foo: "bar"})
    end
  end
end
