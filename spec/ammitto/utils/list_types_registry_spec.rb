# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Utils::ListTypesRegistry do
  describe '::CN' do
    it 'includes anti-sanction-list' do
      expect(described_class::CN).to have_key('anti-sanction-list')
    end

    it 'includes import-export-control-list' do
      expect(described_class::CN).to have_key('import-export-control-list')
    end

    it 'includes unreliable-entity-list' do
      expect(described_class::CN).to have_key('unreliable-entity-list')
    end
  end

  describe '::RU' do
    it 'includes stop-list' do
      expect(described_class::RU).to have_key('stop-list')
    end
  end

  describe '::US' do
    it 'includes sdn-list' do
      expect(described_class::US).to have_key('sdn-list')
    end

    it 'includes entity-list' do
      expect(described_class::US).to have_key('entity-list')
    end
  end

  describe '.list_types_for' do
    it 'returns list types for China' do
      result = described_class.list_types_for('cn')
      expect(result).to be_a(Hash)
      expect(result.keys).to include('anti-sanction-list', 'import-export-control-list', 'unreliable-entity-list')
    end

    it 'returns list types for Russia' do
      result = described_class.list_types_for('ru')
      expect(result).to be_a(Hash)
      expect(result.keys).to include('stop-list')
    end

    it 'returns nil for unknown source' do
      expect(described_class.list_types_for('unknown')).to be_nil
    end

    it 'handles symbol source codes' do
      result = described_class.list_types_for(:cn)
      expect(result).to be_a(Hash)
    end
  end

  describe '.get' do
    it 'returns info for a specific list type' do
      result = described_class.get('cn', 'anti-sanction-list')
      expect(result).to be_a(Hash)
      expect(result[:name]).to eq('Anti-Sanction List')
    end

    it 'returns nil for unknown list type' do
      expect(described_class.get('cn', 'unknown-list')).to be_nil
    end

    it 'returns nil for unknown source' do
      expect(described_class.get('unknown', 'some-list')).to be_nil
    end
  end

  describe '.exists?' do
    it 'returns true for existing list type' do
      expect(described_class.exists?('cn', 'anti-sanction-list')).to be true
    end

    it 'returns false for non-existing list type' do
      expect(described_class.exists?('cn', 'unknown-list')).to be false
    end
  end

  describe '.all_list_types' do
    it 'returns an array of unique list types' do
      result = described_class.all_list_types
      expect(result).to be_an(Array)
      expect(result).to include('anti-sanction-list', 'consolidated-list', 'stop-list')
    end

    it 'returns sorted list types' do
      result = described_class.all_list_types
      expect(result).to eq(result.sort)
    end
  end

  describe '.default_list_type' do
    it 'returns first list type for China' do
      result = described_class.default_list_type('cn')
      expect(result).to eq('anti-sanction-list')
    end

    it 'returns first list type for Russia' do
      result = described_class.default_list_type('ru')
      expect(result).to eq('stop-list')
    end

    it 'returns nil for unknown source' do
      expect(described_class.default_list_type('unknown')).to be_nil
    end
  end

  describe '.all_sources' do
    it 'returns all source codes' do
      result = described_class.all_sources
      expect(result).to be_an(Array)
      expect(result).to include('cn', 'ru', 'eu', 'uk', 'us')
    end

    it 'returns sorted sources' do
      result = described_class.all_sources
      expect(result).to eq(result.sort)
    end
  end
end
