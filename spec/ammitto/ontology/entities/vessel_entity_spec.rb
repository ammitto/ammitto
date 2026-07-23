# frozen_string_literal: true

require 'ammitto'
require 'ammitto/ontology'

RSpec.describe Ammitto::Ontology::Entities::VesselEntity do
  describe '#has_imo?' do
    it 'accepts exactly seven digits' do
      expect(described_class.new(imo_number: '9195949')).to have_imo
      expect(described_class.new(imo_number: 'IMO 9195949')).not_to have_imo
      expect(described_class.new(imo_number: '123')).not_to have_imo
      expect(described_class.new).not_to have_imo
    end
  end

  describe '#info_summary' do
    it 'joins name, IMO, and flag with slashes, skipping nils' do
      vessel = described_class.new(name: 'SHIP X', imo_number: '9195949', flag_state: 'Panama')
      expect(vessel.info_summary).to eq('SHIP X / 9195949 / Panama')
      expect(described_class.new(name: 'SHIP X').info_summary).to eq('SHIP X')
    end
  end

  describe 'tonnage fallbacks' do
    it 'prefers the Tonnage object over flat integers' do
      tonnage = Ammitto::Ontology::ValueObjects::Tonnage.new(gt: 500, dwt: 700)
      vessel = described_class.new(tonnage: tonnage, gross_tonnage: 100, deadweight: 200)
      expect(vessel.gross_tonnage_value).to eq(500)
      expect(vessel.deadweight_value).to eq(700)
    end

    it 'falls back to the flat integers' do
      vessel = described_class.new(gross_tonnage: 100, deadweight: 200)
      expect(vessel.gross_tonnage_value).to eq(100)
      expect(vessel.deadweight_value).to eq(200)
    end
  end

  it 'is a vessel by construction and names itself' do
    vessel = described_class.new(name: 'SHIP X')
    expect(vessel).to be_vessel
    expect(vessel.primary_name).to eq('SHIP X')
  end
end
