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

  describe '#birth_country with independent birth records' do
    it 'finds the country after date-only records' do
      subject.birth_info = [Ammitto::BirthInfo.new(year: 1980), birth_info]
      expect(subject.birth_country).to eq('United States')
    end

    it 'skips nil and blank country records' do
      subject.birth_info = [nil, Ammitto::BirthInfo.new(country: '  '), birth_info]
      expect(subject.birth_country).to eq('United States')
    end

    it 'retains the first stated country' do
      subject.birth_info = [birth_info, Ammitto::BirthInfo.new(country: 'Canada')]
      expect(subject.birth_country).to eq('United States')
    end

    it 'returns nil when no country is stated' do
      subject.birth_info = [nil, Ammitto::BirthInfo.new(year: 1980)]
      expect(subject.birth_country).to be_nil
    end
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
