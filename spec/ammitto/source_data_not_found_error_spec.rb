# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::SourceDataNotFoundError do
  let(:source) { Class.new(Ammitto::BaseSource) { def code = :tr }.new }
  let(:cache_dir) { Dir.mktmpdir('ammitto-not-found') }

  before { allow(Ammitto.configuration).to receive(:cache_dir).and_return(cache_dir) }
  after { FileUtils.remove_entry(cache_dir) }

  it 'is raised for a 404 and names the source and URL' do
    stub_request(:get, source.api_endpoint).to_return(status: 404)

    expect { source.download_to_cache }
      .to raise_error(described_class, "No tr data is published at #{source.api_endpoint} (HTTP 404)") { |e|
        expect([e.status_code, e.url]).to eq([404, source.api_endpoint])
      }
  end

  it 'asks the server again on the next load rather than remembering the 404' do
    stub_request(:get, source.api_endpoint).to_return(status: 404)

    2.times { expect { source.load_data }.to raise_error(described_class) }
    expect(a_request(:get, source.api_endpoint)).to have_been_made.twice
  end

  it 'is raised by ApiClient#fetch_source for a 404 too' do
    url = "#{Ammitto.configuration.api_base_url}/sources/tr.jsonld"
    stub_request(:get, url).to_return(status: 404)

    expect { Ammitto::Client::ApiClient.new.fetch_source(:tr) }
      .to raise_error(described_class, "No tr data is published at #{url} (HTTP 404)")
  end

  it 'leaves other failed statuses as a plain NetworkError' do
    stub_request(:get, source.api_endpoint).to_return(status: 503)

    expect { source.download_to_cache }.to raise_error(Ammitto::NetworkError) { |e|
      expect([e.class, e.status_code]).to eq([Ammitto::NetworkError, 503])
    }
  end

  it 'lets a search skip the source and record it' do
    stub_request(:get, source.api_endpoint).to_return(status: 404)
    allow(Ammitto::Registry).to receive(:instance).and_call_original
    allow(Ammitto::Registry).to receive(:instance).with(:tr).and_return(source)

    results = Ammitto.search('match', sources: %i[tr])

    expect(results.skipped_sources).to eq([:tr])
  end
end
