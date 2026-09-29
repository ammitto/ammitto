# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/un_vessels/vessel'

RSpec.describe Ammitto::Sources::UnVessels::Vessel do
  describe '.parse_date' do
    it 'parses a well-formed date' do
      expect(described_class.parse_date('2019-03-30')).to eq(Date.new(2019, 3, 30))
    end
  end

  # An unreadable designation_date publishes as nil in every mode;
  # visibility only adds the report.
  describe 'parse failure visibility' do
    include_context 'with parse failure log capture'

    let(:parse_unreadable) { -> { described_class.parse_date('not-a-date') } }
    let(:raise_unreadable) { parse_unreadable }

    it_behaves_like 'a reported parse failure', source: :un_vessels, field: :designation_date
  end
end
