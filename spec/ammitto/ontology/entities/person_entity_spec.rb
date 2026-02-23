# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/ontology/entities/person_entity'
require 'ammitto/ontology/value_objects/name_variant'
require 'ammitto/ontology/value_objects/birth_info'

RSpec.describe Ammitto::Ontology::Entities::PersonEntity do
  describe '#initialize' do
    it 'creates a person entity with required attributes' do
      person = described_class.new(
        id: 'https://www.ammitto.org/entity/eu/EU.123.45',
        names: [
          Ammitto::Ontology::ValueObjects::NameVariant.new(
            full_name: 'Ivan Ivanov',
            is_primary: true
          )
        ]
      )

      expect(person.id).to eq('https://www.ammitto.org/entity/eu/EU.123.45')
      expect(person.entity_type).to eq('person')
      expect(person.names).to have_attributes(size: 1)
    end

    it 'sets entity_type to person automatically' do
      person = described_class.new(id: 'https://test.org/1')
      expect(person.entity_type).to eq('person')
    end
  end

  describe '#primary_name' do
    it 'returns the primary name' do
      person = described_class.new(
        id: 'https://test.org/1',
        names: [
          Ammitto::Ontology::ValueObjects::NameVariant.new(full_name: 'Primary', is_primary: true),
          Ammitto::Ontology::ValueObjects::NameVariant.new(full_name: 'Secondary', is_primary: false)
        ]
      )

      expect(person.primary_name).to eq('Primary')
    end

    it 'returns first name when no primary is marked' do
      person = described_class.new(
        id: 'https://test.org/1',
        names: [
          Ammitto::Ontology::ValueObjects::NameVariant.new(full_name: 'First'),
          Ammitto::Ontology::ValueObjects::NameVariant.new(full_name: 'Second')
        ]
      )

      expect(person.primary_name).to eq('First')
    end
  end

  describe '#all_names' do
    it 'returns all name variants' do
      person = described_class.new(
        id: 'https://test.org/1',
        names: [
          Ammitto::Ontology::ValueObjects::NameVariant.new(full_name: 'Name 1'),
          Ammitto::Ontology::ValueObjects::NameVariant.new(full_name: 'Name 2')
        ]
      )

      expect(person.all_names).to contain_exactly('Name 1', 'Name 2')
    end
  end

  describe '#person?' do
    it 'returns true' do
      person = described_class.new(id: 'https://test.org/1')
      expect(person.person?).to be true
    end
  end

  describe '#organization?' do
    it 'returns false' do
      person = described_class.new(id: 'https://test.org/1')
      expect(person.organization?).to be false
    end
  end

  describe '#to_hash' do
    it 'includes all non-nil attributes' do
      person = described_class.new(
        id: 'https://test.org/1',
        names: [
          Ammitto::Ontology::ValueObjects::NameVariant.new(full_name: 'Test Person')
        ],
        gender: 'male',
        nationalities: ['RU']
      )
      hash = person.to_hash

      expect(hash[:id]).to eq('https://test.org/1')
      expect(hash[:entity_type]).to eq('person')
      expect(hash[:gender]).to eq('male')
      expect(hash[:nationalities]).to eq(['RU'])
      expect(hash[:names]).to be_an(Array)
    end
  end
end
