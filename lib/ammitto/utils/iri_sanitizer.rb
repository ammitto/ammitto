# frozen_string_literal: true

require 'date' # FIXED_SIZE_TYPES references Date at load time

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

      # Default identifier when sanitization results in empty string.
      # Only non-identifying IRI components (source codes, list types,
      # authority codes) may fall back to it — never a local id, where a
      # shared "unknown" would merge distinct sanctioned parties into one
      # record (the 2026-07-28 harvest audit: 37 Turkish designees
      # collapsed into a single entity/tr/unknown).
      DEFAULT_ID = 'unknown'

      # Raised when an IRI is requested for a record whose local id is
      # nil, empty, or sanitizes to nothing. Carries the source code so
      # per-file error attribution in the harmonize pipeline names the
      # offending source record instead of silently emitting a shared
      # ".../unknown" IRI.
      class MissingLocalIdError < StandardError
        attr_reader :source, :kind, :value

        # @param source [String] source code the IRI was requested for
        # @param kind [String] IRI kind (entity, entry, announcement, ...)
        # @param value [Object] the rejected local id
        def initialize(source:, kind:, value:)
          @source = source
          @kind = kind
          @value = value
          super(self.class.describe(source, kind, value))
        end

        # Build the message. Each label is produced defensively: a
        # diagnostic must never mask the error it describes, so a value
        # whose own methods raise (a singleton #size, an overridden
        # #inspect) degrades to a placeholder instead of escaping as an
        # unrelated exception. This complements the exact-class dispatch
        # in #preview, which bounds how much work those labels can do.
        # @param source [Object] source the IRI was requested for
        # @param kind [String] IRI kind (entity, entry, ...)
        # @param value [Object] the rejected local id
        # @return [String] the error message
        def self.describe(source, kind, value)
          "#{safe_label { short_label(source) }}: cannot build " \
            "#{safe_label { short_label(kind) }} IRI from blank or " \
            "unusable local id #{safe_label { preview(value) }} — the " \
            'source record is missing a usable identifier (refusing ' \
            'to emit an "unknown" IRI)'
        end

        # Run a label builder, degrading to a placeholder if the value's
        # own methods raise
        # @return [String]
        def self.safe_label
          yield
        rescue StandardError
          '(unprintable)'
        end

        # Classes whose #inspect is inherently short, so calling it to
        # build a diagnostic cannot materialize a large string. Matched
        # by EXACT class (see #renderable?): a subclass may override
        # #inspect. Symbol and Integer are deliberately absent — their
        # representations are unbounded (a 200k-character symbol, a
        # million-digit integer), so they report their class instead.
        FIXED_SIZE_TYPES = [NilClass, TrueClass, FalseClass, Float,
                            Date, Time].freeze

        # Bounded preview of the rejected id. No branch calls an
        # unbounded or overridable conversion: a String is sliced before
        # #inspect (escape expansion is capped afterwards), exact
        # containers report class and size instead of inspecting
        # elements, only exact fixed-size classes are inspected, and
        # anything else — unknown objects, ANY subclass (whose #size or
        # #inspect could raise or run long), Symbol, Integer — reports
        # its class alone. Every branch is matched by exact class, and
        # the result is capped regardless.
        # @param value [Object] the rejected local id
        # @return [String] inspect-style preview, at most ~64 chars
        def self.preview(value)
          text =
            if value.instance_of?(Array) || value.instance_of?(Hash)
              "#{value.class}(#{value.size} entries)"
            elsif value.instance_of?(String)
              sliced = value.length > 61 ? "#{value[0, 61]}..." : value
              sliced.inspect
            elsif renderable?(value)
              value.inspect
            else
              "#{value.class} instance"
            end
          truncate(text)
        end

        # Whether a value may be rendered by #inspect: exact class only,
        # so an overriding subclass never reaches #inspect
        # @param value [Object] the value to test
        # @return [Boolean]
        def self.renderable?(value)
          FIXED_SIZE_TYPES.include?(value.class)
        end

        # Bounded label for a short message component (the source code
        # and the IRI kind). Both are short strings or symbols drawn
        # from fixed lists; anything else reports its class rather than
        # risking an unbounded or overridable #to_s. Applied to the kind
        # as well as the source so no component of a diagnostic can
        # outgrow or outlive the error it describes, even though every
        # caller passes a literal kind today.
        # @param value [Object] the component to label
        # @return [String] label, at most ~32 chars
        def self.short_label(value)
          label = if value.instance_of?(String)
                    value
                  elsif value.instance_of?(Symbol)
                    value.name
                  else
                    "#{value.class} instance"
                  end
          label.length > 32 ? "#{label[0, 29]}..." : label
        end

        # Cap an already-built preview string
        # @param str [String] inspect output
        # @return [String] at most 64 characters
        def self.truncate(str)
          str.length > 64 ? "#{str[0, 61]}..." : str
        end
      end

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

          sanitized = apply_sanitization_rules(str)

          sanitized.empty? ? DEFAULT_ID : sanitized
        end

        # Sanitize a local id for use in an identifying IRI, raising
        # instead of falling back to DEFAULT_ID.
        #
        # Local ids identify individual records; a nil/empty id (or one
        # that sanitizes to nothing) must fail loudly so the harmonize
        # health gates surface the defective source file, rather than
        # collapsing distinct records into one shared "unknown" IRI.
        #
        # The id is converted to a string exactly once. Local ids reach
        # this method straight from parsed YAML, so #to_s may be
        # heavyweight (an Array id materializes its whole contents) or
        # non-idempotent; converting twice would double that cost and
        # let the blank check and the sanitizer disagree about the same
        # id. The unconverted id is still what MissingLocalIdError
        # receives, so #preview keeps its exact-class dispatch.
        #
        # @param local_id [Object] the raw local id
        # @param source [String] source code, for error attribution
        # @param kind [String] IRI kind (entity, entry, announcement, ...)
        # @return [String] sanitized identifier
        # @raise [MissingLocalIdError] when the id is nil/empty or
        #   sanitizes to an empty string
        def sanitize_local_id!(local_id, source:, kind:)
          text = local_id.nil? ? '' : local_id.to_s
          sanitized =
            text.strip.empty? ? '' : apply_sanitization_rules(text)
          return sanitized unless sanitized.empty?

          raise MissingLocalIdError.new(source: source, kind: kind,
                                        value: local_id)
        end

        # Generate an entity IRI (LIST-AGNOSTIC).
        #
        # Entities can appear on multiple lists, so they don't include list_type.
        # The entity is uniquely identified by source + local_id.
        #
        # @param source [String] Source code (e.g., "cn", "ru", "au")
        # @param local_id [String] Local entity identifier (unique within source)
        # @return [String] Full entity IRI
        # @raise [MissingLocalIdError] when local_id is blank or
        #   sanitizes to nothing
        #
        # @example
        #   entity_iri("cn", "mitsubishi-heavy-industries")
        #   # => "https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries"
        #
        def entity_iri(source, local_id)
          id = sanitize_local_id!(local_id, source: source, kind: 'entity')
          "#{BASE_URI}/entity/#{sanitize(source)}/#{id}"
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
        # @raise [MissingLocalIdError] when local_id is blank or
        #   sanitizes to nothing
        #
        # @example Same entity, different lists
        #   entry_iri("cn", "import-export-control-list", "mitsubishi-heavy-industries")
        #   # => "https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries"
        #
        #   entry_iri("cn", "unreliable-entity-list", "mitsubishi-heavy-industries")
        #   # => "https://www.ammitto.org/entry/cn/unreliable-entity-list/mitsubishi-heavy-industries"
        #
        def entry_iri(source, list_type, local_id)
          id = sanitize_local_id!(local_id, source: source, kind: 'entry')
          "#{BASE_URI}/entry/#{sanitize(source)}/#{sanitize(list_type)}/#{id}"
        end

        # Generate an announcement IRI (LIST-AGNOSTIC).
        #
        # Announcements can affect multiple lists, so they don't include list_type.
        #
        # @param source [String] Source code (e.g., "cn", "ru", "au")
        # @param local_id [String] Local announcement identifier
        # @return [String] Full announcement IRI
        # @raise [MissingLocalIdError] when local_id is blank or
        #   sanitizes to nothing
        #
        # @example
        #   announcement_iri("cn", "mofcom-2026-11")
        #   # => "https://www.ammitto.org/announcement/cn/mofcom-2026-11"
        #
        def announcement_iri(source, local_id)
          id = sanitize_local_id!(local_id, source: source,
                                            kind: 'announcement')
          "#{BASE_URI}/announcement/#{sanitize(source)}/#{id}"
        end

        # Generate a legal instrument IRI (LIST-AGNOSTIC).
        #
        # Legal instruments can authorize multiple lists, so they don't include list_type.
        #
        # @param source [String] Source code (e.g., "cn", "ru", "au")
        # @param local_id [String] Local legal instrument identifier
        # @return [String] Full legal instrument IRI
        # @raise [MissingLocalIdError] when local_id is blank or
        #   sanitizes to nothing
        #
        # @example
        #   legal_instrument_iri("cn", "export-control-law")
        #   # => "https://www.ammitto.org/legal_instrument/cn/export-control-law"
        #
        def legal_instrument_iri(source, local_id)
          id = sanitize_local_id!(local_id, source: source,
                                            kind: 'legal_instrument')
          "#{BASE_URI}/legal_instrument/#{sanitize(source)}/#{id}"
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
        # @raise [MissingLocalIdError] when the parsed local id segment
        #   sanitizes to nothing
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
        # @raise [MissingLocalIdError] when local_id is blank or
        #   sanitizes to nothing
        #
        def entry_iris_for_entity(source, local_id, list_types)
          list_types.map do |list_type|
            entry_iri(source, list_type, local_id)
          end
        end

        private

        # The shared sanitization pipeline; may return an empty string
        # (callers decide between DEFAULT_ID fallback and raising)
        # @param str [Object] the string to sanitize
        # @return [String] sanitized identifier, possibly empty
        def apply_sanitization_rules(str)
          str.to_s
             .gsub(/\s+/, '-') # Replace whitespace with hyphens
             .gsub(/[^a-zA-Z0-9\-_]/, '') # Remove non-alphanumeric/hyphen/underscore chars
             .gsub(/--+/, '-')           # Collapse multiple hyphens
             .gsub(/^-|-$/, '')          # Remove leading/trailing hyphens
             .downcase                   # Lowercase
             .slice(0, MAX_ID_LENGTH)    # Truncate
        end
      end
    end
  end
end
