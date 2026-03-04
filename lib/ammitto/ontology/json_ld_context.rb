# frozen_string_literal: true

# JSON-LD Context for Ammitto Knowledge Graph
#
# This module provides JSON-LD context generation from the ontology.
# The context maps ontology properties to semantic web vocabularies.
#
# @example
#   context = Ammitto::Ontology::JsonLdContext.generate
#   # => { "@vocab" => "...", "Person" => "schema:Person", ... }

module Ammitto
  module Ontology
    module JsonLdContext
      # Base namespace for Ammitto ontology
      ONTOLOGY_NS = 'https://www.ammitto.org/ontology/'

      # External vocabularies
      VOCABULARIES = {
        schema: 'http://schema.org/',
        xsd: 'http://www.w3.org/2001/XMLSchema#',
        rdfs: 'http://www.w3.org/2000/01/rdf-schema#',
        skos: 'http://www.w3.org/2004/02/skos/core#'
      }.freeze

      # Class mappings to Schema.org
      CLASS_MAPPINGS = {
        'Entity' => 'schema:Thing',
        'Person' => 'schema:Person',
        'Organization' => 'schema:Organization',
        'Vessel' => 'schema:Vehicle',
        'Aircraft' => 'schema:Vehicle',
        'Name' => 'schema:Thing',
        'Address' => 'schema:PostalAddress',
        'Identifier' => 'schema:PropertyValue',
        'Entry' => 'schema:Thing',
        'Authority' => 'schema:Organization',
        'Country' => 'schema:Country',
        'Regime' => 'schema:Thing',
        'Announcement' => 'schema:NewsArticle',
        'LegalInstrument' => 'schema:Legislation'
      }.freeze

      # Property mappings to Schema.org
      PROPERTY_MAPPINGS = {
        # Core properties
        'id' => '@id',
        'type' => '@type',

        # Names
        'name' => 'schema:name',
        'full_name' => 'schema:name',
        'names' => { '@id' => 'hasName', '@container' => '@set' },
        'is_primary' => 'schema:isPrimary',

        # Address
        'street' => 'schema:streetAddress',
        'city' => 'schema:addressLocality',
        'state' => 'schema:addressRegion',
        'postal_code' => 'schema:postalCode',
        'country' => 'schema:addressCountry',
        'addresses' => { '@id' => 'hasAddress', '@container' => '@set' },

        # Identifiers
        'identifier' => 'schema:identifier',
        'identifiers' => { '@id' => 'hasIdentifier', '@container' => '@set' },
        'value' => 'schema:value',
        'issue_date' => { '@id' => 'schema:dateIssued', '@type' => 'xsd:date' },
        'expiry_date' => { '@id' => 'expiryDate', '@type' => 'xsd:date' },

        # Person properties
        'birth_date' => { '@id' => 'schema:birthDate', '@type' => 'xsd:date' },
        'birth_place' => 'schema:birthPlace',
        'death_date' => { '@id' => 'schema:deathDate', '@type' => 'xsd:date' },
        'gender' => 'schema:gender',
        'nationality' => 'schema:nationality',
        'nationalities' => { '@id' => 'schema:nationality', '@container' => '@set' },

        # Organization properties
        'registration_number' => 'schema:taxID',
        'incorporation_country' => 'schema:foundingLocation',
        'website' => 'schema:url',

        # Vessel properties
        'imo_number' => 'schema:serialNumber',
        'flag_state' => 'schema:flag',

        # Sanction properties
        'status' => 'schema:status',
        'listed_date' => { '@id' => 'listedDate', '@type' => 'xsd:date' },
        'delisted_date' => { '@id' => 'delistedDate', '@type' => 'xsd:date' },
        'measures' => 'schema:description',
        'remarks' => 'schema:description',

        # Relationships
        'entity' => { '@id' => 'forEntity', '@type' => '@id' },
        'authority' => { '@id' => 'listedBy', '@type' => '@id' },
        'regime' => { '@id' => 'underRegime', '@type' => '@id' },
        'announcement' => { '@id' => 'publishedIn', '@type' => '@id' },

        # Source/reference
        'source' => 'schema:sourceOrganization',
        'reference_number' => 'schema:identifier',
        'url' => 'schema:url'
      }.freeze

      # Generate the full JSON-LD context
      def self.generate
        context = {
          '@vocab' => ONTOLOGY_NS
        }

        # Add vocabulary prefixes
        VOCABULARIES.each do |prefix, uri|
          context[prefix.to_s] = uri
        end

        # Add class mappings
        CLASS_MAPPINGS.each do |local, mapped|
          context[local] = mapped
        end

        # Add property mappings
        PROPERTY_MAPPINGS.each do |prop, mapping|
          context[prop] = mapping
        end

        context
      end

      # Get JSON-LD @type for a class
      def self.type_for(class_name)
        CLASS_MAPPINGS[class_name] || class_name
      end

      # Get property mapping
      def self.property_mapping(prop_name)
        PROPERTY_MAPPINGS[prop_name] || prop_name
      end
    end
  end
end
