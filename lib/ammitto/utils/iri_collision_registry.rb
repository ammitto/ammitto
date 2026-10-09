# frozen_string_literal: true

require 'digest'
require_relative '../error'

module Ammitto
  module Utils
    module IriSanitizer
      # Records complete normalized local ids in one harmonization scope so
      # only ids that would actually collide receive a digest.
      class CollisionRegistry
        def initialize
          @ids_by_scope = Hash.new { |hash, key| hash[key] = {} }
          @colliding_ids = {}
          @finalized = false
        end

        # @param kind [String] IRI kind (entity, entry, ...)
        # @param source [String] source code
        # @param list_type [String, nil] entry list type
        # @param id [String] complete normalized local id
        # @return [void]
        def register(kind:, source:, list_type:, id:)
          @ids_by_scope[scope_key(kind, source, list_type)][id] = true
        end

        # Run one candidate transform transactionally. A transform that raises
        # may already have minted one or more ids; none of those ids belongs in
        # the collision decision for the surviving records.
        # @return [Object] the block's result
        def with_candidate
          snapshot = Hash.new { |hash, key| hash[key] = {} }
          @ids_by_scope.each { |scope, ids| snapshot[scope] = ids.dup }
          yield
        rescue StandardError
          @ids_by_scope = snapshot
          raise
        end

        # Freeze the collision decision after the candidate pass. A set of
        # identical normalized ids represents one record, not a collision.
        # @return [self]
        def finalize!
          @colliding_ids = @ids_by_scope.each_with_object({}) do |(scope, ids), result|
            colliding = ids.keys.group_by { |id| id[0, IriSanitizer::MAX_ID_LENGTH] }
                                .values
                                .select { |group| group.length > 1 }
                                .flatten
            result[scope] = colliding.to_h { |id| [id, true] }
          end
          reject_emitted_id_collisions!
          @finalized = true
          self
        end

        # @param kind [String]
        # @param source [String]
        # @param list_type [String, nil]
        # @param id [String]
        # @return [Boolean]
        def colliding?(kind:, source:, list_type:, id:)
          @finalized && digest?(scope_key(kind, source, list_type), id)
        end

        # @return [Boolean] whether any id in any scope needs a second pass
        def collisions?
          @colliding_ids.any? { |_scope, ids| ids.any? }
        end

        private

        # An entry also takes its entity's digest, so entity_iri_from_entry
        # still lands on the entity IRI that was actually emitted.
        def digest?(scope, id)
          return true if @colliding_ids.dig(scope, id)
          return false unless scope.first == 'entry'

          @colliding_ids.dig(['entity', scope[1], nil], id) ? true : false
        end

        def scope_key(kind, source, list_type)
          [kind.to_s, source.to_s.downcase,
           kind.to_s == 'entry' ? IriSanitizer.sanitize(list_type) : nil].freeze
        end

        def reject_emitted_id_collisions!
          @ids_by_scope.each do |scope, ids|
            emitted = ids.keys.to_h do |id|
              [id, emitted_identifier(scope, id)]
            end
            duplicates = emitted.group_by(&:last).values.select { |group| group.length > 1 }
            next if duplicates.empty?

            details = duplicates.map { |group| group.map(&:first).inspect }.join(', ')
            raise Ammitto::ParseError,
                  "IRI ids collide after sanitization in scope #{scope.inspect}: #{details}"
          end
        end

        def emitted_identifier(scope, id)
          colliding = digest?(scope, id) &&
                      id.length > IriSanitizer::MAX_ID_LENGTH
          return truncate_id(id) unless colliding

          digest = Digest::SHA256.hexdigest(id)[0, IriSanitizer::DIGEST_LENGTH]
          head = id[0, IriSanitizer::MAX_ID_LENGTH - IriSanitizer::DIGEST_LENGTH - 1]
          "#{head}-#{digest}"
        end

        def truncate_id(id)
          id.slice(0, IriSanitizer::MAX_ID_LENGTH)
        end
      end
    end
  end
end
