# frozen_string_literal: true

require 'net/http'
require 'open-uri' # OpenURI::HTTPError only; this file never calls URI.open

module Ammitto
  module Extractors
    # One HTTPS downloader for every extractor.
    #
    # The extractors reached their sources through +URI.open+, which is
    # convenient but carries policy nobody declared: RuboCop's
    # Security/Open flags it because a string beginning "|" runs a
    # subprocess, and on Ruby 3.3 open-uri applies no numeric redirect
    # cap at all. None of the call sites build a URL from untrusted
    # input, so the pipe form was never reachable here — the reason to
    # move is that every source now follows ONE written-down policy
    # instead of open-uri's defaults varying across the supported Ruby
    # range.
    #
    # Deliberately preserved from open-uri, because changing them would
    # be a behaviour change wearing a cleanup's clothes:
    #
    # - HTTPS-only, at every hop. open-uri already refuses an
    #   https->http redirect; so does this. Nothing here closes a
    #   downgrade that open-uri permitted.
    # - Environment proxies, resolved the way open-uri resolved them.
    #   +Net::HTTP+'s own :ENV default is NOT equivalent: on Ruby 3.3
    #   and 3.4 it reads http_proxy and ignores https_proxy, so an
    #   operator behind an https-only proxy would have silently gone
    #   direct. +URI#find_proxy+ picks the right variable for the
    #   scheme and honours no_proxy, so the proxy is resolved here and
    #   passed in explicitly.
    # - Transparent gzip. Net::HTTP advertises the encodings it can
    #   decode and decodes them, but only while the caller leaves
    #   Accept-Encoding unset — so this never sets it.
    # - 60-second open and read timeouts, Net::HTTP's own defaults,
    #   which is what open-uri was already using. Callers that had
    #   chosen something else keep choosing it.
    # - +OpenURI::HTTPError+ on a non-2xx terminal response, so callers
    #   that rescue it keep working.
    class HttpClient
      # Redirect hops allowed after the initial request. open-uri on
      # Ruby 3.4+ allows 64 and on 3.3 allows unlimited; no sanctions
      # source legitimately needs more than a couple.
      MAX_REDIRECTS = 3

      # Net::HTTP's own defaults, which is what open-uri applied here.
      OPEN_TIMEOUT = 60
      READ_TIMEOUT = 60

      # The statuses open-uri treats as redirects. Net::HTTPRedirection
      # is deliberately NOT used as the test: 304 Not Modified is one
      # of its subclasses and carries no Location, so following it
      # blindly turns a valid response into a crash.
      REDIRECT_CODES = %w[301 302 303 307 308].freeze

      # Recognised redirect policies. An unrecognised value is refused
      # rather than defaulted: silently falling back to :any_https
      # would turn a typo like :same_orgin into a credential leak, and
      # nothing in the request would look wrong.
      REDIRECT_POLICIES = %i[any_https same_origin].freeze

      class << self
        # Fetches +url+ and returns the response body.
        #
        # @param url [String] an https URL
        # @param headers [Hash] request headers, sent on every hop
        #   unless +redirect_policy+ is :same_origin
        # @param open_timeout [Integer] seconds to wait for the connection
        # @param read_timeout [Integer] seconds to wait for the body
        # @param max_redirects [Integer] hops allowed after the first request
        # @param redirect_policy [Symbol] :any_https follows an https
        #   redirect to any host — correct for public downloads.
        #   :same_origin refuses to leave the original host/port, which
        #   is what a request carrying a credential needs: +headers+
        #   travel with every hop, so a cross-host redirect would hand
        #   the secret to whoever answered.
        # @return [String] the response body
        # @raise [OpenURI::HTTPError] on a non-2xx terminal response, or
        #   any redirect this client refuses to follow — non-https,
        #   cross-origin while credentialed, missing or unparseable
        #   Location, a loop, or too many hops
        # @raise [ArgumentError] if +url+ is not https, or
        #   +redirect_policy+ is not one of REDIRECT_POLICIES
        def get(url, headers: {}, open_timeout: OPEN_TIMEOUT,
                read_timeout: READ_TIMEOUT, max_redirects: MAX_REDIRECTS,
                redirect_policy: :any_https)
          validate_policy(redirect_policy)
          uri = parse_https(url)
          origin = uri.dup
          seen = [uri.to_s]

          (max_redirects + 1).times do
            response = request(uri, headers, open_timeout, read_timeout)
            return response.body if response.is_a?(Net::HTTPSuccess)

            uri = redirect_target(response, uri, origin, redirect_policy, seen)
            seen << uri.to_s
          end

          raise OpenURI::HTTPError.new(
            "more than #{max_redirects} redirects for #{url}", nil
          )
        end

        private

        # @raise [ArgumentError] on an unrecognised policy
        def validate_policy(policy)
          return if REDIRECT_POLICIES.include?(policy)

          raise ArgumentError,
                'redirect_policy must be one of ' \
                "#{REDIRECT_POLICIES.inspect}, got: #{policy.inspect}"
        end

        # Anything that is not a usable https URL is refused the same
        # way, whether it parses to another scheme or does not parse at
        # all — "|whoami", the shape Security/Open warns about, lands
        # here as an unparseable URI rather than a second error class.
        #
        # @param url [String]
        # @return [URI::HTTPS]
        def parse_https(url)
          uri = begin
            URI.parse(url.to_s)
          rescue URI::InvalidURIError
            nil
          end
          return uri if uri.is_a?(URI::HTTPS)

          raise ArgumentError, "https required, got: #{url}"
        end

        # Resolves one redirect, or raises if it must not be followed.
        #
        # @return [URI::HTTPS]
        def redirect_target(response, uri, origin, redirect_policy, seen)
          unless REDIRECT_CODES.include?(response.code)
            raise OpenURI::HTTPError.new(
              "#{response.code} #{response.message}", nil
            )
          end

          location = response['Location']
          if location.nil? || location.empty?
            raise OpenURI::HTTPError.new(
              "#{response.code} redirect without a Location", nil
            )
          end

          # A server that sends a Location we cannot parse is a failed
          # redirect, not a caller error — it surfaces as the same
          # OpenURI::HTTPError every other refused hop raises, so
          # callers need one rescue rather than two.
          target = begin
            URI.join(uri.to_s, location)
          rescue URI::InvalidURIError => e
            raise OpenURI::HTTPError.new(
              "#{response.code} unparseable Location: #{e.message}", nil
            )
          end

          check_hop(target, origin, redirect_policy, seen)
          target
        end

        # @raise [OpenURI::HTTPError] if the hop breaks policy
        def check_hop(target, origin, redirect_policy, seen)
          unless target.is_a?(URI::HTTPS)
            raise OpenURI::HTTPError.new(
              "redirection to non-https forbidden: #{target}", nil
            )
          end

          if redirect_policy == :same_origin && !same_origin?(target, origin)
            raise OpenURI::HTTPError.new(
              'cross-origin redirect forbidden for a credentialed ' \
              "request: #{target}", nil
            )
          end

          return unless seen.include?(target.to_s)

          raise OpenURI::HTTPError.new("redirect loop at #{target}", nil)
        end

        # @return [Boolean]
        def same_origin?(target, origin)
          target.host == origin.host && target.port == origin.port
        end

        # One GET; the caller's loop owns redirect following.
        #
        # The proxy is resolved per-URI rather than left to
        # Net::HTTP's :ENV default — see the class comment. A nil proxy
        # means "go direct", which is exactly what find_proxy returns
        # when no_proxy matches or nothing is configured.
        #
        # Accept-Encoding is never set, so Net::HTTP::Get advertises the
        # encodings it can decode and gzip stays transparent.
        #
        # @return [Net::HTTPResponse]
        def request(uri, headers, open_timeout, read_timeout)
          proxy = uri.find_proxy
          Net::HTTP.start(
            uri.host, uri.port,
            proxy&.host, proxy&.port, proxy&.user, proxy&.password,
            use_ssl: true,
            open_timeout: open_timeout, read_timeout: read_timeout
          ) do |http|
            http.request(Net::HTTP::Get.new(uri, headers))
          end
        end
      end
    end
  end
end
