# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Client::CacheManager do
  describe '.refresh' do
    let(:cache) { instance_double(Ammitto::Client::Cache, exists?: false, write: nil) }
    let(:api_client) { instance_double(Ammitto::Client::ApiClient) }

    before do
      allow(Ammitto::Client::Cache).to receive(:new).and_return(cache)
      allow(Ammitto::Client::ApiClient).to receive(:new).and_return(api_client)
      allow(Ammitto::Logger).to receive(:error)
      allow(described_class).to receive(:save_metadata)
    end

    it 'writes fetched data and reports :refreshed' do
      allow(api_client).to receive(:fetch_source).with(:eu).and_return('data')

      expect(described_class.refresh(sources: [:eu])).to eq(eu: { status: :refreshed, message: 'Cache updated' })
      expect(cache).to have_received(:write).with(:eu, 'data')
    end

    [Ammitto::NetworkError.new('connection refused'), RuntimeError.new('connection refused')].each do |error|
      it "logs and reports :error for #{error.class}" do
        allow(api_client).to receive(:fetch_source).and_raise(error)

        expect(described_class.refresh(sources: [:eu])).to eq(eu: { status: :error, message: 'connection refused' })
        expect(Ammitto::Logger).to have_received(:error).with('Failed to refresh eu: connection refused')
        expect(cache).not_to have_received(:write)
      end
    end
  end
end
