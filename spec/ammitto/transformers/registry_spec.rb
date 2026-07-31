# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Transformers::Registry do
  describe '.get' do
    it 'returns Uk::Transformer for :uk' do
      transformer = described_class.get(:uk)
      expect(transformer).to be_a(Ammitto::Sources::Uk::Transformer)
    end

    it 'returns Eu::Transformer for :eu' do
      transformer = described_class.get(:eu)
      expect(transformer).to be_a(Ammitto::Sources::Eu::Transformer)
    end

    it 'returns Un::Transformer for :un' do
      transformer = described_class.get(:un)
      expect(transformer).to be_a(Ammitto::Sources::Un::Transformer)
    end

    it 'returns Us::Transformer for :us' do
      transformer = described_class.get(:us)
      expect(transformer).to be_a(Ammitto::Sources::Us::Transformer)
    end

    it 'returns Wb::Transformer for :wb' do
      transformer = described_class.get(:wb)
      expect(transformer).to be_a(Ammitto::Sources::Wb::Transformer)
    end

    it 'returns Au::Transformer for :au' do
      transformer = described_class.get(:au)
      expect(transformer).to be_a(Ammitto::Sources::Au::Transformer)
    end

    it 'returns Ca::Transformer for :ca' do
      transformer = described_class.get(:ca)
      expect(transformer).to be_a(Ammitto::Sources::Ca::Transformer)
    end

    it 'returns Ch::Transformer for :ch' do
      transformer = described_class.get(:ch)
      expect(transformer).to be_a(Ammitto::Sources::Ch::Transformer)
    end

    it 'returns Cn::Transformer for :cn' do
      transformer = described_class.get(:cn)
      expect(transformer).to be_a(Ammitto::Sources::Cn::Transformer)
    end

    it 'returns Ru::Transformer for :ru' do
      transformer = described_class.get(:ru)
      expect(transformer).to be_a(Ammitto::Sources::Ru::Transformer)
    end

    it 'returns nil for unknown source' do
      expect(described_class.get(:unknown)).to be_nil
    end
  end

  describe '.supported_sources' do
    it 'returns array of supported source codes' do
      expect(described_class.supported_sources).to contain_exactly(
        :uk, :eu, :un, :us, :wb, :au, :ca, :ch, :cn, :ru, :nz, :tr,
        :eu_vessels, :jp, :un_vessels
      )
    end
  end

  describe '.supported?' do
    it 'returns true for supported sources' do
      expect(described_class.supported?(:uk)).to be true
      expect(described_class.supported?(:eu)).to be true
    end

    it 'returns false for unsupported sources' do
      expect(described_class.supported?(:unknown)).to be false
    end
  end
end
