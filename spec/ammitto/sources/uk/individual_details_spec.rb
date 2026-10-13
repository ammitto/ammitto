# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Uk::IndividualDetails do
  let(:details) { UkExcerpt.designation('AFG0006').individual_details }

  it 'reads the blocks nested under <Individual>' do
    expect(details.dobs.size).to eq(10)
    expect(details.nationalities).to eq(['Afghanistan'])
    expect(details.positions.size).to eq(4)
    expect(details.birth_details.primary_location.country_of_birth)
      .to eq('Afghanistan')
  end

  it 'reads passports with their additional information' do
    expect(details.passports.map(&:number).uniq).to eq(['P04581926'])
    expect(details.passports.first.additional_information)
      .to include('issued in Kandahar')
  end

  it 'survives the round trip the harmonize step makes' do
    designation = UkExcerpt.designation('AFG0006')
    copy = Ammitto::Sources::Uk::Designation.from_hash(
      YAML.safe_load(designation.to_yaml)
    )

    expect(copy.individual_details.nationalities).to eq(['Afghanistan'])
    expect(copy.individual_details.passports.size).to eq(10)
    expect(copy.titles).to eq(%w[Mullah Haji])
  end
end
