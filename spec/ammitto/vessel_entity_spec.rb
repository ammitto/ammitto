# frozen_string_literal: true

RSpec.describe Ammitto::VesselEntity do
  let(:name) do
    Ammitto::NameVariant.new(
      full_name: 'MV Pacific Star',
      is_primary: true
    )
  end

  subject do
    described_class.new(
      id: 'https://ammitto.org/entity/vessel-1',
      names: [name],
      imo_number: '1234567',
      flag_state: 'Panama',
      vessel_type: 'Cargo'
    )
  end

  it 'has correct entity type' do
    expect(subject.entity_type).to eq('vessel')
  end

  it 'returns display name' do
    expect(subject.display_name).to eq('MV Pacific Star')
  end

  it 'matches search term in name' do
    expect(subject.matches?('Pacific')).to be true
  end

  it 'matches search term in IMO number' do
    expect(subject.matches?('1234567')).to be true
  end

  it 'matches search term in flag state' do
    expect(subject.matches?('Panama')).to be true
  end
end
