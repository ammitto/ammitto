# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/extractors/ch_extractor'

RSpec.describe Ammitto::Extractors::ChExtractor do
  subject(:extractor) { described_class.new }

  describe '#fetch' do
    # A data-ch checkout beside the gem holds an old reference-docs
    # snapshot. Fetch must still return the live list, or a prune run
    # deletes every record listed since that snapshot.
    it 'downloads the live list even when a reference-docs snapshot exists' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(a_string_including('reference-docs')).and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(a_string_including('reference-docs')).and_return('<snapshot/>')
      allow(Ammitto::Extractors::HttpClient).to receive(:get).and_return('<live/>')

      expect(extractor.fetch).to eq('<live/>')
    end
  end
end
