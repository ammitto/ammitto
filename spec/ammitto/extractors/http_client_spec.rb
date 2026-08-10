# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/extractors/http_client'

RSpec.describe Ammitto::Extractors::HttpClient do
  # Every example stubs Net::HTTP.start, so nothing here touches the
  # network. That proves this client's DECISIONS — which hops it will
  # follow, which it refuses, what it sends. It cannot prove that a
  # government server still accepts our user agent or that its real
  # redirect chain matches these assumptions; only a live scheduled
  # fetch proves that.
  let(:url) { 'https://example.gov/list.xlsx' }

  # Builds a real Net::HTTPResponse so subclass checks (HTTPSuccess,
  # HTTPNotModified, ...) behave exactly as they do in production.
  def response(code, body: '', location: nil)
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(code)
    res = klass.new('1.1', code, 'msg')
    res['Location'] = location if location
    allow(res).to receive(:body).and_return(body)
    res
  end

  # Records each requested URI and replays +responses+ in order.
  # The proxy arrives as positional args (p_addr, p_port, ...), so they
  # are captured rather than ignored — the proxy contract is asserted.
  def stub_hops(*responses)
    requested = []
    allow(Net::HTTP).to receive(:start) do |host, _port, *pos, **opts, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |req|
        requested << { host: host, path: req.path, headers: req,
                       proxy: [pos[0], pos[1]],
                       use_ssl: opts[:use_ssl],
                       open_timeout: opts[:open_timeout],
                       read_timeout: opts[:read_timeout] }
        responses[requested.size - 1]
      end
      block.call(http)
    end
    requested
  end

  # Sets env vars for the block and restores them afterwards.
  def with_env(vars)
    previous = vars.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe 'the happy path' do
    it 'returns the body of a 200' do
      stub_hops(response('200', body: 'PAYLOAD'))

      expect(described_class.get(url)).to eq('PAYLOAD')
    end

    it 'sends the caller headers and always uses TLS' do
      hops = stub_hops(response('200'))

      described_class.get(url, headers: { 'User-Agent' => 'Mozilla/5.0' })

      expect(hops.first[:headers]['User-Agent']).to eq('Mozilla/5.0')
      expect(hops.first[:use_ssl]).to be(true)
    end

    it 'applies the default timeouts, and the caller overrides them' do
      hops = stub_hops(response('200'), response('200'))

      described_class.get(url)
      described_class.get(url, open_timeout: 120, read_timeout: 600)

      expect(hops[0].values_at(:open_timeout, :read_timeout)).to eq([60, 60])
      expect(hops[1].values_at(:open_timeout, :read_timeout)).to eq([120, 600])
    end

    # Narrow claim on purpose: Net::HTTP.start is stubbed, so no real
    # body is ever decompressed here. What this proves is that the
    # request is still ELIGIBLE for automatic decoding — Net::HTTP::Get
    # generated its own Accept-Encoding and nothing overrode it. Real
    # decompression is Ruby's, and only a live fetch exercises it.
    it 'leaves the request eligible for automatic gzip decoding' do
      hops = stub_hops(response('200'))

      described_class.get(url)

      expect(hops.first[:headers].decode_content).to be(true)
    end

    # The proxy must be resolved per-URI. Net::HTTP's own :ENV default
    # reads http_proxy and IGNORES https_proxy on Ruby 3.3/3.4, so an
    # operator behind an https-only proxy would silently go direct —
    # which is not what open-uri did.
    it 'honours https_proxy, which Net::HTTP\'s own default ignores' do
      hops = stub_hops(response('200'))

      with_env('https_proxy' => 'http://proxy.local:8080',
               'http_proxy' => nil, 'no_proxy' => nil) do
        described_class.get(url)
      end

      expect(hops.first[:proxy]).to eq(['proxy.local', 8080])
    end

    it 'goes direct when no_proxy covers the host' do
      hops = stub_hops(response('200'))

      with_env('https_proxy' => 'http://proxy.local:8080',
               'http_proxy' => nil, 'no_proxy' => 'example.gov') do
        described_class.get(url)
      end

      expect(hops.first[:proxy]).to eq([nil, nil])
    end
  end

  describe 'redirects' do
    %w[301 302 303 307 308].each do |code|
      it "follows a #{code} to another https host" do
        stub_hops(
          response(code, location: 'https://cdn.example.gov/f.xlsx'),
          response('200', body: 'MOVED')
        )

        expect(described_class.get(url)).to eq('MOVED')
      end
    end

    it 'resolves a relative Location against the current URI' do
      hops = stub_hops(
        response('302', location: '/elsewhere/f.xlsx'),
        response('200')
      )

      described_class.get(url)

      expect(hops.last[:host]).to eq('example.gov')
      expect(hops.last[:path]).to eq('/elsewhere/f.xlsx')
    end

    it 'refuses a downgrade to http' do
      stub_hops(response('302', location: 'http://example.gov/f.xlsx'))

      expect { described_class.get(url) }
        .to raise_error(OpenURI::HTTPError, /non-https forbidden/)
    end

    it 'refuses a redirect to a non-http scheme' do
      stub_hops(response('302', location: 'ftp://example.gov/f.xlsx'))

      expect { described_class.get(url) }
        .to raise_error(OpenURI::HTTPError, /non-https forbidden/)
    end

    it 'refuses a redirect that carries no Location' do
      stub_hops(response('302'))

      expect { described_class.get(url) }
        .to raise_error(OpenURI::HTTPError, /without a Location/)
    end

    it 'refuses a Location that cannot be parsed, as the same error' do
      stub_hops(response('302', location: 'http://[bad'))

      expect { described_class.get(url) }
        .to raise_error(OpenURI::HTTPError, /unparseable Location/)
    end

    # Headers travel with every hop by design. A mutant that dropped
    # them after the first request would otherwise survive, since the
    # credential examples only exercise the :same_origin branch.
    it 'carries the caller headers across a cross-host hop' do
      hops = stub_hops(
        response('302', location: 'https://cdn.example.gov/f.xlsx'),
        response('200')
      )

      described_class.get(url, headers: { 'User-Agent' => 'Mozilla/5.0' })

      expect(hops.last[:host]).to eq('cdn.example.gov')
      expect(hops.last[:headers]['User-Agent']).to eq('Mozilla/5.0')
    end

    it 'refuses a loop rather than spending every hop on it' do
      stub_hops(
        response('302', location: 'https://example.gov/b'),
        response('302', location: 'https://example.gov/list.xlsx')
      )

      expect { described_class.get(url) }
        .to raise_error(OpenURI::HTTPError, /redirect loop/)
    end

    it 'allows exactly max_redirects hops' do
      hops = stub_hops(
        response('302', location: 'https://example.gov/a'),
        response('302', location: 'https://example.gov/b'),
        response('302', location: 'https://example.gov/c'),
        response('200', body: 'THIRD')
      )

      expect(described_class.get(url)).to eq('THIRD')
      expect(hops.size).to eq(4) # the initial request plus three hops
    end

    it 'stops one hop later' do
      stub_hops(
        response('302', location: 'https://example.gov/a'),
        response('302', location: 'https://example.gov/b'),
        response('302', location: 'https://example.gov/c'),
        response('302', location: 'https://example.gov/d')
      )

      expect { described_class.get(url) }
        .to raise_error(OpenURI::HTTPError, /more than 3 redirects/)
    end

    # 304 is a Net::HTTPRedirection subclass but carries no Location.
    # Testing for the superclass instead of the status list turns this
    # response into a crash.
    # The message is matched whole on purpose. Testing for the
    # superclass instead of the status list ALSO produces a 304-prefixed
    # error ("304 redirect without a Location"), so a loose /^304 /
    # match passes against the very mistake this example exists to
    # catch.
    it 'treats 304 as a terminal response, not a redirect' do
      stub_hops(response('304'))

      expect { described_class.get(url) }
        .to raise_error(OpenURI::HTTPError, /\A304 msg\z/)
    end
  end

  describe 'credentialed requests' do
    # Headers travel with every hop, so a request carrying a key must
    # not be allowed to leave its origin.
    let(:key) { { 'apikey' => 'SECRET' } }

    it 'refuses to carry credentials to another host' do
      stub_hops(response('302', location: 'https://elsewhere.example/f'))

      expect do
        described_class.get(url, headers: key, redirect_policy: :same_origin)
      end.to raise_error(OpenURI::HTTPError, /cross-origin redirect forbidden/)
    end

    it 'still follows a redirect within the same origin' do
      hops = stub_hops(
        response('302', location: 'https://example.gov/v2/list.xlsx'),
        response('200', body: 'SAME')
      )

      result = described_class.get(url, headers: key,
                                        redirect_policy: :same_origin)

      expect(result).to eq('SAME')
      expect(hops.last[:headers]['apikey']).to eq('SECRET')
    end

    # A misspelled policy previously fell through to :any_https, which
    # silently disabled the credential boundary. Nothing in the request
    # would have looked wrong.
    it 'refuses an unrecognised policy instead of defaulting to open' do
      expect do
        described_class.get(url, headers: key, redirect_policy: :same_orgin)
      end.to raise_error(ArgumentError, /redirect_policy must be one of/)
    end

    it 'refuses the policy before making any request' do
      hops = stub_hops(response('200'))

      expect { described_class.get(url, redirect_policy: :nope) }
        .to raise_error(ArgumentError)
      expect(hops).to be_empty
    end
  end

  describe 'refusals before any request is made' do
    it 'rejects an http URL' do
      expect { described_class.get('http://example.gov/f') }
        .to raise_error(ArgumentError, /https required/)
    end

    it 'rejects the pipe form Security/Open warns about' do
      expect { described_class.get('|whoami') }
        .to raise_error(ArgumentError, /https required/)
    end
  end

  describe 'terminal failures' do
    it 'raises the error class the open-uri download raised' do
      stub_hops(response('403'))

      expect { described_class.get(url) }
        .to raise_error(OpenURI::HTTPError, /403/)
    end
  end
end
