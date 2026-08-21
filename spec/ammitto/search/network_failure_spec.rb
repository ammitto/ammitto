# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'ammitto'

# One unreachable source must not take a whole search down.
#
# QueryBuilder#execute already says so in its own comment, and rescues
# NetworkError per source to make it true. But BaseSource#download_to_cache
# calls Faraday.get directly, and Faraday raises its own error class for a
# transport failure — DNS, refused connection, timeout. That escaped the
# rescue, so on a cold cache with no network `Ammitto.search` died with
# Faraday::ConnectionFailed instead of returning the sources it could read.
#
# The fix converts a transport failure into the NetworkError the search
# path already handles. These examples pin both halves: the conversion,
# and the survival that depends on it.
RSpec.describe 'search when a source cannot be reached' do
  let(:source) do
    Class.new(Ammitto::BaseSource) { def code = :tr }.new
  end

  let(:cache_dir) { Dir.mktmpdir('ammitto-network') }

  before { allow(Ammitto.configuration).to receive(:cache_dir).and_return(cache_dir) }

  after { FileUtils.remove_entry(cache_dir) if File.directory?(cache_dir) }

  it 'reports a transport failure as NetworkError, not as a Faraday error' do
    allow(Faraday).to receive(:get)
      .and_raise(Faraday::ConnectionFailed.new('Failed to open TCP connection'))

    expect { source.download_to_cache }
      .to raise_error(Ammitto::NetworkError, /Failed to download tr data/)
  end

  it 'keeps the underlying reason in the message' do
    allow(Faraday).to receive(:get)
      .and_raise(Faraday::ConnectionFailed.new('getaddrinfo: Name or service not known'))

    expect { source.download_to_cache }
      .to raise_error(Ammitto::NetworkError, /getaddrinfo/)
  end

  describe Ammitto::Client::ApiClient do
    # The same normalization on the other fetch path. refresh_cache does
    # not crash without it — CacheManager#refresh_source has a broad
    # StandardError rescue — but a caller using ApiClient directly would
    # see a Faraday class where every other failure gives NetworkError.
    subject(:client) { described_class.new }

    before do
      allow(client.connection).to receive(:get)
        .and_raise(Faraday::ConnectionFailed.new('Failed to open TCP connection'))
    end

    %i[fetch_all fetch_context].each do |call|
      it "reports a transport failure from #{call} as NetworkError" do
        expect { client.public_send(call) }
          .to raise_error(Ammitto::NetworkError, /Failed to reach/)
      end
    end

    it 'reports a transport failure from fetch_source as NetworkError' do
      expect { client.fetch_source(:tr) }
        .to raise_error(Ammitto::NetworkError, /Failed to reach/)
    end
  end

  it 'lets a search finish instead of raising out of it' do
    # The whole point: a laptop with no network gets an empty result set
    # and a warning, not a stack trace.
    allow(Faraday).to receive(:get)
      .and_raise(Faraday::ConnectionFailed.new('Failed to open TCP connection'))

    results = nil
    expect { results = Ammitto.search('mohammad', sources: [:tr], limit: 3) }
      .not_to raise_error
    expect(results).to be_empty
  end
end
