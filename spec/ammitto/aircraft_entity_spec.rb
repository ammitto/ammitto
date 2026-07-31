# frozen_string_literal: true

RSpec.describe Ammitto::AircraftEntity do
  let(:name) do
    Ammitto::NameVariant.new(
      full_name: 'RA-12345',
      is_primary: true
    )
  end

  subject do
    described_class.new(
      id: 'https://ammitto.org/entity/aircraft-1',
      names: [name],
      serial_number: '12345ABC',
      registration_number: 'RA-12345',
      manufacturer: 'Boeing',
      model: '737-800',
      flag_state: 'Russia'
    )
  end

  it 'has correct entity type' do
    expect(subject.entity_type).to eq('aircraft')
  end

  it 'returns display name' do
    expect(subject.display_name).to eq('RA-12345')
  end

  it 'matches search term in registration number' do
    expect(subject.matches?('RA-12345')).to be true
  end

  it 'matches search term in manufacturer' do
    expect(subject.matches?('Boeing')).to be true
  end
end
