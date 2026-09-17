# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/nz/ship'

RSpec.describe Ammitto::Sources::Nz::Ship do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it.
  #
  # The task this spec was written for described a suspected latent bug:
  # that Ship might not define reference_number at all, so the old
  # `[item.unique_identifier, item.reference_number]` candidate list would
  # raise NoMethodError rather than return nil for a real Ship with a
  # blank unique_identifier. Reading this file shows that is NOT the
  # case on this branch — Ship defines reference_number as an alias of
  # unique_identifier, same as Individual and Entity — so there is no
  # live bug to fix here. This spec exists anyway, to lock in that Ship
  # answers #identifier the same way its siblings do and never raises,
  # and to catch it if reference_number is ever removed from this file
  # without reference_number's caller here being updated to match.
  describe '#identifier' do
    it 'is unique_identifier when present' do
      ship = described_class.new(unique_identifier: 'NZ-SHIP-1')

      expect(ship.identifier).to eq('NZ-SHIP-1')
    end

    it 'returns nil rather than raising when unique_identifier is blank' do
      ship = described_class.new(unique_identifier: nil)

      expect { ship.identifier }.not_to raise_error
      expect(ship.identifier).to be_nil
    end
  end
end
