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

        # lutaml-model calls a custom `from` method with the model being built
        # and the raw value, and uses only what the method assigns.
        def firms_from_json(model, value)
          items = value.is_a?(Hash) ? value['ZPROCSUPP'] : value
          model.firms = (items.is_a?(Array) ? items : []).map do |item|
            SanctionedFirm.from_json(item.to_json)
          end
        end

        # The matching `to` method gets the model and the element being
        # written, and writes the key itself.
        def firms_to_json(model, doc)
          doc['ZPROCSUPP'] = model.items.map { |firm| SanctionedFirm.as_json(firm) }
        end

        # Every fetched record this source carries.
        # @return [Array<SanctionedFirm>]
        def items
          firms || []
        end
      end
    end
  end
end
