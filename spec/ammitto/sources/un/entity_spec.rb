# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/un/entity'

RSpec.describe Ammitto::Sources::Un::Entity do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is reference_number when present' do
      expect(described_class.new(reference_number: 'QDe.001').identifier)
        .to eq('QDe.001')
    end

    it 'is nil when reference_number is blank' do
      expect(described_class.new(reference_number: nil).identifier).to be_nil
    end
  end
end
