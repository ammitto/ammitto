# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/nz/entity'

RSpec.describe Ammitto::Sources::Nz::Entity do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it. reference_number is defined above as an alias of
  # unique_identifier, so the two candidates always agree; the fallback
  # is exercised anyway for parity with Individual and Ship.
  describe '#identifier' do
    it 'is unique_identifier when present' do
      entity = described_class.new(unique_identifier: 'NZ 34')

      expect(entity.identifier).to eq('NZ 34')
    end

    it 'is nil when unique_identifier is blank' do
      entity = described_class.new(unique_identifier: nil)

      expect(entity.identifier).to be_nil
    end
  end
end
