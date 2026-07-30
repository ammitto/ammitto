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

  describe '::SOURCE_LIST_TYPES' do
    it 'keys vessel sources with underscores (the gem source codes)' do
      expect(described_class::SOURCE_LIST_TYPES)
        .to include('eu_vessels', 'un_vessels')
    end

    it 'holds no hyphenated source keys' do
      expect(described_class::SOURCE_LIST_TYPES.keys.grep(/-/)).to be_empty
    end
  end

  describe '.list_types_for' do
    it 'returns list types for China' do
      result = described_class.list_types_for('cn')
      expect(result).to be_a(Hash)
      expect(result.keys).to include('anti-sanction-list', 'import-export-control-list', 'unreliable-entity-list')
    end

    it 'resolves eu_vessels by its underscored source code' do
      result = described_class.list_types_for('eu_vessels')
      expect(result).to be_a(Hash)
      expect(result.keys).to eq(['vessel-sanctions-list'])
    end

    it 'resolves un_vessels by its underscored source code' do
      result = described_class.list_types_for(:un_vessels)
      expect(result).to be_a(Hash)
      expect(result.keys).to eq(['vessel-sanctions-list'])
    end

    it 'normalizes legacy hyphenated aliases from repo-derived codes' do
      expect(described_class.list_types_for('eu-vessels'))
        .to eq(described_class::EU_VESSELS)
      expect(described_class.list_types_for('UN-Vessels'))
        .to eq(described_class::UN_VESSELS)
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

    it 'returns the vessel list for eu_vessels' do
      expect(described_class.default_list_type('eu_vessels'))
        .to eq('vessel-sanctions-list')
    end

    it 'returns the vessel list for un_vessels' do
      expect(described_class.default_list_type('un_vessels'))
        .to eq('vessel-sanctions-list')
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
