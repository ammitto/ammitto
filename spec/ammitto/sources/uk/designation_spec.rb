# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/uk/designation'

RSpec.describe Ammitto::Sources::Uk::Designation do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is unique_id when present' do
      expect(described_class.new(unique_id: 'GBR-0123').identifier)
        .to eq('GBR-0123')
    end

    it 'is nil when unique_id is blank' do
      expect(described_class.new(unique_id: nil).identifier).to be_nil
    end

    it 'treats whitespace as absent, not as an identifier' do
      expect(described_class.new(unique_id: '   ').identifier).to be_nil
    end
  end
end
