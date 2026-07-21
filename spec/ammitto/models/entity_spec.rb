# frozen_string_literal: true

RSpec.describe Ammitto::PersonEntity do
  let(:name) do
    Ammitto::NameVariant.new(
      full_name: 'John Doe',
      first_name: 'John',
      last_name: 'Doe',
      is_primary: true
    )
  end

  let(:birth_info) do
    Ammitto::BirthInfo.new(
      date: '1980-01-15',
      city: 'New York',
      country: 'United States'
    )
  end

  subject do
    described_class.new(
      id: 'https://ammitto.org/entity/test-1',
      names: [name],
      birth_info: [birth_info],
      nationalities: ['United States'],
      gender: 'Male'
    )
  end

  it 'has correct entity type' do
    expect(subject.entity_type).to eq('person')
  end

  it 'returns primary name' do
    expect(subject.primary_name).to eq(name)
  end

  it 'returns display name' do
    expect(subject.display_name).to eq('John Doe')
  end

  it 'returns birth date' do
    expect(subject.birth_date).to eq(Date.new(1980, 1, 15))
  end

  it 'returns birth country' do
    expect(subject.birth_country).to eq('United States')
  end

  it 'matches search term in names' do
    expect(subject.matches?('John')).to be true
    expect(subject.matches?('Doe')).to be true
  end

  it 'matches search term in nationalities' do
    expect(subject.matches?('United')).to be true
  end

  it 'does not match unrelated search term' do
    expect(subject.matches?('XYZ123')).to be false
  end
end

RSpec.describe Ammitto::OrganizationEntity do
  let(:name) do
    Ammitto::NameVariant.new(
      full_name: 'ACME Corporation',
      is_primary: true
    )
  end

  subject do
    described_class.new(
      id: 'https://ammitto.org/entity/org-1',
      names: [name],
      registration_number: '12345678',
      country: 'United States',
      sector: 'Technology'
    )
  end

  it 'has correct entity type' do
    expect(subject.entity_type).to eq('organization')
  end

  it 'returns display name' do
    expect(subject.display_name).to eq('ACME Corporation')
  end

  it 'matches search term in name' do
    expect(subject.matches?('ACME')).to be true
  end

  it 'matches search term in country' do
    expect(subject.matches?('United')).to be true
  end

  it 'matches search term in registration number' do
    expect(subject.matches?('12345')).to be true
  end
end

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
