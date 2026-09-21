# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/nz/individual'

RSpec.describe Ammitto::Sources::Nz::Individual do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it. reference_number is defined above as an alias of
  # unique_identifier, so the two candidates always agree; the fallback
  # is exercised anyway for parity with Entity and Ship.
  describe '#identifier' do
    it 'is unique_identifier when present' do
      individual = described_class.new(unique_identifier: 'NZ 12')

      expect(individual.identifier).to eq('NZ 12')
    end

    it 'is nil when unique_identifier is blank' do
      individual = described_class.new(unique_identifier: nil)

      expect(individual.identifier).to be_nil
    end
  end
end
