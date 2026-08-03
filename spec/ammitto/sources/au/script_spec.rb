# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au::Script do
  describe '.detect' do
    it 'detects Latin script' do
      expect(described_class.detect('Mohammad Salah JOKAR')).to eq('Latn')
    end

    it 'detects Arabic script' do
      expect(described_class.detect('محمد صالح جوکار')).to eq('Arab')
    end

    it 'detects Cyrillic script' do
      expect(described_class.detect('Владимир ПУТИН')).to eq('Cyrl')
    end

    it 'detects Chinese script' do
      expect(described_class.detect('习近平')).to eq('Hani')
    end

    it 'returns Latn for empty string' do
      expect(described_class.detect('')).to eq('Latn')
    end

    it 'returns Latn for nil' do
      expect(described_class.detect(nil)).to eq('Latn')
    end
  end
end
