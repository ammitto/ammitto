# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/wb/sanctioned_firm'

RSpec.describe Ammitto::Sources::Wb::SanctionedFirm do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is supp_id when present' do
      expect(described_class.new(supp_id: 777).identifier).to eq(777)
    end

    it 'is nil when supp_id is blank' do
      expect(described_class.new(supp_id: nil).identifier).to be_nil
    end
  end
end
