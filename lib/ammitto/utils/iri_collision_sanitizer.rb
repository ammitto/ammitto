# frozen_string_literal: true

require 'digest'

module Ammitto
  module Utils
    module IriSanitizer
      # Private class methods used by the sanitizer's collision-aware local-id
      # path. Kept separate so the public IRI builders stay small and auditable.
      module CollisionAware
        private

        def identifier_for(id, kind:, source:, list_type:, collision_registry:)
          collision_registry&.register(kind: kind, source: source,
                                       list_type: list_type, id: id)

          if id.length > MAX_ID_LENGTH &&
             collision_registry&.colliding?(kind: kind, source: source,
                                            list_type: list_type, id: id)
            digest_identifier(id)
          else
            truncate_id(id)
          end
        end

        def digest_identifier(id)
          digest = Digest::SHA256.hexdigest(id)[0, DIGEST_LENGTH]
          head = id[0, MAX_ID_LENGTH - DIGEST_LENGTH - 1]
          "#{head}-#{digest}"
        end

        def truncate_id(id)
          id.slice(0, MAX_ID_LENGTH)
        end

        def normalize(str)
          str.to_s
             .gsub(/\s+/, '-') # Replace whitespace with hyphens
             .gsub(/[^a-zA-Z0-9\-_]/, '') # Remove non-alphanumeric/hyphen/underscore chars
             .gsub(/--+/, '-')           # Collapse multiple hyphens
             .gsub(/^-|-$/, '')          # Remove leading/trailing hyphens
             .downcase                   # Lowercase
        end
      end
    end
  end
end
