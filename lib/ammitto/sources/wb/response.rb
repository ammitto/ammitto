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
          def from_json(data)
            # Handle nested response structure
            data = data['response'] if data.is_a?(Hash) && data.key?('response')
            super(data)
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

        # Override to handle nested response structure
        def self.from_json(data)
          # Handle nested response structure
          data = data['response'] if data.is_a?(Hash) && data.key?('response')
          super(data)
        end
      end
    end
  end
end
