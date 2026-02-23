# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Wb
      # Root response wrapper
      class Response < Lutaml::Model::Serializable
        attribute :firms, SanctionedFirm, collection: true

        json do
          map 'ZPROCSUPP', to: :firms, with: { from: :firms_from_json, to: :firms_to_json }
        end

        yaml do
          map 'firms', to: :firms
        end

        class << self
          # Override from_json to handle nested response structure
          # @param data [String, Hash] JSON string or parsed Hash
          # @return [Response]
          def from_json(data)
            # Parse string to hash if needed
            data = JSON.parse(data) if data.is_a?(String)

            # Extract nested response structure
            data = data['response'] if data.is_a?(Hash) && data.key?('response')

            # Create instance and populate firms
            instance = new
            firms_data = data['ZPROCSUPP'] || []
            instance.firms = firms_data.map do |item|
              # Convert Hash to JSON string for lutaml-model
              SanctionedFirm.from_json(item.to_json)
            end
            instance
          end
        end

        def firms_from_json(data, _doc)
          # Handle nested response.ZPROCSUPP structure
          if data.is_a?(Hash) && data.key?('ZPROCSUPP')
            data['ZPROCSUPP'].map { |item| SanctionedFirm.from_json(item) }
          elsif data.is_a?(Array)
            data.map { |item| SanctionedFirm.from_json(item) }
          else
            []
          end
        end

        def firms_to_json
          { 'ZPROCSUPP' => firms.map(&:to_json) }
        end
      end
    end
  end
end
