# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/eu_vessels/transformer'
require 'ammitto/sources/eu_vessels/vessel'
require 'ammitto/sources/un_vessels/transformer'
require 'ammitto/sources/un_vessels/vessel'

RSpec.describe 'Vessel sources list identity' do
  it 'writes the vessel list into eu_vessels entry IRIs' do
    vessel = Ammitto::Sources::EuVessels::Vessel.new(
      vessel_name: 'Test Vessel', imo_number: '9111111'
    )

    entry = Ammitto::Sources::EuVessels::Transformer.new
                                                    .transform(vessel)[:entry]

    expect(entry.id)
      .to include('/entry/eu_vessels/vessel-sanctions-list/')
    expect(entry.id).not_to include('/unknown')
  end

  it 'writes the vessel list into un_vessels entry IRIs' do
    vessel = Ammitto::Sources::UnVessels::Vessel.new(imo_number: '9222222')

    entry = Ammitto::Sources::UnVessels::Transformer.new
                                                    .transform(vessel)[:entry]

    expect(entry.id)
      .to include('/entry/un_vessels/vessel-sanctions-list/')
    expect(entry.id).not_to include('/unknown')
  end
end
