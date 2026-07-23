# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::Sanction::SanctionReason do
  describe '#present?' do
    it 'requires a non-blank category or description' do
      expect(described_class.new(category: 'terrorism')).to be_present
      expect(described_class.new(description: 'financing')).to be_present
    end

    it 'is blank when both are empty or whitespace-only' do
      expect(described_class.new).not_to be_present
      expect(described_class.new(category: ' ', description: '')).not_to be_present
    end
  end
end
