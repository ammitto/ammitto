# frozen_string_literal: true

require 'tmpdir'
require 'ammitto'

# The default API host is a correctness constraint, not a preference.
#
# Source downloads do not follow redirects. Bulk release downloads have their
# own bounded redirect handling. `Ammitto::BaseSource#download_to_cache`
# downloads through `Client::ApiClient`'s connection, which has an empty
# middleware stack, so a 3xx is simply not
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
  include ApiClientConnectionStub

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
      stub_api_client_get.and_return(redirect)

      Dir.mktmpdir do |dir|
        allow(Ammitto.configuration).to receive(:cache_dir).and_return(dir)
        expect { source.download_to_cache }
          .to raise_error(Ammitto::NetworkError, /Failed to download tr data/)
      end
    end
  end

  describe Ammitto::Client::ApiClient do
    describe '#fetch_all' do
      let(:client) { described_class.new }
      let(:base) { 'https://www.ammitto.org/api/v1' }
      let(:release_url) { "https://github.com/ammitto/data/releases/download/api-v1-#{'a' * 40}/all.jsonld" }
      let(:asset_url) { 'https://release-assets.githubusercontent.com/github-production-release-asset/test?signature=example' }

      def data
        { '@graph' => [{ '@id' => 'test:entity' }] }
      end

      def catalogue_response(url)
        { entries: [{ name: 'all.jsonld', url: url }] }.to_json
      end

      it 'discovers and follows a pinned release asset redirect' do
        stub_request(:get, "#{base}/index.jsonld").to_return(body: catalogue_response(release_url))
        stub_request(:get, release_url).to_return(status: 302, headers: { location: asset_url })
        stub_request(:get, asset_url).to_return(body: data.to_json)

        expect(client.fetch_all).to eq(data)
        expect(a_request(:get, "#{base}/all.jsonld")).not_to have_been_made
      end

      it 'keeps existing relative local catalogue URLs working' do
        stub_request(:get, "#{base}/index.jsonld").to_return(body: catalogue_response('all.jsonld'))
        stub_request(:get, "#{base}/all.jsonld").to_return(body: data.to_json)

        expect(client.fetch_all).to eq(data)
      end

      it 'preserves a custom base path with a trailing slash' do
        allow(Ammitto.configuration).to receive(:api_base_url).and_return('http://localhost:9000/custom/api/')
        stub_request(:get, 'http://localhost:9000/custom/api/index.jsonld')
          .to_return(body: catalogue_response('all.jsonld'))
        stub_request(:get, 'http://localhost:9000/custom/api/all.jsonld').to_return(body: data.to_json)

        expect(client.fetch_all).to eq(data)
      end

      it 'falls back for an older host with no catalogue' do
        stub_request(:get, "#{base}/index.jsonld").to_return(status: 404)
        stub_request(:get, "#{base}/all.jsonld").to_return(body: data.to_json)

        expect(client.fetch_all).to eq(data)
      end

      it 'does not fall back when the catalogue is unavailable' do
        stub_request(:get, "#{base}/index.jsonld").to_return(status: 503)

        expect { client.fetch_all }.to raise_error(Ammitto::NetworkError) { |error|
          expect(error.status_code).to eq(503)
          expect(error.url).to eq("#{base}/index.jsonld")
        }
        expect(a_request(:get, "#{base}/all.jsonld")).not_to have_been_made
      end

      ['not json', '[]', '{"entries":[]}', '{"entries":[{"name":"all.jsonld","url":3}]}'].each do |body|
        it "rejects a malformed catalogue: #{body}" do
          stub_request(:get, "#{base}/index.jsonld").to_return(body: body)

          expect { client.fetch_all }.to raise_error(Ammitto::NetworkError, /catalogue/)
        end
      end

      ['file:///etc/passwd', 'http://github.com/ammitto/data/releases/download/latest/all.jsonld',
       'https://example.com/all.jsonld', 'https://github.com/ammitto/data/releases/latest/download/all.jsonld',
       'https://user:password@www.ammitto.org/api/v1/all.jsonld', ''].each do |url|
        it "rejects unsafe or unpinned catalogue targets: #{url}" do
          stub_request(:get, "#{base}/index.jsonld").to_return(body: catalogue_response(url))

          expect { client.fetch_all }.to raise_error(Ammitto::NetworkError, /bulk download URL/)
        end
      end

      ['http://release-assets.githubusercontent.com/asset', 'file:///etc/passwd',
       'https://example.com/asset', 'https://user:password@github.com/asset', nil].each do |location|
        it "rejects unsafe or missing release redirects: #{location}" do
          stub_request(:get, "#{base}/index.jsonld").to_return(body: catalogue_response(release_url))
          headers = location ? { location: location } : {}
          stub_request(:get, release_url).to_return(status: 302, headers: headers)

          expect { client.fetch_all }.to raise_error(Ammitto::NetworkError, /bulk download redirect/)
        end
      end

      it 'accepts five safe asset redirects' do
        stub_request(:get, "#{base}/index.jsonld").to_return(body: catalogue_response(release_url))
        stub_request(:get, release_url).to_return(status: 302, headers: { location: asset_url })
        stub_request(:get, asset_url)
          .to_return(status: 307, headers: { location: asset_url }).times(4)
          .then.to_return(body: data.to_json)

        expect(client.fetch_all).to eq(data)
      end

      it 'bounds redirect loops' do
        stub_request(:get, "#{base}/index.jsonld").to_return(body: catalogue_response(release_url))
        stub_request(:get, release_url).to_return(status: 302, headers: { location: release_url })

        expect { client.fetch_all }.to raise_error(Ammitto::NetworkError, /Too many/)
        expect(a_request(:get, release_url)).to have_been_made.times(6)
      end

      it 'reports an unavailable asset with the published URL' do
        stub_request(:get, "#{base}/index.jsonld").to_return(body: catalogue_response(release_url))
        stub_request(:get, release_url).to_return(status: 404)

        expect { client.fetch_all }.to raise_error(Ammitto::NetworkError) { |error|
          expect(error.status_code).to eq(404)
          expect(error.url).to eq(release_url)
        }
      end

      it 'reports HTTP errors at the final asset URL' do
        stub_request(:get, "#{base}/index.jsonld").to_return(body: catalogue_response(release_url))
        stub_request(:get, release_url).to_return(status: 302, headers: { location: asset_url })
        stub_request(:get, asset_url).to_return(status: 403)

        expect { client.fetch_all }.to raise_error(Ammitto::NetworkError) { |error|
          expect(error.status_code).to eq(403)
          expect(error.url).to eq(asset_url)
        }
      end

      it 'normalizes release transport failures' do
        stub_request(:get, "#{base}/index.jsonld").to_return(body: catalogue_response(release_url))
        stub_request(:get, release_url).to_return(status: 302, headers: { location: asset_url })
        stub_request(:get, asset_url).to_timeout

        expect { client.fetch_all }.to raise_error(Ammitto::NetworkError) { |error|
          expect(error.url).to eq(asset_url)
        }
      end
    end

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
