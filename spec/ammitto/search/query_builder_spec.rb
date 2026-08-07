# frozen_string_literal: true

require 'ammitto'

# The registry knows every source the gem has ever shipped; the
# published API only carries the currently built ones, so a client's
# default all-sources search always meets sources whose download 404s.
# One unavailable source must not take the whole search down.
RSpec.describe Ammitto::Search::QueryBuilder do
  describe '#execute' do
    let(:row) do
      {
        '@id' => 'https://www.ammitto.org/entity/au/100',
        'entityType' => 'person',
        'names' => [{ 'fullName' => 'Nazir Mohammad Abdul Basir',
                      'isPrimary' => true }]
      }
    end

    let(:live_source) do
      instance_double(Ammitto::BaseSource).tap do |source|
        allow(source).to receive(:load_data)
          .and_return('@graph' => [row])
        allow(source).to receive(:search)
          .with('basir', '@graph' => [row]).and_return([row])
      end
    end

    let(:dead_source) do
      instance_double(Ammitto::BaseSource).tap do |source|
        allow(source).to receive(:load_data).and_raise(
          Ammitto::NetworkError.new('Failed to download ca data',
                                    status_code: 404)
        )
      end
    end

    before do
      allow(Ammitto::Registry).to receive(:registered?).and_return(true)
      allow(Ammitto::Registry).to receive(:instance)
        .with(:ca).and_return(dead_source)
      allow(Ammitto::Registry).to receive(:instance)
        .with(:au).and_return(live_source)
    end

    it 'skips a source whose download fails and keeps the published ones' do
      results = described_class.new('basir', sources: %i[ca au]).execute

      expect(results).to eq([row])
    end

    it 'says which source it skipped rather than skipping silently' do
      allow(Ammitto::Logger).to receive(:warn)

      described_class.new('basir', sources: %i[ca au]).execute

      expect(Ammitto::Logger).to have_received(:warn)
        .with(/ca.*Failed to download ca data/)
    end

    it 'returns [] when every source is unavailable' do
      results = described_class.new('basir', sources: [:ca]).execute

      expect(results).to eq([])
    end
  end
end
