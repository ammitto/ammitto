# frozen_string_literal: true

require 'lutaml/model'
require_relative '../types'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents a name variant for an entity
      #
      # Names can be in different scripts and languages.
      # One name should be marked as primary.
      #
      # @example Creating a name variant
      #   name = NameVariant.new(
      #     full_name: "Ivan Ivanovich Ivanov",
      #     first_name: "Ivan",
      #     middle_name: "Ivanovich",
      #     last_name: "Ivanov",
      #     script: :Cyrl,
      #     language: "ru",
      #     is_primary: true
      #   )
      #
      class NameVariant < Lutaml::Model::Serializable
        # Full name (complete name as a single string)
        # @return [String, nil]
        attribute :full_name, :string

        # First name / given name
        # @return [String, nil]
        attribute :first_name, :string

        # Middle name / patronymic
        # @return [String, nil]
        attribute :middle_name, :string

        # Last name / family name / surname
        # @return [String, nil]
        attribute :last_name, :string

        # Title (Mr, Mrs, Dr, etc.)
        # @return [String, nil]
        attribute :title, :string

        # Function/role (e.g., "Director", "General")
        # @return [String, nil]
        attribute :function, :string

        # Script of the name (ISO 15924 code)
        # @return [Symbol, nil]
        attribute :script, :string

        # Language code (ISO 639-1)
        # @return [String, nil]
        attribute :language, :string

        # Whether this is the primary name
        # @return [Boolean]
        attribute :is_primary, :boolean, default: false

        # Quality indicator (from source)
        # @return [Boolean, nil]
        attribute :is_strong, :boolean

        # Custom setter for script with normalization
        # @param value [String, Symbol, nil]
        def script=(value)
          super(value&.to_s)
        end

        # Get script as symbol
        # @return [Symbol, nil]
        def script_sym
          script&.to_sym
        end

        # Check if this is a primary name
        # @return [Boolean]
        def primary?
          is_primary == true
        end

        # Check if name is in non-Latin script
        # @return [Boolean]
        def non_latin?
          script && script != 'Latn'
        end

        # Get display name (full_name or constructed from parts)
        # @return [String]
        def display_name
          full_name || [title, first_name, middle_name, last_name].compact.join(' ')
        end

        # Detect script from full_name if not set
        # @return [void]
        def detect_script!
          self.script = Types.detect_script(full_name).to_s if full_name
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:full_name] = full_name if full_name
          hash[:first_name] = first_name if first_name
          hash[:middle_name] = middle_name if middle_name
          hash[:last_name] = last_name if last_name
          hash[:title] = title if title
          hash[:function] = function if function
          hash[:script] = script if script
          hash[:language] = language if language
          hash[:is_primary] = is_primary if is_primary
          hash
        end

        # JSON-LD mapping
        json do
          map :full_name, to: :full_name
          map :first_name, to: :first_name
          map :middle_name, to: :middle_name
          map :last_name, to: :last_name
          map :title, to: :title
          map :function, to: :function
          map :script, to: :script
          map :language, to: :language
          map :is_primary, to: :is_primary
        end

        # YAML mapping
        yaml do
          map :full_name, to: :full_name
          map :first_name, to: :first_name
          map :middle_name, to: :middle_name
          map :last_name, to: :last_name
          map :title, to: :title
          map :function, to: :function
          map :script, to: :script
          map :language, to: :language
          map :is_primary, to: :is_primary
        end
      end
    end
  end
end
