# frozen_string_literal: true

RSpec.describe Ammitto::Registry do
  describe '.register' do
    it 'registers a source' do
      class TestSource < Ammitto::BaseSource
        def code
          :test
        end
      end

      described_class.register(:test, TestSource)
      expect(described_class.registered?(:test)).to be true
      # Clean up only our test source
      described_class.instance_variable_get(:@sources).delete(:test)
    end
  end

  describe '.get' do
    it 'returns registered source class' do
      expect(described_class.get(:eu)).to eq(Ammitto::EuSource)
      expect(described_class.get(:un)).to eq(Ammitto::UnSource)
      expect(described_class.get(:us)).to eq(Ammitto::UsSource)
    end

    it 'returns nil for unregistered source' do
      expect(described_class.get(:nonexistent)).to be_nil
    end
  end

  describe '.codes' do
    it 'returns sorted list of source codes' do
      codes = described_class.codes
      expect(codes).to be_an(Array)
      expect(codes).to include(:eu, :un, :us, :wb, :uk, :au, :ca, :ch, :cn, :ru)
      expect(codes).to eq(codes.sort)
    end
  end

  describe '.instance' do
    it 'returns new instance of source' do
      instance = described_class.instance(:eu)
      expect(instance).to be_a(Ammitto::EuSource)
      expect(instance.code).to eq(:eu)
    end
  end
end
