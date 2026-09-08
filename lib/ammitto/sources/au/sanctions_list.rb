# frozen_string_literal: true

require 'lutaml/model'
require 'csv'
require_relative 'base_entity'
require_relative 'entity_type'
require_relative 'individual'
require_relative 'organization'
require_relative 'vessel'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Collection of all sanctioned entities from the CSV
      class SanctionsList < Lutaml::Model::Serializable
        attribute :individuals, Individual, collection: true
        attribute :organizations, Organization, collection: true
        attribute :vessels, Vessel, collection: true

        # Module-level method for parse_base_reference
        def self.parse_base_reference(ref)
          BaseEntity.parse_base_reference(ref)
        end

        # Parse from CSV content
        # @param csv_content [String] CSV content
        # @return [SanctionsList]
        def self.from_csv(csv_content)
          list = new(individuals: [], organizations: [], vessels: [])

          # Track entities by base reference to merge rows
          individuals_map = {}
          organizations_map = {}
          vessels_map = {}

          CSV.parse(csv_content, headers: true) do |row|
            next unless row['Reference']

            entity_type = EntityType.from_csv(row['Type'])
            base_ref = parse_base_reference(row['Reference'])

            case entity_type
            when EntityType::INDIVIDUAL
              if individuals_map[base_ref]
                individuals_map[base_ref].merge_row(row)
              else
                entity = Individual.from_csv_row(row)
                individuals_map[base_ref] = entity
                list.individuals << entity
              end
            when EntityType::ORGANIZATION
              if organizations_map[base_ref]
                organizations_map[base_ref].merge_row(row)
              else
                entity = Organization.from_csv_row(row)
                organizations_map[base_ref] = entity
                list.organizations << entity
              end
            when EntityType::VESSEL
              if vessels_map[base_ref]
                vessels_map[base_ref].merge_row(row)
              else
                entity = Vessel.from_csv_row(row)
                vessels_map[base_ref] = entity
                list.vessels << entity
              end
            end
          end

          list
        end

        # Parse from XLSX file path
        # @param xlsx_path [String] path to XLSX file
        # @return [SanctionsList]
        def self.from_xlsx(xlsx_path)
          require 'roo'

          list = new(individuals: [], organizations: [], vessels: [])

          # Track entities by base reference to merge rows
          individuals_map = {}
          organizations_map = {}
          vessels_map = {}

          xlsx = Roo::Excelx.new(xlsx_path)
          sheet = xlsx.sheet(0)

          # Get headers from first row
          headers = sheet.row(1).map(&:to_s)

          (2..sheet.last_row).each do |row_num|
            values = sheet.row(row_num)

            # Build row hash
            row = {}
            headers.each_with_index do |header, idx|
              row[header] = values[idx]&.to_s
            end

            next unless row['Reference'] && !row['Reference'].strip.empty?

            entity_type = EntityType.from_csv(row['Type'])
            base_ref = parse_base_reference(row['Reference'])

            case entity_type
            when EntityType::INDIVIDUAL
              if individuals_map[base_ref]
                individuals_map[base_ref].merge_row(row)
              else
                entity = Individual.from_csv_row(row)
                individuals_map[base_ref] = entity
                list.individuals << entity
              end
            when EntityType::ORGANIZATION
              if organizations_map[base_ref]
                organizations_map[base_ref].merge_row(row)
              else
                entity = Organization.from_csv_row(row)
                organizations_map[base_ref] = entity
                list.organizations << entity
              end
            when EntityType::VESSEL
              if vessels_map[base_ref]
                vessels_map[base_ref].merge_row(row)
              else
                entity = Vessel.from_csv_row(row)
                vessels_map[base_ref] = entity
                list.vessels << entity
              end
            end
          end

          list
        end

        def all_entities
          individuals + organizations + vessels
        end

        def count
          individuals.size + organizations.size + vessels.size
        end

        def count_by_regime
          all_entities.group_by { |e| e.sanction&.committees }
                      .transform_values(&:count)
        end

        def count_by_effect
          counts = Hash.new(0)
          all_entities.each do |entity|
            entity.sanction&.effects&.each do |effect|
              counts[effect] += 1
            end
          end
          counts
        end
      end
    end
  end
end
