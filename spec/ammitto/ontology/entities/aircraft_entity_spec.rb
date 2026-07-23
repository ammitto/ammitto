# frozen_string_literal: true

require 'ammitto'
require 'ammitto/ontology'

RSpec.describe Ammitto::Ontology::Entities::AircraftEntity do
  it 'is an aircraft by construction' do
    expect(described_class.new).to be_aircraft
  end

  describe '#primary_name / #all_names' do
    it 'uses the name plus previous names' do
      aircraft = described_class.new(name: 'N12345', previous_names: ['EX-111'])
      expect(aircraft.primary_name).to eq('N12345')
      expect(aircraft.all_names).to include('N12345', 'EX-111')
    end
  end

  describe '#to_hash' do
    it 'includes identifying fields and omits nils' do
      aircraft = described_class.new(serial_number: 'SN-1', manufacturer: 'Ilyushin')
      hash = aircraft.to_hash
      expect(hash[:serial_number]).to eq('SN-1')
      expect(hash[:manufacturer]).to eq('Ilyushin')
      expect(hash).not_to have_key(:operator)
    end
  end
end
