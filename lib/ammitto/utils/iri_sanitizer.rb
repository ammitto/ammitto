# frozen_string_literal: true

module Ammitto
  module Utils
    # IriSanitizer provides methods for sanitizing strings and generating
    # valid IRIs (Internationalized Resource Identifiers) for the knowledge graph.
    #
    # == Normalized Knowledge Graph Structure
    #
    # The knowledge graph follows a normalized structure where:
    # - Entities are LIST-AGNOSTIC (can appear on multiple lists)
    # - Entries are LIST-SPECIFIC (junction tables linking entities to lists)
    # - Announcements are LIST-AGNOSTIC (can affect multiple lists)
    # - Legal Instruments are LIST-AGNOSTIC (can authorize multiple lists)
    #
    # == IRI Structure
    #
    #   # Entities - NO list_type (can be on multiple lists)
    #   BASE_URI/entity/{source}/{local_id}
    #
    #   # Entries - WITH list_type (specific to a list)
    #   BASE_URI/entry/{source}/{list_type}/{local_id}
    #
    #   # Announcements - NO list_type (can affect multiple lists)
    #   BASE_URI/announcement/{source}/{local_id}
    #
    #   # Legal Instruments - NO list_type (can authorize multiple lists)
    #   BASE_URI/legal_instrument/{source}/{local_id}
    #
    # == Examples
    #
    #   # Entity (list-agnostic)
    #   https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries
    #
    #   # Entry (list-specific) - links entity to a specific list
    #   https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries
    #
    #   # Same entity, different list entry
    #   https://www.ammitto.org/entry/cn/unreliable-entity-list/mitsubishi-heavy-industries
    #
    #   # Announcement (list-agnostic)
    #   https://www.ammitto.org/announcement/cn/mofcom-2026-11
    #
    #   # Legal Instrument (list-agnostic)
    #   https://www.ammitto.org/legal_instrument/cn/export-control-law
    #
    module IriSanitizer
      # Base URI for all Ammitto identifiers
      BASE_URI = 'https://www.ammitto.org'

      # Maximum length for a sanitized identifier
      MAX_ID_LENGTH = 64

      # Default identifier when sanitization results in empty string
      DEFAULT_ID = 'unknown'

      class << self
        # Sanitize a string for use as a URL-safe identifier.
        #
        # Rules:
        # - Convert to lowercase
        # - Replace whitespace with hyphens
        # - Remove special characters (keep only alphanumeric, hyphens, and underscores)
        # - Collapse multiple consecutive hyphens
        # - Remove leading/trailing hyphens
        # - Truncate to MAX_ID_LENGTH
        # - Return 'unknown' if result is empty
        #
        # @param str [String, nil] The string to sanitize
        # @return [String] Sanitized identifier
        #
        # @example Basic sanitization
        #   sanitize("Mitsubishi Heavy Industries")
        #   # => "mitsubishi-heavy-industries"
        #
        # @example Special characters
        #   sanitize("O'Brien & Co.")
        #   # => "obrien-co"
        #
        # @example Multiple spaces and hyphens
        #   sanitize("  Some   Name -- Test  ")
        #   # => "some-name-test"
        #
        # @example Empty or nil input
        #   sanitize(nil)
        #   # => "unknown"
        #   sanitize("")
        #   # => "unknown"
        #
        def sanitize(str)
          return DEFAULT_ID if str.nil? || str.to_s.strip.empty?

          sanitized = str.to_s
                         .gsub(/\s+/, '-') # Replace whitespace with hyphens
                         .gsub(/[^a-zA-Z0-9\-_]/, '') # Remove non-alphanumeric/hyphen/underscore chars
                         .gsub(/--+/, '-')           # Collapse multiple hyphens
                         .gsub(/^-|-$/, '')          # Remove leading/trailing hyphens
                         .downcase                   # Lowercase
                         .slice(0, MAX_ID_LENGTH)    # Truncate

          sanitized.empty? ? DEFAULT_ID : sanitized
        end

        # Generate an entity IRI (LIST-AGNOSTIC).
        #
        # Entities can appear on multiple lists, so they don't include list_type.
        # The entity is uniquely identified by source + local_id.
        #
        # @param source [String] Source code (e.g., "cn", "ru", "au")
        # @param local_id [String] Local entity identifier (unique within source)
        # @return [String] Full entity IRI
        #
        # @example
        #   entity_iri("cn", "mitsubishi-heavy-industries")
        #   # => "https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries"
        #
        def entity_iri(source, local_id)
          "#{BASE_URI}/entity/#{sanitize(source)}/#{sanitize(local_id)}"
        end

        # Generate an entry IRI (LIST-SPECIFIC).
        #
        # Entries are junction records linking entities to specific lists.
        # An entity can have multiple entries (one per list it appears on).
        #
        # @param source [String] Source code (e.g., "cn", "ru", "au")
        # @param list_type [String] List type (e.g., "import-export-control-list")
        # @param local_id [String] Local entry identifier
        # @return [String] Full entry IRI
        #
        # @example Same entity, different lists
        #   entry_iri("cn", "import-export-control-list", "mitsubishi-heavy-industries")
        #   # => "https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries"
        #
        #   entry_iri("cn", "unreliable-entity-list", "mitsubishi-heavy-industries")
        #   # => "https://www.ammitto.org/entry/cn/unreliable-entity-list/mitsubishi-heavy-industries"
        #
        def entry_iri(source, list_type, local_id)
          "#{BASE_URI}/entry/#{sanitize(source)}/#{sanitize(list_type)}/#{sanitize(local_id)}"
        end

        # Generate an announcement IRI (LIST-AGNOSTIC).
        #
        # Announcements can affect multiple lists, so they don't include list_type.
        #
        # @param source [String] Source code (e.g., "cn", "ru", "au")
        # @param local_id [String] Local announcement identifier
        # @return [String] Full announcement IRI
        #
        # @example
        #   announcement_iri("cn", "mofcom-2026-11")
        #   # => "https://www.ammitto.org/announcement/cn/mofcom-2026-11"
        #
        def announcement_iri(source, local_id)
          "#{BASE_URI}/announcement/#{sanitize(source)}/#{sanitize(local_id)}"
        end

        # Generate a legal instrument IRI (LIST-AGNOSTIC).
        #
        # Legal instruments can authorize multiple lists, so they don't include list_type.
        #
        # @param source [String] Source code (e.g., "cn", "ru", "au")
        # @param local_id [String] Local legal instrument identifier
        # @return [String] Full legal instrument IRI
        #
        # @example
        #   legal_instrument_iri("cn", "export-control-law")
        #   # => "https://www.ammitto.org/legal_instrument/cn/export-control-law"
        #
        def legal_instrument_iri(source, local_id)
          "#{BASE_URI}/legal_instrument/#{sanitize(source)}/#{sanitize(local_id)}"
        end

        # Generate an authority IRI.
        #
        # @param code [String] Authority code (e.g., "cn", "mofcom", "eu")
        # @return [String] Full authority IRI
        #
        # @example
        #   authority_iri("cn")
        #   # => "https://www.ammitto.org/authority/cn"
        #
        def authority_iri(code)
          "#{BASE_URI}/authority/#{sanitize(code)}"
        end

        # Generate a source IRI.
        #
        # @param source [String] Source code (e.g., "cn", "ru", "au")
        # @return [String] Full source IRI
        #
        # @example
        #   source_iri("cn")
        #   # => "https://www.ammitto.org/source/cn"
        #
        def source_iri(source)
          "#{BASE_URI}/source/#{sanitize(source)}"
        end

        # Generate a list type IRI.
        #
        # @param source [String] Source code
        # @param list_type [String] List type identifier
        # @return [String] Full list type IRI
        #
        # @example
        #   list_type_iri("cn", "import-export-control-list")
        #   # => "https://www.ammitto.org/list/cn/import-export-control-list"
        #
        def list_type_iri(source, list_type)
          "#{BASE_URI}/list/#{sanitize(source)}/#{sanitize(list_type)}"
        end

        # Parse an entity IRI (LIST-AGNOSTIC format).
        #
        # @param iri [String] The IRI to parse
        # @return [Hash] Components: type, source, local_id
        #
        # @example
        #   parse_entity_iri("https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries")
        #   # => { type: "entity", source: "cn", local_id: "mitsubishi-heavy-industries" }
        #
        def parse_entity_iri(iri)
          return nil if iri.nil? || !iri.start_with?(BASE_URI)

          path = iri.sub("#{BASE_URI}/", '')
          parts = path.split('/')

          return nil if parts.length < 3 || parts[0] != 'entity'

          {
            type: 'entity',
            source: parts[1],
            local_id: parts[2..].join('/')
          }
        end

        # Parse an entry IRI (LIST-SPECIFIC format).
        #
        # @param iri [String] The IRI to parse
        # @return [Hash] Components: type, source, list_type, local_id
        #
        # @example
        #   parse_entry_iri("https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries")
        #   # => { type: "entry", source: "cn", list_type: "import-export-control-list", local_id: "mitsubishi-heavy-industries" }
        #
        def parse_entry_iri(iri)
          return nil if iri.nil? || !iri.start_with?(BASE_URI)

          path = iri.sub("#{BASE_URI}/", '')
          parts = path.split('/')

          return nil if parts.length < 4 || parts[0] != 'entry'

          {
            type: 'entry',
            source: parts[1],
            list_type: parts[2],
            local_id: parts[3..].join('/')
          }
        end

        # Parse any IRI and extract its components.
        # Handles both list-agnostic and list-specific formats.
        #
        # @param iri [String] The IRI to parse
        # @return [Hash] Components including type, source, and optionally list_type, local_id
        #
        def parse_iri(iri)
          return nil if iri.nil? || !iri.start_with?(BASE_URI)

          path = iri.sub("#{BASE_URI}/", '')
          parts = path.split('/')

          return nil if parts.length < 2

          type = parts[0]

          case type
          when 'entry'
            # Entry IRIs have list_type: /entry/{source}/{list_type}/{local_id}
            return nil if parts.length < 4

            {
              type: type,
              source: parts[1],
              list_type: parts[2],
              local_id: parts[3..].join('/')
            }
          when 'entity', 'announcement', 'legal_instrument', 'authority', 'source'
            # List-agnostic: /{type}/{source}/{local_id} or /{type}/{id}
            {
              type: type,
              source: parts[1],
              local_id: parts[2..].join('/')
            }
          when 'list'
            # List type IRI: /list/{source}/{list_type}
            return nil if parts.length < 3

            {
              type: type,
              source: parts[1],
              list_type: parts[2]
            }
          end
        end

        # Validate that an IRI follows the expected structure.
        #
        # @param iri [String] The IRI to validate
        # @return [Boolean] True if valid
        #
        def valid_iri?(iri)
          parsed = parse_iri(iri)
          return false if parsed.nil?

          parsed[:type] && parsed[:source] && !parsed[:source].empty?
        end

        # Extract the entity IRI from an entry IRI.
        # Useful for navigation from entry to entity.
        #
        # @param entry_iri [String] An entry IRI
        # @return [String, nil] The corresponding entity IRI
        #
        # @example
        #   entity_iri_from_entry("https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries")
        #   # => "https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries"
        #
        def entity_iri_from_entry(entry_iri)
          parsed = parse_entry_iri(entry_iri)
          return nil if parsed.nil?

          entity_iri(parsed[:source], parsed[:local_id])
        end

        # Generate all entry IRIs for an entity across all known lists.
        #
        # @param source [String] Source code
        # @param local_id [String] Entity local ID
        # @param list_types [Array<String>] List of list types
        # @return [Array<String>] Array of entry IRIs
        #
        def entry_iris_for_entity(source, local_id, list_types)
          list_types.map do |list_type|
            entry_iri(source, list_type, local_id)
          end
        end
      end
    end
  end
end
