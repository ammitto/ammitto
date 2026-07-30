# frozen_string_literal: true

module Ammitto
  module Utils
    # ListTypesRegistry defines the available list types for each source.
    # Each source can have multiple lists, each representing a different
    # sanctions or control regime.
    #
    # List types should be:
    # - Lowercase with hyphens
    # - URL-safe
    # - Descriptive of the list purpose
    # - Unique per source
    #
    module ListTypesRegistry
      # China (CN) list types
      CN = {
        'anti-sanction-list' => {
          name: 'Anti-Sanction List',
          name_chinese: '反制裁清单',
          authority: 'MFA'
        },
        'import-export-control-list' => {
          name: 'Import-Export Control List',
          name_chinese: '出口管制管控名单',
          authority: 'MOFCOM'
        },
        'unreliable-entity-list' => {
          name: 'Unreliable Entity List',
          name_chinese: '不可靠实体清单',
          authority: 'MOFCOM'
        }
      }.freeze

      # Russia (RU) list types
      RU = {
        'stop-list' => {
          name: 'Stop List',
          name_russian: 'Стоп-лист',
          authority: 'MID'
        }
      }.freeze

      # European Union (EU) list types
      EU = {
        'consolidated-list' => {
          name: 'EU Consolidated List',
          authority: 'European Commission'
        }
      }.freeze

      # EU Vessels list types
      EU_VESSELS = {
        'vessel-sanctions-list' => {
          name: 'EU Vessel Sanctions List',
          authority: 'Denmark DMA'
        }
      }.freeze

      # United Kingdom (UK) list types
      UK = {
        'consolidated-list' => {
          name: 'UK Sanctions List',
          authority: 'OFSI'
        }
      }.freeze

      # United States (US) list types
      US = {
        'sdn-list' => {
          name: 'Specially Designated Nationals',
          authority: 'OFAC'
        },
        'entity-list' => {
          name: 'Entity List',
          authority: 'BIS'
        },
        'nonproliferation-sanctions' => {
          name: 'Nonproliferation Sanctions',
          authority: 'State Department'
        }
      }.freeze

      # Australia (AU) list types
      AU = {
        'consolidated-list' => {
          name: 'Australia Consolidated Sanctions List',
          authority: 'DFAT'
        }
      }.freeze

      # Canada (CA) list types
      CA = {
        'consolidated-list' => {
          name: 'Canada Consolidated Sanctions List',
          authority: 'Global Affairs Canada'
        }
      }.freeze

      # Switzerland (CH) list types
      CH = {
        'consolidated-list' => {
          name: 'Switzerland Sanctions List',
          authority: 'SECO'
        }
      }.freeze

      # Japan (JP) list types
      JP = {
        'end-user-list' => {
          name: 'Japan End User List',
          authority: 'METI'
        }
      }.freeze

      # New Zealand (NZ) list types
      NZ = {
        'consolidated-list' => {
          name: 'New Zealand Sanctions List',
          authority: 'MFAT'
        }
      }.freeze

      # Turkey (TR) list types
      TR = {
        'consolidated-list' => {
          name: 'Turkey Sanctions List',
          authority: 'HMB'
        }
      }.freeze

      # United Nations (UN) list types
      UN = {
        'consolidated-list' => {
          name: 'UN Security Council Consolidated List',
          authority: 'UN Security Council'
        }
      }.freeze

      # UN Vessels list types
      UN_VESSELS = {
        'vessel-sanctions-list' => {
          name: 'UN Vessel Sanctions List',
          authority: '1718 Committee'
        }
      }.freeze

      # World Bank (WB) list types
      WB = {
        'debarment-list' => {
          name: 'World Bank Debarment List',
          authority: 'World Bank'
        }
      }.freeze

      # Mapping of source codes to their list types.
      # Keys use the gem's underscored source codes
      # (Config::Defaults::ALL_SOURCES): eu_vessels, un_vessels.
      SOURCE_LIST_TYPES = {
        'cn' => CN,
        'ru' => RU,
        'eu' => EU,
        'eu_vessels' => EU_VESSELS,
        'uk' => UK,
        'us' => US,
        'au' => AU,
        'ca' => CA,
        'ch' => CH,
        'jp' => JP,
        'nz' => NZ,
        'tr' => TR,
        'un' => UN,
        'un_vessels' => UN_VESSELS,
        'wb' => WB
      }.freeze

      class << self
        # Get list types for a source. Hyphenated aliases (legacy
        # repo-derived codes like "eu-vessels") normalize to the
        # underscored contract codes.
        #
        # @param source_code [String] Source code (e.g., "cn", "ru")
        # @return [Hash, nil] List types hash or nil if source not found
        #
        def list_types_for(source_code)
          SOURCE_LIST_TYPES[source_code.to_s.downcase.tr('-', '_')]
        end

        # Get information about a specific list type.
        #
        # @param source_code [String] Source code
        # @param list_type [String] List type identifier
        # @return [Hash, nil] List type info or nil if not found
        #
        def get(source_code, list_type)
          list_types = list_types_for(source_code)
          return nil if list_types.nil?

          list_types[list_type.to_s.downcase]
        end

        # Check if a list type exists for a source.
        #
        # @param source_code [String] Source code
        # @param list_type [String] List type identifier
        # @return [Boolean]
        #
        def exists?(source_code, list_type)
          !get(source_code, list_type).nil?
        end

        # Get all known list types across all sources.
        #
        # @return [Array<String>] Unique list type identifiers
        #
        def all_list_types
          SOURCE_LIST_TYPES.values.flat_map(&:keys).uniq.sort
        end

        # Get the default list type for a source.
        #
        # @param source_code [String] Source code
        # @return [String, nil] Default list type or nil
        #
        def default_list_type(source_code)
          list_types = list_types_for(source_code)
          return nil if list_types.nil? || list_types.empty?

          list_types.keys.first
        end

        # Get all source codes.
        #
        # @return [Array<String>] Source codes
        #
        def all_sources
          SOURCE_LIST_TYPES.keys.sort
        end
      end
    end
  end
end
