# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Uk::SanctionsIndicators do
  it 'reads ProhibitionOfPortEntry, the element OFSI publishes' do
    indicators = UkExcerpt.designation('DPR0075').sanctions_imposed_indicators

    expect(indicators.prohibition_of_port_entry).to be(true)
    expect(indicators.active_indicators).to eq([:prohibition_of_port_entry])
  end
end
