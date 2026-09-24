# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/us/sdn_entry'

RSpec.describe Ammitto::Sources::Us::SdnEntry do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is uid when present' do
      expect(described_class.new(uid: '12345').identifier).to eq('12345')
    end

    it 'is nil when uid is blank' do
      expect(described_class.new(uid: nil).identifier).to be_nil
    end
  end
end
