# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/eu_vessels/vessel'

RSpec.describe Ammitto::Sources::EuVessels::Vessel do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it. unique_identifier is "IMO-#{imo_number}", so it is
  # never blank even when imo_number is nil ("IMO-"); imo_number itself
  # is therefore always the value that actually wins in practice.
  describe '#identifier' do
    it 'is imo_number when present' do
      vessel = described_class.new(imo_number: '9999999')

      expect(vessel.identifier).to eq('9999999')
    end

    it 'falls through to unique_identifier when imo_number is blank' do
      vessel = described_class.new(imo_number: nil)

      expect(vessel.identifier).to eq('IMO-')
    end
  end
end
