# frozen_string_literal: true

require 'tmpdir'
require 'ammitto'

# The default API host is a correctness constraint, not a preference.
#
# Nothing in the gem follows redirects. `Ammitto::BaseSource#download_to_cache`
# calls `Faraday.get` directly and `Client::ApiClient` builds a Faraday
# connection with an empty middleware stack, so a 3xx is simply not
# `success?` and the fetch raises. The default used to be
# `https://ammitto.org/api/v1`, which answers 301 to the www host, so
# every client call failed: `Ammitto.search` logged "Failed to download
# <code> data" for all fifteen sources and returned an empty ResultSet —
# indistinguishable, to a caller, from "nothing matched".
#
# `Ammitto.search` reaches the network through `BaseSource`, NOT through
# `ApiClient` (which serves `refresh_cache`). Both are pinned below,
# because both build their URL from `api_base_url` and both would break
# again if the default named a redirecting host.
#
# These examples stub the transport rather than reaching the network, so
# they pin the LOGIC — a redirect is a failure — and the default that
# logic forces. Whether the live host still answers 200 is not proved
# here.
RSpec.describe 'the API host the gem fetches from' do
  let(:redirect) do
    instance_double(
      Faraday::Response,
      success?: false,
      status: 301,
      headers: { 'location' => 'https://www.ammitto.org/api/v1/sources/tr.jsonld' }
    )
  end

  describe Ammitto::BaseSource do
    subject(:source) do
      Class.new(described_class) { def code = :tr }.new
    end

    it 'builds its endpoint from the configured base URL' do
      expect(source.api_endpoint)
        .to eq('https://www.ammitto.org/api/v1/sources/tr.jsonld')
    end

    it 'fails on a redirect instead of following it' do
      # This is the path `Ammitto.search` takes. Left unpinned, the bug
      # returns as an empty result set rather than an error.
      allow(Faraday).to receive(:get).and_return(redirect)

      Dir.mktmpdir do |dir|
        allow(Ammitto.configuration).to receive(:cache_dir).and_return(dir)
        expect { source.download_to_cache }
          .to raise_error(Ammitto::NetworkError, /Failed to download tr data/)
      end
    end
  end

  describe Ammitto::Client::ApiClient do
    it 'fails on a redirect instead of following it' do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get(//) { [301, {}, ''] }
      client = described_class.new
      client.instance_variable_set(
        :@connection, Faraday.new { |f| f.adapter :test, stubs }
      )

      expect { client.fetch_source(:tr) }
        .to raise_error(Ammitto::NetworkError, /Failed to fetch tr/)
    end
  end

  it 'defaults to a host that answers without redirecting' do
    # ammitto.org 301s to www.ammitto.org. Naming the apex host here
    # breaks every fetch in the gem, on both paths above.
    expect(Ammitto::Config::Defaults::API_BASE_URL)
      .to eq('https://www.ammitto.org/api/v1')
    expect(Ammitto.configuration.api_base_url)
      .to eq('https://www.ammitto.org/api/v1')
  end
end
