# frozen_string_literal: true

require 'faraday'

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
        response = connection.get(url)

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
        url = "#{base_url}/all.jsonld"
        response = connection.get(url)

        unless response.success?
          raise NetworkError.new(
            'Failed to fetch all data',
            status_code: response.status,
            url: url
          )
        end

        MultiJson.load(response.body)
      end

      # Fetch the schema context
      # @return [Hash] the JSON-LD context
      def fetch_context
        url = "#{base_url}/schema/context.jsonld"
        response = connection.get(url)

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
