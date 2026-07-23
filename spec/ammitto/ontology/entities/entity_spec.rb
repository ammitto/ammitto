# frozen_string_literal: true

require 'ammitto'
require 'ammitto/ontology'

RSpec.describe Ammitto::Ontology::Entities::Entity do
  describe 'type predicates' do
    it 'reflects entity_type exactly' do
      expect(described_class.new(entity_type: 'person')).to be_person
      expect(described_class.new(entity_type: 'organization')).to be_organization
      expect(described_class.new(entity_type: 'vessel')).to be_vessel
      expect(described_class.new(entity_type: 'aircraft')).to be_aircraft
    end

    it 'is nothing in particular without a type' do
      entity = described_class.new
      expect(entity).not_to be_person
      expect(entity.entity_type_sym).to be_nil
    end
  end

  describe '#add_sanction_entry' do
    it 'accumulates entries' do
      entity = described_class.new(id: 'x')
      entity.add_sanction_entry(:entry_one)
      entity.add_sanction_entry(:entry_two)
      expect(entity.sanction_entries).to eq(%i[entry_one entry_two])
    end
  end

  describe '#primary_name' do
    it 'is nil on the abstract base (subclasses override)' do
      expect(described_class.new.primary_name).to be_nil
    end
  end
end
