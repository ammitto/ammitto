# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/eu_vessels/vessel'

RSpec.describe Ammitto::Sources::EuVessels::Vessel do
  describe '#identifier' do
    it 'is imo_number when present' do
      vessel = described_class.new(imo_number: '9999999')

      expect(vessel.identifier).to eq('9999999')
    end

    it 'is a slug of the name when there is no IMO number' do
      vessel = described_class.new(imo_number: nil, vessel_name: 'MIN NING DE YOU 078')

      expect(vessel.identifier).to eq('min-ning-de-you-078')
    end

    it 'is nil when there is neither' do
      expect(described_class.new(imo_number: nil).identifier).to be_nil
    end
  end

  it 'round-trips its designations through the fetch YAML' do
    vessel = described_class.new(
      vessel_name: 'Alpha', imo_number: '9000001',
      designations: [Ammitto::Sources::EuVessels::Designation.new(
        date_of_application: Date.new(2025, 5, 20), subject_to: 'Article 3s (Council Regulation 833/2014)'
      )]
    )

    copy = described_class.from_hash(YAML.safe_load(vessel.to_yaml))

    expect(copy.designations.map { |d| [d.date_of_application, d.subject_to] })
      .to eq([[Date.new(2025, 5, 20), 'Article 3s (Council Regulation 833/2014)']])
  end
end
