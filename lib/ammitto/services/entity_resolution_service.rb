# frozen_string_literal: true

require 'set'
require_relative '../ontology/entities/harmonized_entity'
require_relative '../ontology/value_objects/harmonized_name'
require_relative '../ontology/value_objects/harmonized_attributes'
require_relative '../ontology/value_objects/source_provenance'
require_relative '../ontology/types'

module Ammitto
  module Services
    # EntityResolutionService handles entity deduplication and harmonization
    # across multiple sanctions sources.
    #
    # This service implements entity resolution (also known as record linkage
    # or deduplication) to identify when entities from different sources
    # represent the same real-world entity.
    #
    # Key features:
    # - Fuzzy name matching using multiple algorithms
    # - Type conflict detection and resolution
    # - Provenance tracking for all merged data
    # - Confidence scoring for matches
    #
    # @example Basic usage
    #   resolver = EntityResolutionService.new
    #
    #   # Add entities from different sources
    #   resolver.add_entity(uk_entity, source: :uk)
    #   resolver.add_entity(eu_entity, source: :eu)
    #   resolver.add_entity(un_entity, source: :un)
    #
    #   # Find matches and create harmonized entities
    #   harmonized = resolver.resolve
    #
    class EntityResolutionService
      # Match confidence threshold for automatic matching
      AUTO_MATCH_THRESHOLD = 0.85

      # Match confidence threshold for review queue
      REVIEW_THRESHOLD = 0.70

      # Entity type weights for conflict resolution
      TYPE_WEIGHTS = {
        person: 1.0,
        organization: 1.0,
        vessel: 1.5, # Vessels have unique identifiers (IMO)
        aircraft: 1.5 # Aircraft have unique identifiers
      }.freeze

      # Initialize the resolution service
      # @param auto_match_threshold [Float] Confidence threshold for auto-matching
      # @param review_threshold [Float] Confidence threshold for review queue
      def initialize(auto_match_threshold: AUTO_MATCH_THRESHOLD,
                     review_threshold: REVIEW_THRESHOLD)
        @auto_match_threshold = auto_match_threshold
        @review_threshold = review_threshold
        @entities = []
        @source_codes = Set.new
      end

      # Add an entity to be resolved
      # @param entity [Hash, Entity] The source entity
      # @param source_code [String] The source code (uk, eu, un, etc.)
      # @return [void]
      def add_entity(entity, source_code:)
        @entities << {
          entity: entity,
          source_code: source_code.to_s.downcase
        }
        @source_codes << source_code.to_s.downcase
      end

      # Add multiple entities from a source
      # @param entities [Array<Hash, Entity>] The source entities
      # @param source_code [String] The source code
      # @return [void]
      def add_entities(entities, source_code:)
        entities.each { |e| add_entity(e, source_code: source_code) }
      end

      # Resolve entities into harmonized entities
      # @return [Array<HarmonizedEntity>] The harmonized entities
      def resolve
        clusters = cluster_entities
        clusters.map { |cluster| create_harmonized_entity(cluster) }
      end

      # Find potential matches for a specific entity
      # @param entity [Hash, Entity] The entity to match
      # @param source_code [String] The source code
      # @return [Array<Hash>] Potential matches with confidence scores
      def find_matches(entity, source_code:)
        matches = []
        entity_names = extract_names(entity)
        entity_type = extract_type(entity)

        @entities.each do |candidate|
          next if candidate[:source_code] == source_code.to_s.downcase

          confidence = calculate_match_confidence(
            entity_names: entity_names,
            entity_type: entity_type,
            candidate_names: extract_names(candidate[:entity]),
            candidate_type: extract_type(candidate[:entity])
          )

          next unless confidence >= @review_threshold

          matches << {
            entity: candidate[:entity],
            source_code: candidate[:source_code],
            confidence: confidence
          }
        end

        matches.sort_by { |m| -m[:confidence] }
      end

      private

      # Cluster entities that represent the same real-world entity
      # @return [Array<Array<Hash>>] Clusters of matching entities
      def cluster_entities
        clusters = []
        assigned = Set.new

        @entities.each_with_index do |entity_data, idx|
          next if assigned.include?(idx)

          # Start a new cluster with this entity
          cluster = [entity_data]
          assigned << idx

          # Find all matching entities
          entity_names = extract_names(entity_data[:entity])
          entity_type = extract_type(entity_data[:entity])

          @entities.each_with_index do |candidate, cidx|
            next if assigned.include?(cidx)

            confidence = calculate_match_confidence(
              entity_names: entity_names,
              entity_type: entity_type,
              candidate_names: extract_names(candidate[:entity]),
              candidate_type: extract_type(candidate[:entity])
            )

            if confidence >= @auto_match_threshold
              cluster << candidate
              assigned << cidx
            end
          end

          clusters << cluster
        end

        clusters
      end

      # Create a harmonized entity from a cluster of matching entities
      # @param cluster [Array<Hash>] The cluster of matching entities
      # @return [HarmonizedEntity] The harmonized entity
      def create_harmonized_entity(cluster)
        # Generate canonical ID
        canonical_id = generate_canonical_id(cluster)

        # Determine harmonized entity type
        type_info = resolve_entity_type(cluster)

        # Aggregate names with provenance
        harmonized_names = aggregate_names(cluster)

        # Aggregate other attributes
        birth_info = aggregate_birth_info(cluster)
        nationalities = aggregate_nationalities(cluster)
        addresses = aggregate_addresses(cluster)
        identifications = aggregate_identifications(cluster)

        # Create source entity references
        source_refs = cluster.map do |item|
          entity = item[:entity]
          Ontology::ValueObjects::SourceEntityReference.new(
            iri: entity['id'] || entity[:id],
            source_code: item[:source_code],
            original_type: extract_type(entity).to_s,
            type_matches_harmonized: extract_type(entity).to_s == type_info[:type].to_s,
            match_confidence: 1.0 # Within a cluster, all entities match
          )
        end

        # Determine review status
        review_status = determine_review_status(type_info, cluster)

        Ontology::Entities::HarmonizedEntity.new(
          id: canonical_id,
          entity_type: type_info[:type].to_s,
          type_confidence: type_info[:confidence],
          type_conflict: type_info[:conflict],
          type_conflict_sources: type_info[:conflict_sources],
          names: harmonized_names,
          birth_info: birth_info,
          nationalities: nationalities,
          addresses: addresses,
          identifications: identifications,
          source_entities: source_refs,
          review_status: review_status
        )
      end

      # Generate a canonical ID for a harmonized entity
      # @param cluster [Array<Hash>] The cluster
      # @return [String] The canonical IRI
      def generate_canonical_id(cluster)
        # Use the entity ID from the most authoritative source
        # Priority: UN > EU > UK > US > others
        priority = %w[un eu uk us ca au nz jp ru tr ch wb]

        sorted = cluster.sort_by do |item|
          priority.index(item[:source_code]) || 100
        end

        primary = sorted.first
        primary_id = primary[:entity]['id'] || primary[:entity][:id]

        # Convert source-specific IRI to canonical IRI
        # e.g., https://www.ammitto.org/entity/uk/xxx -> https://www.ammitto.org/entity/canonical/xxx
        local_id = primary_id.gsub(%r{^https://www\.ammitto\.org/entity/[^/]+/}, '')
        "https://www.ammitto.org/entity/canonical/#{local_id}"
      end

      # Resolve entity type from cluster
      # @param cluster [Array<Hash>] The cluster
      # @return [Hash] { type:, confidence:, conflict:, conflict_sources: }
      def resolve_entity_type(cluster)
        type_counts = Hash.new(0)
        type_sources = Hash.new { |h, k| h[k] = [] }

        cluster.each do |item|
          entity_type = extract_type(item[:entity])
          type_counts[entity_type] += 1
          type_sources[entity_type] << item[:source_code]
        end

        # Find majority type
        majority_type = type_counts.max_by { |_, count| count }

        {
          type: majority_type&.first || :person,
          confidence: majority_type ? (majority_type.last.to_f / cluster.length) : 0.0,
          conflict: type_counts.keys.length > 1,
          conflict_sources: type_sources.reject { |k, _| k == majority_type&.first }.values.flatten
        }
      end

      # Aggregate names from all entities in cluster
      # @param cluster [Array<Hash>] The cluster
      # @return [Array<HarmonizedName>]
      def aggregate_names(cluster)
        names_map = {} # full_name -> HarmonizedName

        cluster.each do |item|
          entity = item[:entity]
          source_code = item[:source_code]
          entity_iri = entity['id'] || entity[:id]

          names = entity['names'] || entity[:names] || []
          names.each do |name|
            full_name = name['full_name'] || name[:full_name]
            next unless full_name

            script = name['script'] || name[:script] ||
                     Ontology::Types.detect_script(full_name).to_s

            is_primary = name['is_primary'] || name[:is_primary] || false

            if names_map[full_name]
              # Add source to existing name
              names_map[full_name].sources << Ontology::ValueObjects::SourceProvenance.new(
                source_code: source_code,
                source_entity_iri: entity_iri,
                match_confidence: 1.0,
                contributed_at: Time.now
              )
              # Upgrade to primary if any source says it's primary
              names_map[full_name].is_primary = true if is_primary
            else
              # Create new name
              names_map[full_name] = Ontology::ValueObjects::HarmonizedName.new(
                full_name: full_name,
                script: script,
                is_primary: is_primary,
                sources: [
                  Ontology::ValueObjects::SourceProvenance.new(
                    source_code: source_code,
                    source_entity_iri: entity_iri,
                    match_confidence: 1.0,
                    contributed_at: Time.now
                  )
                ]
              )
            end
          end
        end

        # Ensure exactly one primary name
        names = names_map.values
        unless names.any?(&:primary?)
          first_name = names.first
          first_name&.is_primary = true
        end

        names
      end

      # Aggregate birth info from cluster
      # @param cluster [Array<Hash>] The cluster
      # @return [Array<HarmonizedBirthInfo>]
      def aggregate_birth_info(cluster)
        birth_map = {} # key -> HarmonizedBirthInfo

        cluster.each do |item|
          entity = item[:entity]
          source_code = item[:source_code]
          entity_iri = entity['id'] || entity[:id]

          birth_infos = entity['birth_info'] || entity[:birth_info] || []
          birth_infos = [birth_infos] unless birth_infos.is_a?(Array)

          birth_infos.each do |birth|
            next unless birth

            key = birth_key(birth)
            provenance = Ontology::ValueObjects::SourceProvenance.new(
              source_code: source_code,
              source_entity_iri: entity_iri,
              match_confidence: 1.0,
              contributed_at: Time.now
            )

            if birth_map[key]
              birth_map[key].sources << provenance
            else
              birth_map[key] = Ontology::ValueObjects::HarmonizedBirthInfo.new(
                date: birth['date'] || birth[:date],
                year: birth['year'] || birth[:year],
                circa: birth['circa'] || birth[:circa] || false,
                city: birth['city'] || birth[:city],
                region: birth['region'] || birth[:region],
                country: birth['country'] || birth[:country],
                country_iso_code: birth['country_iso_code'] || birth[:country_iso_code],
                sources: [provenance]
              )
            end
          end
        end

        birth_map.values
      end

      # Aggregate nationalities from cluster
      # @param cluster [Array<Hash>] The cluster
      # @return [Array<HarmonizedNationality>]
      def aggregate_nationalities(cluster)
        nat_map = {}

        cluster.each do |item|
          entity = item[:entity]
          source_code = item[:source_code]
          entity_iri = entity['id'] || entity[:id]

          nationalities = entity['nationalities'] || entity[:nationalities] || []
          nationalities = [nationalities] unless nationalities.is_a?(Array)

          nationalities.each do |nat|
            country = nat.is_a?(Hash) ? (nat['country'] || nat[:country]) : nat
            next unless country

            key = country.to_s.downcase
            provenance = Ontology::ValueObjects::SourceProvenance.new(
              source_code: source_code,
              source_entity_iri: entity_iri,
              match_confidence: 1.0,
              contributed_at: Time.now
            )

            if nat_map[key]
              nat_map[key].sources << provenance
            else
              nat_map[key] = Ontology::ValueObjects::HarmonizedNationality.new(
                country: country,
                country_iso_code: nat.is_a?(Hash) ? (nat['country_iso_code'] || nat[:country_iso_code]) : nil,
                sources: [provenance]
              )
            end
          end
        end

        nat_map.values
      end

      # Aggregate addresses from cluster
      # @param cluster [Array<Hash>] The cluster
      # @return [Array<HarmonizedAddress>]
      def aggregate_addresses(cluster)
        addr_map = {}

        cluster.each do |item|
          entity = item[:entity]
          source_code = item[:source_code]
          entity_iri = entity['id'] || entity[:id]

          addresses = entity['addresses'] || entity[:addresses] || []
          addresses = [addresses] unless addresses.is_a?(Array)

          addresses.each do |addr|
            next unless addr

            key = address_key(addr)
            provenance = Ontology::ValueObjects::SourceProvenance.new(
              source_code: source_code,
              source_entity_iri: entity_iri,
              match_confidence: 1.0,
              contributed_at: Time.now
            )

            if addr_map[key]
              addr_map[key].sources << provenance
            else
              addr_map[key] = Ontology::ValueObjects::HarmonizedAddress.new(
                street: addr['street'] || addr[:street],
                city: addr['city'] || addr[:city],
                state: addr['state'] || addr[:state],
                country: addr['country'] || addr[:country],
                country_iso_code: addr['country_iso_code'] || addr[:country_iso_code],
                postal_code: addr['postal_code'] || addr[:postal_code],
                sources: [provenance]
              )
            end
          end
        end

        addr_map.values
      end

      # Aggregate identifications from cluster
      # @param cluster [Array<Hash>] The cluster
      # @return [Array<HarmonizedIdentification>]
      def aggregate_identifications(cluster)
        id_map = {}

        cluster.each do |item|
          entity = item[:entity]
          source_code = item[:source_code]
          entity_iri = entity['id'] || entity[:id]

          ids = entity['identifications'] || entity[:identifications] ||
                entity['identifiers'] || entity[:identifiers] || []
          ids = [ids] unless ids.is_a?(Array)

          ids.each do |id|
            next unless id

            number = id['number'] || id[:number] || id['value'] || id[:value]
            next unless number

            key = "#{id['type'] || id[:type]}-#{number}"
            provenance = Ontology::ValueObjects::SourceProvenance.new(
              source_code: source_code,
              source_entity_iri: entity_iri,
              match_confidence: 1.0,
              contributed_at: Time.now
            )

            if id_map[key]
              id_map[key].sources << provenance
            else
              id_map[key] = Ontology::ValueObjects::HarmonizedIdentification.new(
                type: id['type'] || id[:type],
                document_type: id['document_type'] || id[:document_type],
                number: number,
                issuing_country: id['issuing_country'] || id[:issuing_country],
                note: id['note'] || id[:note],
                sources: [provenance]
              )
            end
          end
        end

        id_map.values
      end

      # Determine review status for harmonized entity
      # @param type_info [Hash] Type resolution info
      # @param cluster [Array<Hash>] The cluster
      # @return [Symbol]
      def determine_review_status(type_info, cluster)
        return :disputed if type_info[:confidence] < 0.6
        return :pending_review if type_info[:conflict]
        return :pending_review if cluster.length > 5 # Many sources, complex merge

        :auto_approved
      end

      # Calculate match confidence between two entities
      # @param entity_names [Array<String>] Names from first entity
      # @param entity_type [Symbol] Type of first entity
      # @param candidate_names [Array<String>] Names from candidate
      # @param candidate_type [Symbol] Type of candidate
      # @return [Float] Confidence score (0.0-1.0)
      def calculate_match_confidence(entity_names:, entity_type:, candidate_names:, candidate_type:)
        # Name similarity score (0.0-1.0)
        name_score = calculate_name_similarity(entity_names, candidate_names)

        # Type match bonus/penalty
        type_score = entity_type == candidate_type ? 1.0 : 0.7

        # Weighted combination
        # Names are the primary matching criterion
        (name_score * 0.8) + (type_score * 0.2)
      end

      # Calculate name similarity between two name sets
      # @param names1 [Array<String>] First name set
      # @param names2 [Array<String>] Second name set
      # @return [Float] Similarity score (0.0-1.0)
      def calculate_name_similarity(names1, names2)
        return 0.0 if names1.empty? || names2.empty?

        # Find best matching pair
        best_score = 0.0
        names1.each do |n1|
          names2.each do |n2|
            score = string_similarity(n1, n2)
            best_score = [best_score, score].max
          end
        end

        best_score
      end

      # Calculate string similarity using multiple methods
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @return [Float] Similarity score (0.0-1.0)
      def string_similarity(str1, str2)
        return 1.0 if str1.nil? && str2.nil?
        return 0.0 if str1.nil? || str2.nil?

        s1 = normalize_name(str1)
        s2 = normalize_name(str2)

        return 1.0 if s1 == s2
        return 0.0 if s1.empty? || s2.empty?

        # Exact match
        return 1.0 if s1 == s2

        # Jaccard similarity on words
        words1 = s1.split(/\s+/)
        words2 = s2.split(/\s+/)

        intersection = (words1 & words2).length
        union = (words1 | words2).length

        jaccard = union.positive? ? intersection.to_f / union : 0.0

        # Levenshtein-based similarity
        lev = levenshtein_similarity(s1, s2)

        # Take maximum of methods
        [jaccard, lev].max
      end

      # Normalize a name for comparison
      # @param name [String] The name
      # @return [String] Normalized name
      def normalize_name(name)
        return '' if name.nil?

        name.to_s
            .upcase
            .gsub(/[^\p{L}\p{N}\s]/, '') # Keep only letters, numbers, spaces
            .gsub(/\s+/, ' ') # Normalize whitespace
            .strip
      end

      # Calculate Levenshtein-based similarity
      # @param s1 [String] First string
      # @param s2 [String] Second string
      # @return [Float] Similarity (0.0-1.0)
      def levenshtein_similarity(s1, s2)
        distance = levenshtein_distance(s1, s2)
        max_len = [s1.length, s2.length].max
        return 1.0 if max_len.zero?

        1.0 - (distance.to_f / max_len)
      end

      # Calculate Levenshtein distance
      # @param s1 [String] First string
      # @param s2 [String] Second string
      # @return [Integer] Edit distance
      def levenshtein_distance(s1, s2)
        return s2.length if s1.empty?
        return s1.length if s2.empty?

        matrix = Array.new(s1.length + 1) { Array.new(s2.length + 1, 0) }

        (0..s1.length).each { |i| matrix[i][0] = i }
        (0..s2.length).each { |j| matrix[0][j] = j }

        (1..s1.length).each do |i|
          (1..s2.length).each do |j|
            cost = s1[i - 1] == s2[j - 1] ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,      # deletion
              matrix[i][j - 1] + 1,      # insertion
              matrix[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        matrix[s1.length][s2.length]
      end

      # Helper methods

      def extract_names(entity)
        names = entity['names'] || entity[:names] || []
        names.map { |n| n['full_name'] || n[:full_name] }.compact
      end

      def extract_type(entity)
        type = entity['entity_type'] || entity[:entity_type] || entity['type'] || entity[:type]
        type&.to_sym || :person
      end

      def birth_key(birth)
        [
          birth['date'] || birth[:date],
          birth['year'] || birth[:year],
          birth['city'] || birth[:city],
          birth['country'] || birth[:country]
        ].compact.join('-')
      end

      def address_key(addr)
        [
          addr['street'] || addr[:street],
          addr['city'] || addr[:city],
          addr['country'] || addr[:country]
        ].compact.join('-')
      end
    end
  end
end
