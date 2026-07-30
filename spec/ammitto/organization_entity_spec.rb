# frozen_string_literal: true

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
