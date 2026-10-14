# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology/value_objects/name_variant'

RSpec.describe Ammitto::Ontology::ValueObjects::NameVariant do
  describe '#initialize' do
    it 'creates a name variant with all attributes' do
      name = described_class.new(
        full_name: 'Ivan Ivanov',
        first_name: 'Ivan',
        last_name: 'Ivanov',
        script: 'Latn',
        language: 'en',
        is_primary: true
      )

      expect(name.full_name).to eq('Ivan Ivanov')
      expect(name.first_name).to eq('Ivan')
      expect(name.last_name).to eq('Ivanov')
      expect(name.script).to eq('Latn')
      expect(name.is_primary).to be true
    end

    it 'defaults is_primary to false' do
      name = described_class.new(full_name: 'Test Name')
      expect(name.is_primary).to be false
    end
  end

  describe '#primary?' do
    it 'returns true when is_primary is true' do
      name = described_class.new(full_name: 'Test', is_primary: true)
      expect(name.primary?).to be true
    end

    it 'returns false when is_primary is false' do
      name = described_class.new(full_name: 'Test', is_primary: false)
      expect(name.primary?).to be false
    end
  end

  describe '#non_latin?' do
    it 'returns true for non-Latin scripts' do
      name = described_class.new(full_name: 'Иван', script: 'Cyrl')
      expect(name.non_latin?).to be true
    end

    it 'returns false for Latin script' do
      name = described_class.new(full_name: 'Ivan', script: 'Latn')
      expect(name.non_latin?).to be false
    end
  end

  describe '#display_name' do
    it 'returns full_name when present' do
      name = described_class.new(full_name: 'Ivan Ivanov')
      expect(name.display_name).to eq('Ivan Ivanov')
    end

    it 'constructs name from parts when full_name is nil' do
      name = described_class.new(first_name: 'Ivan', last_name: 'Ivanov')
      expect(name.display_name).to eq('Ivan Ivanov')
    end
  end

  describe '#to_hash' do
    it 'converts to hash for JSON-LD' do
      name = described_class.new(
        full_name: 'Ivan Ivanov',
        first_name: 'Ivan',
        script: 'Latn',
        is_primary: true
      )
      hash = name.to_hash

      expect(hash[:full_name]).to eq('Ivan Ivanov')
      expect(hash[:first_name]).to eq('Ivan')
      expect(hash[:script]).to eq('Latn')
      expect(hash[:is_primary]).to be true
    end
  end

  describe '#with' do
    it 'returns a sealed replacement and retains the original value' do
      original = described_class.new(full_name: 'Before')
      replacement = original.with(full_name: 'After')

      expect(replacement).to be_frozen
      expect(replacement.full_name).to eq('After')
      expect(original.full_name).to eq('Before')
      expect(original).to be_frozen
    end
  end

  describe '#with_detected_script' do
    it 'returns a Cyrillic replacement without mutating the original' do
      original = described_class.new(full_name: 'Иван', script: 'Latn')
      replacement = original.with_detected_script

      expect(replacement.script).to eq('Cyrl')
      expect(replacement).to be_frozen
      expect(original.script).to eq('Latn')
      expect { original.detect_script! }.to raise_error(FrozenError)
    end
  end

  [nil, false, true].each do |flag|
    it "preserves is_strong #{flag.inspect} through every existing export" do
      value = described_class.new(full_name: 'Metadata', is_strong: flag)
      expect(described_class.from_json(value.to_json).is_strong).to eq(flag)
      expect(described_class.from_yaml(value.to_yaml).is_strong).to eq(flag)
      expect(value.to_hash.key?(:is_strong)).to eq(!flag.nil?)
      expect(value.to_neo4j_properties.key?(:is_strong)).to eq(!flag.nil?)
      expect(value.to_hash[:is_strong]).to eq(flag)
      expect(described_class.from_neo4j_record(value.to_neo4j_properties.transform_keys(&:to_s)).is_strong).to eq(flag)
    end
  end
end
