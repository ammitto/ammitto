# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/un_vessels/vessel'

# Named `_identifier_spec` rather than `vessel_spec` because this class's
# PDF-parsing behaviour already has its own spec at
# spec/ammitto/sources/un_vessels/sanctions_list_spec.rb.
RSpec.describe Ammitto::Sources::UnVessels::Vessel do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it. local_id, not unique_identifier: see the comment on
  # #identifier for why the constant "IMO-" ref must never be minted.
  describe '#identifier' do
    it 'is local_id when the vessel has an IMO number' do
      vessel = described_class.new(imo_number: '9999999')

      expect(vessel.identifier).to eq('9999999')
    end

    it 'falls back to a slugged vessel name when there is no IMO number' do
      vessel = described_class.new(
        imo_number: nil,
        names: [Ammitto::Sources::UnVessels::NameVariant.new(full_name: 'Min Ning De You 078', is_primary: true)]
      )

      expect(vessel.identifier).to eq('min-ning-de-you-078')
    end

    it 'is nil when the vessel has neither an IMO number nor a name' do
      vessel = described_class.new(imo_number: nil, names: [])

      expect(vessel.identifier).to be_nil
    end
  end
end
