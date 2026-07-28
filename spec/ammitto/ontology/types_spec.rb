# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology/types'

RSpec.describe Ammitto::Ontology::Types do
  describe 'ENTITY_TYPES' do
    it 'contains expected types' do
      expect(described_class::ENTITY_TYPES).to include(:person, :organization, :vessel, :aircraft)
    end

    it 'is frozen' do
      expect(described_class::ENTITY_TYPES).to be_frozen
    end
  end

  describe 'IDENTIFICATION_TYPES' do
    it 'contains expected types' do
      expect(described_class::IDENTIFICATION_TYPES).to include(:passport, :national_id, :tax_id)
    end

    it 'is frozen' do
      expect(described_class::IDENTIFICATION_TYPES).to be_frozen
    end
  end

  describe 'SANCTION_EFFECT_TYPES' do
    it 'contains expected types' do
      expect(described_class::SANCTION_EFFECT_TYPES).to include(:asset_freeze, :travel_ban, :arms_embargo)
    end

    it 'is frozen' do
      expect(described_class::SANCTION_EFFECT_TYPES).to be_frozen
    end
  end

  describe 'SANCTION_STATUSES' do
    it 'contains expected statuses' do
      expect(described_class::SANCTION_STATUSES).to include(:active, :delisted, :expired)
    end
  end

  describe 'LEGAL_INSTRUMENT_TYPES' do
    it 'contains expected types' do
      expect(described_class::LEGAL_INSTRUMENT_TYPES).to include(:regulation, :decision, :resolution)
    end
  end

  describe 'NAME_SCRIPTS' do
    it 'contains expected scripts' do
      expect(described_class::NAME_SCRIPTS).to include(:Latn, :Cyrl, :Arab, :Hani)
    end

    it 'holds only ISO 15924 codes plus :other (no comment tokens)' do
      described_class::NAME_SCRIPTS.each do |script|
        expect(script.to_s).to match(/\A(?:[A-Z][a-z]{3}|other)\z/)
      end
    end

    it 'uses the ISO 15924 code Grek, not the prose word Greek' do
      expect(described_class::NAME_SCRIPTS).to include(:Grek)
      expect(described_class::NAME_SCRIPTS).not_to include(:Greek)
    end

    it 'covers every script code the transformers and models emit' do
      require 'ammitto/sources/au'

      # Transformer literals plus the AU Script detector constants
      transformer_literals = %i[Latn Cyrl Arab Hani Jpan]
      script_module = Ammitto::Sources::Au::Script
      emitted = script_module.constants
                             .map { |c| script_module.const_get(c) }
                             .grep(String)
                             .map(&:to_sym) + transformer_literals

      expect(described_class::NAME_SCRIPTS).to include(*emitted.uniq)
    end
  end

  describe '.valid_script?' do
    it 'rejects the comment token "#"' do
      expect(described_class.valid_script?('#')).to be false
    end

    it 'rejects prose words from former inline comments' do
      expect(described_class.valid_script?('Cyrillic')).to be false
      expect(described_class.valid_script?('Greek')).to be false
    end

    it 'accepts Grek, Jpan, and Kore' do
      expect(described_class.valid_script?('Grek')).to be true
      expect(described_class.valid_script?(:Jpan)).to be true
      expect(described_class.valid_script?('Kore')).to be true
    end
  end

  describe '.valid_entity_type?' do
    it 'returns true for valid types' do
      expect(described_class.valid_entity_type?(:person)).to be true
      expect(described_class.valid_entity_type?('organization')).to be true
    end

    it 'returns false for invalid types' do
      expect(described_class.valid_entity_type?(:invalid)).to be false
    end
  end

  describe '.valid_identification_type?' do
    it 'returns true for valid types' do
      expect(described_class.valid_identification_type?(:passport)).to be true
    end

    it 'returns false for invalid types' do
      expect(described_class.valid_identification_type?(:unknown_type)).to be false
    end
  end

  describe '.normalize_entity_type' do
    it 'normalizes to symbol' do
      expect(described_class.normalize_entity_type('Person')).to eq(:person)
    end

    it 'returns nil for invalid types' do
      expect(described_class.normalize_entity_type('invalid')).to be_nil
    end

    it 'returns nil for nil input' do
      expect(described_class.normalize_entity_type(nil)).to be_nil
    end
  end

  describe '.normalize_identification_type' do
    it 'normalizes passport variations' do
      expect(described_class.normalize_identification_type('Passport')).to eq(:passport)
      expect(described_class.normalize_identification_type('passports')).to eq(:passport)
    end

    it 'normalizes national ID variations' do
      expect(described_class.normalize_identification_type('National ID')).to eq(:national_id)
      expect(described_class.normalize_identification_type('nationalId')).to eq(:national_id)
    end

    it 'returns :other for unknown types' do
      expect(described_class.normalize_identification_type('unknown')).to eq(:other)
    end

    it 'returns :other for nil' do
      expect(described_class.normalize_identification_type(nil)).to eq(:other)
    end
  end

  describe '.detect_script' do
    it 'detects Cyrillic' do
      expect(described_class.detect_script('Иван Иванов')).to eq(:Cyrl)
    end

    it 'detects Greek as the ISO 15924 code Grek' do
      script = described_class.detect_script('Αθήνα')

      expect(script).to eq(:Grek)
      expect(described_class.valid_script?(script)).to be true
    end

    it 'detects Arabic' do
      expect(described_class.detect_script('محمد')).to eq(:Arab)
    end

    it 'detects Han (Chinese)' do
      expect(described_class.detect_script('王明')).to eq(:Hani)
    end

    it 'defaults to Latin' do
      expect(described_class.detect_script('John Smith')).to eq(:Latn)
    end

    it 'returns Latin for nil' do
      expect(described_class.detect_script(nil)).to eq(:Latn)
    end

    it 'returns Latin for empty string' do
      expect(described_class.detect_script('')).to eq(:Latn)
    end
  end

  describe '.normalize_gender' do
    it 'normalizes male variations' do
      expect(described_class.normalize_gender('M')).to eq(:male)
      expect(described_class.normalize_gender('male')).to eq(:male)
      expect(described_class.normalize_gender('MALE')).to eq(:male)
    end

    it 'normalizes female variations' do
      expect(described_class.normalize_gender('F')).to eq(:female)
      expect(described_class.normalize_gender('female')).to eq(:female)
    end

    it 'returns nil for nil input' do
      expect(described_class.normalize_gender(nil)).to be_nil
    end
  end
end
