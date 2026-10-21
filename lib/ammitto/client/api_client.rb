# frozen_string_literal: true

require 'faraday'
require 'uri'

module Ammitto
  module Client
    # ApiClient handles communication with the Ammitto API
    #
    # @example Fetching data
    #   client = ApiClient.new
    #   data = client.fetch_source(:eu)
    #   all_data = client.fetch_all
    #
    class ApiClient
      # @return [Faraday::Connection] the HTTP connection
      attr_reader :connection

      # Initialize the API client
      def initialize
        @connection = build_connection
      end

      # Fetch a single source
      # @param source_code [Symbol] the source code
      # @return [Hash] the parsed JSON-LD data
      def fetch_source(source_code)
        url = "#{base_url}/sources/#{source_code}.jsonld"
        response = get(url)

        if response.status == 404
          raise SourceDataNotFoundError.new(
            "No #{source_code} data is published at #{url} (HTTP 404)",
            status_code: 404,
            url: url
          )
        end

        unless response.success?
          raise NetworkError.new(
            "Failed to fetch #{source_code} data",
            status_code: response.status,
            url: url
          )
        end

        MultiJson.load(response.body)
      end

      # Fetch all sources combined
      # @return [Hash] the combined JSON-LD data
      def fetch_all
        MultiJson.load(get_bulk(bulk_url).body)
      end

      # Fetch the schema context
      # @return [Hash] the JSON-LD context
      def fetch_context
        url = "#{base_url}/context.jsonld"
        response = get(url)

        unless response.success?
          raise NetworkError.new(
            'Failed to fetch schema context',
            status_code: response.status,
            url: url
          )
        end

        MultiJson.load(response.body)
      end

      private

      # Older deployments have no catalogue. Only a missing catalogue permits
      # the legacy endpoint; an unavailable or malformed catalogue must not
      # silently select a different publication snapshot.
      def bulk_url
        url = "#{base_url.sub(%r{/+\z}, '')}/index.jsonld"
        response = get(url)
        return URI.join(url, 'all.jsonld').to_s if response.status == 404

        unless response.success?
          raise NetworkError.new(
            'Failed to fetch bulk catalogue', status_code: response.status, url: url
          )
        end

        catalogue = MultiJson.load(response.body)
        entries = catalogue.is_a?(Hash) ? catalogue['entries'] : nil
        matches = entries.is_a?(Array) ? entries.select { |entry| entry.is_a?(Hash) && entry['name'] == 'all.jsonld' } : []
        unless matches.length == 1 && matches.first['url'].is_a?(String)
          raise NetworkError.new(
            'Bulk catalogue must identify one all.jsonld download', url: url
          )
        end

        resolve_bulk_url(matches.first['url'], url)
      rescue MultiJson::ParseError => e
        raise NetworkError.new("Invalid bulk catalogue: #{e.message}", url: url)
      end

      def resolve_bulk_url(reference, catalogue_url)
        destination = URI.join(catalogue_url, reference)
        origin = URI.parse(catalogue_url)
        local = destination.scheme == origin.scheme && destination.host == origin.host && destination.port == origin.port
        release = destination.scheme == 'https' && destination.host == 'github.com' && destination.port == 443 &&
                  destination.path.match?(%r{\A/ammitto/data/releases/download/api-v1-[0-9a-f]{40}/all\.jsonld\z})
        unless (local || release) && destination.userinfo.nil? && destination.fragment.nil? && !reference.empty?
          raise NetworkError.new('Unsafe bulk download URL in catalogue', url: catalogue_url)
        end

        destination.to_s
      rescue URI::InvalidURIError
        raise NetworkError.new('Invalid bulk download URL in catalogue', url: catalogue_url)
      end

      # GitHub serves release bytes via a signed HTTPS asset redirect. Keep
      # redirect handling exclusive to bulk downloads, bounded, and restricted
      # to the release hosts; source/context fetches retain their old behavior.
      def get_bulk(url)
        current_url = url
        6.times do |attempt|
          response = get(current_url)
          return response if response.success?
          unless [301, 302, 303, 307, 308].include?(response.status)
            raise NetworkError.new(
              'Failed to fetch all data', status_code: response.status, url: current_url
            )
          end

          if attempt == 5
            raise NetworkError.new(
              'Too many bulk download redirects', status_code: response.status, url: current_url
            )
          end

          current_url = bulk_redirect_url(current_url, response)
        end
      end

      def bulk_redirect_url(current_url, response)
        location = response.headers['location']
        destination = URI.join(current_url, location.to_s)
        allowed_hosts = %w[github.com release-assets.githubusercontent.com objects.githubusercontent.com]
        unless location.is_a?(String) && !location.empty? && destination.scheme == 'https' &&
               allowed_hosts.include?(destination.host) && destination.port == 443 &&
               destination.userinfo.nil? && destination.fragment.nil?
          raise NetworkError.new('Unsafe bulk download redirect', status_code: response.status, url: current_url)
        end

        destination.to_s
      rescue URI::InvalidURIError
        raise NetworkError.new('Invalid bulk download redirect', status_code: response.status, url: current_url)
      end

      # A transport failure — DNS, refused connection, timeout, TLS —
      # has to reach the caller as NetworkError like every other fetch
      # failure. Faraday raises its own class from underneath, and a
      # caller rescuing NetworkError would miss it. Ordinary 4xx/5xx
      # responses are unaffected: no response-raising middleware is
      # installed, so those still return a response and are reported by
      # the `success?` check at each call site.
      # @param url [String] the URL to fetch
      # @return [Faraday::Response]
      # @raise [NetworkError] on any transport failure
      def get(url)
        connection.get(url)
      rescue Faraday::Error => e
        raise NetworkError.new("Failed to reach #{url}: #{e.message}", url: url)
      end

      # Build the Faraday connection
      # @return [Faraday::Connection]
      def build_connection
        Faraday.new do |f|
          f.options.timeout = Ammitto.configuration.read_timeout
          f.options.open_timeout = Ammitto.configuration.connection_timeout
          f.adapter Faraday.default_adapter
        end
      end

      # Get the base URL from configuration
      # @return [String]
      def base_url
        Ammitto.configuration.api_base_url
      end
    end
  end
end
