# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module Ammitto
  module Serialization
    # OntologyExporter exports ontology data for the ontology browser
    #
    # Creates JSON-LD files describing classes, properties, and their relationships
    # for display in the website ontology browser.
    #
    # @example Using the ontology exporter
    #   exporter = OntologyExporter.new
    #   exporter.export('./api/v1/ontology')
    #
    class OntologyExporter
      # Base URI for ontology terms
      BASE_URI = 'https://www.ammitto.org/ontology'

      # Context URL
      CONTEXT_URL = 'https://www.ammitto.org/ontology/context.jsonld'

      # Class definitions
      CLASSES = [
        {
          id: 'Entity',
          label: 'Entity',
          comment: 'Base class for all sanctionable entities',
          parent: nil,
          properties: %w[entityType names aliases hasSanctionEntry]
        },
        {
          id: 'PersonEntity',
          label: 'Person Entity',
          comment: 'A human individual subject to sanctions',
          parent: 'Entity',
          properties: %w[birthInfo nationalities documents gender]
        },
        {
          id: 'OrganizationEntity',
          label: 'Organization Entity',
          comment: 'A legal entity (company, government, etc.) subject to sanctions',
          parent: 'Entity',
          properties: %w[registration addresses businessType]
        },
        {
          id: 'VesselEntity',
          label: 'Vessel Entity',
          comment: 'A maritime vessel subject to sanctions',
          parent: 'Entity',
          properties: %w[imo mmsi flag tonnage callSign buildDate]
        },
        {
          id: 'AircraftEntity',
          label: 'Aircraft Entity',
          comment: 'An aircraft subject to sanctions',
          parent: 'Entity',
          properties: %w[registrationNumber manufacturer model serialNumber]
        },
        {
          id: 'SanctionEntry',
          label: 'Sanction Entry',
          comment: 'A sanction record linking an entity to its sanction details',
          parent: nil,
          properties: %w[entityId authority regime legalBases status listingDate measures announcement]
        },
        {
          id: 'Authority',
          label: 'Authority',
          comment: 'An issuing authority for sanctions (e.g., UN, EU, UK)',
          parent: nil,
          properties: %w[code name countryCode url]
        },
        {
          id: 'Announcement',
          label: 'Announcement',
          comment: 'A publication or list update from an authority',
          parent: nil,
          properties: %w[title number date effectiveDate issuingAuthority measures]
        },
        {
          id: 'SanctionRegime',
          label: 'Sanction Regime',
          comment: 'A sanctions regime (e.g., DPRK, Iran, Russia)',
          parent: nil,
          properties: %w[code name description]
        },
        {
          id: 'LegalInstrument',
          label: 'Legal Instrument',
          comment: 'A legal basis for sanctions (resolution, regulation, etc.)',
          parent: nil,
          properties: %w[identifier title type publicationDate url]
        },
        {
          id: 'SanctionsList',
          label: 'Sanctions List',
          comment: 'A specific sanctions list (e.g., EU Consolidated List, OFAC SDN)',
          parent: nil,
          properties: %w[name authority description listType url]
        },
        {
          id: 'Country',
          label: 'Country',
          comment: 'A country or territory (ISO 3166-1)',
          parent: nil,
          properties: %w[code name]
        },
        {
          id: 'Measure',
          label: 'Measure',
          comment: 'A specific sanctions measure (asset freeze, travel ban, etc.)',
          parent: nil,
          properties: %w[code name description]
        },
        {
          id: 'Name',
          label: 'Name',
          comment: 'A name variant for an entity',
          parent: nil,
          properties: %w[fullName lastName firstName middleName isPrimary script language]
        },
        {
          id: 'Address',
          label: 'Address',
          comment: 'A physical address',
          parent: nil,
          properties: %w[street city state postalCode country countryCode careOf]
        },
        {
          id: 'Identifier',
          label: 'Identifier',
          comment: 'An identifier document (passport, national ID, etc.)',
          parent: nil,
          properties: %w[type value country issuer issueDate expiryDate]
        },
        {
          id: 'BirthInfo',
          label: 'Birth Information',
          comment: 'Birth date and place information',
          parent: nil,
          properties: %w[date year place country circa]
        },
        {
          id: 'Nationality',
          label: 'Nationality',
          comment: 'A nationality or citizenship',
          parent: nil,
          properties: %w[countryCode country]
        }
      ].freeze

      # Property definitions
      PROPERTIES = [
        # Entity properties
        { id: 'entityType', label: 'Entity Type', comment: 'The type of entity', domain: 'Entity', range: 'string' },
        { id: 'names', label: 'Names', comment: 'Name variants for the entity', domain: 'Entity', range: 'Name',
          array: true },
        { id: 'aliases', label: 'Aliases', comment: 'Alternative names or aliases', domain: 'Entity', range: 'Name',
          array: true },
        { id: 'hasSanctionEntry', label: 'Has Sanction Entry', comment: 'Links to sanction record', domain: 'Entity',
          range: 'SanctionEntry', array: true },

        # PersonEntity properties
        { id: 'birthInfo', label: 'Birth Info', comment: 'Birth information', domain: 'PersonEntity',
          range: 'BirthInfo', array: true },
        { id: 'nationalities', label: 'Nationalities', comment: 'Nationalities', domain: 'PersonEntity',
          range: 'Nationality', array: true },
        { id: 'documents', label: 'Documents', comment: 'Identity documents', domain: 'PersonEntity',
          range: 'Identifier', array: true },
        { id: 'gender', label: 'Gender', comment: 'Gender', domain: 'PersonEntity', range: 'string' },

        # OrganizationEntity properties
        { id: 'registration', label: 'Registration', comment: 'Registration details', domain: 'OrganizationEntity',
          range: 'Registration' },
        { id: 'businessType', label: 'Business Type', comment: 'Type of business', domain: 'OrganizationEntity',
          range: 'string' },

        # VesselEntity properties
        { id: 'imo', label: 'IMO', comment: 'IMO number', domain: 'VesselEntity', range: 'string' },
        { id: 'mmsi', label: 'MMSI', comment: 'MMSI number', domain: 'VesselEntity', range: 'string' },
        { id: 'flag', label: 'Flag', comment: 'Flag state', domain: 'VesselEntity', range: 'Country' },
        { id: 'tonnage', label: 'Tonnage', comment: 'Gross tonnage', domain: 'VesselEntity', range: 'integer' },
        { id: 'callSign', label: 'Call Sign', comment: 'Radio call sign', domain: 'VesselEntity', range: 'string' },
        { id: 'buildDate', label: 'Build Date', comment: 'Date vessel was built', domain: 'VesselEntity',
          range: 'date' },

        # AircraftEntity properties
        { id: 'registrationNumber', label: 'Registration Number', comment: 'Aircraft registration',
          domain: 'AircraftEntity', range: 'string' },
        { id: 'manufacturer', label: 'Manufacturer', comment: 'Aircraft manufacturer', domain: 'AircraftEntity',
          range: 'string' },
        { id: 'model', label: 'Model', comment: 'Aircraft model', domain: 'AircraftEntity', range: 'string' },
        { id: 'serialNumber', label: 'Serial Number', comment: 'Aircraft serial number', domain: 'AircraftEntity',
          range: 'string' },

        # Address properties (shared)
        { id: 'addresses', label: 'Addresses', comment: 'Physical addresses', domain: 'Entity', range: 'Address',
          array: true },

        # SanctionEntry properties
        { id: 'entityId', label: 'Entity ID', comment: 'Reference to entity', domain: 'SanctionEntry',
          range: 'Entity' },
        { id: 'authority', label: 'Authority', comment: 'Issuing authority', domain: 'SanctionEntry',
          range: 'Authority' },
        { id: 'regime', label: 'Regime', comment: 'Sanctions regime', domain: 'SanctionEntry',
          range: 'SanctionRegime' },
        { id: 'legalBases', label: 'Legal Bases', comment: 'Legal instruments', domain: 'SanctionEntry',
          range: 'LegalInstrument', array: true },
        { id: 'status', label: 'Status', comment: 'Current status', domain: 'SanctionEntry', range: 'string' },
        { id: 'listingDate', label: 'Listing Date', comment: 'Date listed', domain: 'SanctionEntry', range: 'date' },
        { id: 'delistingDate', label: 'Delisting Date', comment: 'Date removed from list', domain: 'SanctionEntry',
          range: 'date' },
        { id: 'measures', label: 'Measures', comment: 'Sanctions measures applied', domain: 'SanctionEntry',
          range: 'Measure', array: true },
        { id: 'announcement', label: 'Announcement', comment: 'Source announcement', domain: 'SanctionEntry',
          range: 'Announcement' },

        # Authority properties
        { id: 'code', label: 'Code', comment: 'Unique code identifier', domain: 'Authority', range: 'string' },
        { id: 'name', label: 'Name', comment: 'Name', domain: 'Authority', range: 'string' },
        { id: 'countryCode', label: 'Country Code', comment: 'ISO country code', domain: 'Authority', range: 'string' },
        { id: 'url', label: 'URL', comment: 'Official website', domain: 'Authority', range: 'string' },

        # Announcement properties
        { id: 'title', label: 'Title', comment: 'Announcement title', domain: 'Announcement', range: 'string' },
        { id: 'number', label: 'Number', comment: 'Announcement number', domain: 'Announcement', range: 'string' },
        { id: 'date', label: 'Date', comment: 'Publication date', domain: 'Announcement', range: 'date' },
        { id: 'effectiveDate', label: 'Effective Date', comment: 'Date when effective', domain: 'Announcement',
          range: 'date' },
        { id: 'issuingAuthority', label: 'Issuing Authority', comment: 'Authority that issued', domain: 'Announcement',
          range: 'string' },

        # SanctionRegime properties
        { id: 'description', label: 'Description', comment: 'Description', domain: 'SanctionRegime', range: 'string' },

        # LegalInstrument properties
        { id: 'identifier', label: 'Identifier', comment: 'Instrument identifier', domain: 'LegalInstrument',
          range: 'string' },
        { id: 'type', label: 'Type', comment: 'Type', domain: 'LegalInstrument', range: 'string' },
        { id: 'publicationDate', label: 'Publication Date', comment: 'Date published', domain: 'LegalInstrument',
          range: 'date' },

        # SanctionsList properties
        { id: 'listType', label: 'List Type', comment: 'Type of sanctions list', domain: 'SanctionsList',
          range: 'string' },
        { id: 'authority', label: 'Authority', comment: 'Owning authority', domain: 'SanctionsList',
          range: 'Authority' },

        # Country properties
        { id: 'country', label: 'Country', comment: 'Country name', domain: 'Country', range: 'string' },

        # Name properties
        { id: 'fullName', label: 'Full Name', comment: 'Full name', domain: 'Name', range: 'string' },
        { id: 'lastName', label: 'Last Name', comment: 'Family name', domain: 'Name', range: 'string' },
        { id: 'firstName', label: 'First Name', comment: 'Given name', domain: 'Name', range: 'string' },
        { id: 'middleName', label: 'Middle Name', comment: 'Middle name', domain: 'Name', range: 'string' },
        { id: 'isPrimary', label: 'Is Primary', comment: 'Is primary name', domain: 'Name', range: 'boolean' },
        { id: 'script', label: 'Script', comment: 'Writing script (ISO 15924)', domain: 'Name', range: 'string' },
        { id: 'language', label: 'Language', comment: 'Language (ISO 639-1)', domain: 'Name', range: 'string' },

        # Address properties
        { id: 'street', label: 'Street', comment: 'Street address', domain: 'Address', range: 'string' },
        { id: 'city', label: 'City', comment: 'City', domain: 'Address', range: 'string' },
        { id: 'state', label: 'State', comment: 'State or province', domain: 'Address', range: 'string' },
        { id: 'postalCode', label: 'Postal Code', comment: 'Postal/ZIP code', domain: 'Address', range: 'string' },
        { id: 'careOf', label: 'Care Of', comment: 'c/o address', domain: 'Address', range: 'string' },

        # Identifier properties
        { id: 'value', label: 'Value', comment: 'Value', domain: 'Identifier', range: 'string' },
        { id: 'issuer', label: 'Issuer', comment: 'Issuing authority', domain: 'Identifier', range: 'string' },
        { id: 'issueDate', label: 'Issue Date', comment: 'Date issued', domain: 'Identifier', range: 'date' },
        { id: 'expiryDate', label: 'Expiry Date', comment: 'Expiry date', domain: 'Identifier', range: 'date' },

        # BirthInfo properties
        { id: 'year', label: 'Year', comment: 'Birth year', domain: 'BirthInfo', range: 'integer' },
        { id: 'place', label: 'Place', comment: 'Birth place', domain: 'BirthInfo', range: 'string' },
        { id: 'circa', label: 'Circa', comment: 'Approximate date', domain: 'BirthInfo', range: 'boolean' }
      ].freeze

      # Entity type info for hierarchy
      ENTITY_TYPES = {
        'person' => { name: 'Person', icon: 'user', color: '#3b82f6' },
        'organization' => { name: 'Organization', icon: 'building', color: '#10b981' },
        'vessel' => { name: 'Vessel', icon: 'ship', color: '#8b5cf6' },
        'aircraft' => { name: 'Aircraft', icon: 'plane', color: '#f59e0b' }
      }.freeze

      # Initialize with optional entity counts
      # @param entity_counts [Hash] counts by entity type
      def initialize(entity_counts = {})
        @entity_counts = entity_counts
      end

      # Set entity counts
      # @param counts [Hash] counts by entity type
      attr_writer :entity_counts

      # Export ontology data to output directory
      # @param output_dir [String] output directory path
      # @return [void]
      def export(output_dir)
        ontology_dir = File.join(output_dir, 'ontology')
        FileUtils.mkdir_p(ontology_dir)

        export_classes(ontology_dir)
        export_properties(ontology_dir)
        export_hierarchy(ontology_dir)
        export_examples(ontology_dir)

        puts "Exported ontology data to #{ontology_dir}"
      end

      private

      # Export classes.jsonld
      # @param dir [String] ontology directory
      def export_classes(dir)
        classes_graph = CLASSES.map do |cls|
          class_node = {
            '@id' => "#{BASE_URI}/#{cls[:id]}",
            '@type' => 'rdfs:Class',
            'label' => cls[:label],
            'comment' => cls[:comment]
          }
          class_node['subClassOf'] = "#{BASE_URI}/#{cls[:parent]}" if cls[:parent]
          class_node['properties'] = cls[:properties].map { |p| "#{BASE_URI}/#{p}" } if cls[:properties]
          class_node
        end

        data = {
          '@context' => CONTEXT_URL,
          '@graph' => classes_graph
        }

        File.write(File.join(dir, 'classes.jsonld'), JSON.pretty_generate(data))
      end

      # Export properties.jsonld
      # @param dir [String] ontology directory
      def export_properties(dir)
        properties_graph = PROPERTIES.map do |prop|
          property_node = {
            '@id' => "#{BASE_URI}/#{prop[:id]}",
            '@type' => 'rdf:Property',
            'label' => prop[:label],
            'comment' => prop[:comment]
          }
          property_node['domain'] = "#{BASE_URI}/#{prop[:domain]}" if prop[:domain]
          property_node['range'] = map_range(prop[:range])
          property_node['isArray'] = true if prop[:array]
          property_node
        end

        data = {
          '@context' => CONTEXT_URL,
          '@graph' => properties_graph
        }

        File.write(File.join(dir, 'properties.jsonld'), JSON.pretty_generate(data))
      end

      # Map range type to URI
      # @param range [String] range type
      # @return [String] URI or XSD type
      def map_range(range)
        case range
        when 'string', 'integer', 'date', 'boolean'
          "http://www.w3.org/2001/XMLSchema##{range}"
        else
          "#{BASE_URI}/#{range}"
        end
      end

      # Export hierarchy.json
      # @param dir [String] ontology directory
      def export_hierarchy(dir)
        hierarchy = {
          name: 'Entity',
          label: 'Entity',
          count: @entity_counts.values.sum,
          children: build_entity_type_hierarchy
        }

        # Add supporting classes
        supporting = [
          { name: 'SanctionEntry', label: 'Sanction Entry', icon: 'scroll-text', children: [] },
          { name: 'Authority', label: 'Authority', icon: 'building-2', children: [] },
          { name: 'Announcement', label: 'Announcement', icon: 'megaphone', children: [] },
          { name: 'SanctionRegime', label: 'Regime', icon: 'flag', children: [] },
          { name: 'LegalInstrument', label: 'Legal Instrument', icon: 'file-text', children: [] },
          { name: 'SanctionsList', label: 'Sanctions List', icon: 'list', children: [] },
          { name: 'Country', label: 'Country', icon: 'globe', children: [] },
          { name: 'Measure', label: 'Measure', icon: 'ban', children: [] },
          { name: 'Name', label: 'Name', icon: 'type', children: [] },
          { name: 'Address', label: 'Address', icon: 'map-pin', children: [] },
          { name: 'Identifier', label: 'Identifier', icon: 'id-card', children: [] },
          { name: 'BirthInfo', label: 'Birth Info', icon: 'cake', children: [] },
          { name: 'Nationality', label: 'Nationality', icon: 'passport', children: [] }
        ]

        full_hierarchy = {
          name: 'AmmittoOntology',
          label: 'Ammitto Ontology',
          children: [hierarchy] + supporting.map { |s| s.merge(count: 0) }
        }

        File.write(File.join(dir, 'hierarchy.json'), JSON.pretty_generate(full_hierarchy))
      end

      # Build entity type hierarchy with counts
      # @return [Array<Hash>] entity type nodes
      def build_entity_type_hierarchy
        ENTITY_TYPES.map do |code, info|
          {
            name: "#{code.capitalize}Entity",
            label: info[:name],
            code: code,
            count: @entity_counts[code] || 0,
            icon: info[:icon],
            color: info[:color],
            children: []
          }
        end
      end

      # Export example files
      # @param dir [String] ontology directory
      def export_examples(dir)
        examples_dir = File.join(dir, 'examples')
        FileUtils.mkdir_p(examples_dir)

        export_person_example(examples_dir)
        export_organization_example(examples_dir)
        export_vessel_example(examples_dir)
      end

      # Export person example
      # @param dir [String] examples directory
      def export_person_example(dir)
        example = {
          '@context' => CONTEXT_URL,
          '@id' => 'https://www.ammitto.org/entity/example/person',
          '@type' => 'PersonEntity',
          'entityType' => 'person',
          'names' => [
            { '@type' => 'Name', 'fullName' => 'DOE, John', 'isPrimary' => true }
          ],
          'birthInfo' => [
            { '@type' => 'BirthInfo', 'date' => '1970-01-15', 'countryCode' => 'XX' }
          ],
          'nationalities' => [
            { '@type' => 'Nationality', 'countryCode' => 'XX' }
          ],
          'hasSanctionEntry' => [
            { '@id' => 'https://www.ammitto.org/entry/example/person' }
          ]
        }

        File.write(File.join(dir, 'person.jsonld'), JSON.pretty_generate(example))
      end

      # Export organization example
      # @param dir [String] examples directory
      def export_organization_example(dir)
        example = {
          '@context' => CONTEXT_URL,
          '@id' => 'https://www.ammitto.org/entity/example/organization',
          '@type' => 'OrganizationEntity',
          'entityType' => 'organization',
          'names' => [
            { '@type' => 'Name', 'fullName' => 'EXAMPLE CORPORATION LTD', 'isPrimary' => true }
          ],
          'addresses' => [
            { '@type' => 'Address', 'street' => '123 Example St', 'city' => 'Example City', 'countryCode' => 'XX' }
          ],
          'hasSanctionEntry' => [
            { '@id' => 'https://www.ammitto.org/entry/example/organization' }
          ]
        }

        File.write(File.join(dir, 'organization.jsonld'), JSON.pretty_generate(example))
      end

      # Export vessel example
      # @param dir [String] examples directory
      def export_vessel_example(dir)
        example = {
          '@context' => CONTEXT_URL,
          '@id' => 'https://www.ammitto.org/entity/example/vessel',
          '@type' => 'VesselEntity',
          'entityType' => 'vessel',
          'names' => [
            { '@type' => 'Name', 'fullName' => 'EXAMPLE VESSEL', 'isPrimary' => true }
          ],
          'imo' => '1234567',
          'mmsi' => '123456789',
          'flag' => 'Example Flag State',
          'tonnage' => 50_000,
          'callSign' => 'ABCD1',
          'hasSanctionEntry' => [
            { '@id' => 'https://www.ammitto.org/entry/example/vessel' }
          ]
        }

        File.write(File.join(dir, 'vessel.jsonld'), JSON.pretty_generate(example))
      end
    end
  end
end
