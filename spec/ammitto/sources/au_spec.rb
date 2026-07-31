# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au do
  describe '.parse_base_reference' do
    it 'extracts base reference from plain number' do
      expect(described_class::BaseEntity.parse_base_reference('8577')).to eq('8577')
    end

    it 'extracts base reference with single letter suffix' do
      expect(described_class::BaseEntity.parse_base_reference('8577a')).to eq('8577')
    end

    it 'extracts base reference with multiple letter suffix' do
      expect(described_class::BaseEntity.parse_base_reference('8577bcd')).to eq('8577')
    end
  end
end
