# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au::Location do
  describe '.parse' do
    it 'parses "Yazd, Iran"' do
      loc = described_class.parse('Yazd, Iran')
      expect(loc.city).to eq('Yazd')
      expect(loc.country).to eq('Iran')
    end

    it 'parses single location "Iran"' do
      loc = described_class.parse('Iran')
      expect(loc.country).to eq('Iran')
    end
  end
end
