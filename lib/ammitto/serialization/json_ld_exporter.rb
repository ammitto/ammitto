# frozen_string_literal: true

# JSON-LD Exporter for Ammitto Knowledge Graph
#
# Exports entities and their related data as JSON-LD documents
# suitable for website consumption and search engine indexing.
#
# @example
#   exporter = Ammitto::Serialization::JsonLdExporter.new
#   entity_jsonld = exporter.export_entity(entity_id)

require_relative '../ontology/json_ld_context'

module Ammitto
  module Serialization
    class JsonLdExporter
      attr_reader :context

      def initialize
        @context = Ontology::JsonLdContext.generate
      end

      # Export a single entity as JSON-LD
      def export_entity(entity_data, related_data = {})
        doc = {
          '@context' => context,
          '@id' => entity_data['id'],
          '@type' => map_type(entity_data['type'])
        }

        # Add core properties
        add_property(doc, 'source', entity_data['source'])
        add_property(doc, 'remarks', entity_data['remarks'])

        # Add names
        doc['names'] = related_data['names'].map { |n| export_name(n) } if related_data['names']&.any?

        # Add addresses
        doc['addresses'] = related_data['addresses'].map { |a| export_address(a) } if related_data['addresses']&.any?

        # Add identifiers
        if related_data['identifiers']&.any?
          doc['identifiers'] = related_data['identifiers'].map do |i|
            export_identifier(i)
          end
        end

        # Add type-specific properties
        case entity_data['type']
        when 'person'
          add_person_properties(doc, entity_data, related_data)
        when 'organization'
          add_organization_properties(doc, entity_data)
        when 'vessel'
          add_vessel_properties(doc, entity_data)
        end

        # Clean up nil values
        doc.compact!
      end

      # Export name as JSON-LD
      def export_name(name_data)
        {
          '@type' => 'Name',
          'full_name' => name_data['full_name'] || name_data['english'],
          'is_primary' => name_data['is_primary'],
          'script' => name_data['script'],
          'language' => name_data['language']
        }.compact
      end

      # Export address as JSON-LD
      def export_address(addr_data)
        doc = {
          '@type' => 'Address',
          'street' => addr_data['street'],
          'city' => addr_data['city'],
          'state' => addr_data['state'],
          'postal_code' => addr_data['postal_code']
        }

        # Country as reference
        if addr_data['country_code']
          doc['country'] = {
            '@id' => "https://www.ammitto.org/country/#{addr_data['country_code']}",
            'name' => addr_data['country_name']
          }
        end

        doc.compact
      end

      # Export identifier as JSON-LD
      def export_identifier(id_data)
        doc = {
          '@type' => 'Identifier',
          'type' => id_data['type'] || id_data['id_type'],
          'value' => id_data['value'] || id_data['id_number'],
          'issue_date' => id_data['issue_date'],
          'expiry_date' => id_data['expiry_date']
        }

        # Issuing country as reference
        if id_data['country_code']
          doc['issued_by'] = {
            '@id' => "https://www.ammitto.org/country/#{id_data['country_code']}"
          }
        end

        doc.compact
      end

      # Export entry as JSON-LD
      def export_entry(entry_data)
        doc = {
          '@context' => context,
          '@id' => entry_data['id'],
          '@type' => 'Entry',
          'status' => entry_data['status'],
          'listed_date' => entry_data['listed_date'],
          'delisted_date' => entry_data['delisted_date'],
          'measures' => entry_data['measures'],
          'remarks' => entry_data['remarks']
        }

        # Entity reference
        if entry_data['entity_id']
          doc['entity'] = {
            '@id' => entry_data['entity_id']
          }
        end

        # Authority reference
        if entry_data['authority_code']
          doc['authority'] = {
            '@id' => "https://www.ammitto.org/authority/#{entry_data['authority_code']}"
          }
        end

        # Regime reference
        if entry_data['regime_code']
          doc['regime'] = {
            '@id' => "https://www.ammitto.org/regime/#{entry_data['regime_code']}"
          }
        end

        doc.compact
      end

      # Export authority as JSON-LD
      def export_authority(auth_data)
        {
          '@context' => context,
          '@id' => "https://www.ammitto.org/authority/#{auth_data['code']}",
          '@type' => 'Authority',
          'code' => auth_data['code'],
          'name' => auth_data['name'],
          'country' => if auth_data['country_code']
                         {
                           '@id' => "https://www.ammitto.org/country/#{auth_data['country_code']}"
                         }
                       end,
          'url' => auth_data['url']
        }.compact
      end

      # Generate website data file
      def generate_website_data(entities, output_path)
        data = {
          '@context' => context,
          '@graph' => entities.map { |e| export_entity(e) }
        }

        File.write(output_path, JSON.pretty_generate(data))
      end

      private

      def map_type(type)
        case type
        when 'person' then 'Person'
        when 'organization' then 'Organization'
        when 'vessel' then 'Vessel'
        when 'aircraft' then 'Aircraft'
        else 'Entity'
        end
      end

      def add_property(doc, key, value)
        doc[key] = value unless value.nil?
      end

      def add_person_properties(doc, entity_data, related_data)
        # Birth info
        birth_info = related_data['birth_info'] || entity_data['birth_info'] || {}
        if birth_info.any?
          doc['birth_date'] = birth_info['date'] || birth_info['birth_date']
          if birth_info['city'] || birth_info['country']
            doc['birth_place'] =
              [birth_info['city'], birth_info['country']].compact.join(', ')
          end
        end

        # Death date
        doc['death_date'] = entity_data['death_date']

        # Gender
        doc['gender'] = entity_data['gender']

        # Nationalities
        return unless entity_data['nationalities']&.any?

        doc['nationalities'] = entity_data['nationalities'].map do |code|
          { '@id' => "https://www.ammitto.org/country/#{code}" }
        end
      end

      def add_organization_properties(doc, entity_data)
        doc['registration_number'] = entity_data['registration_number']
        doc['incorporation_country'] = entity_data['incorporation_country']
        doc['website'] = entity_data['website']
        doc['organization_type'] = entity_data['organization_type']
      end

      def add_vessel_properties(doc, entity_data)
        doc['imo_number'] = entity_data['imo_number'] || entity_data['imo']
        doc['mmsi_number'] = entity_data['mmsi_number'] || entity_data['mmsi']
        doc['call_sign'] = entity_data['call_sign']

        if entity_data['flag_state'] || entity_data['flag']
          doc['flag_state'] = {
            '@id' => "https://www.ammitto.org/country/#{entity_data['flag_state'] || entity_data['flag']}"
          }
        end

        doc['build_year'] = entity_data['build_year']
        doc['vessel_type'] = entity_data['vessel_type']
      end
    end
  end
end
