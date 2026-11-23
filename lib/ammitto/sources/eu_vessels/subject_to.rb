# frozen_string_literal: true

require_relative '../../error'
require_relative '../../logger'

module Ammitto
  module Sources
    module EuVessels
      # The legal basis and measures one "Subject to" cell of the DMA
      # workbook states, e.g. "Article 3s (Council Regulation 833/2014)" or
      # "De-registration + Port entry ban (Council Regulation 2017/1509)".
      #
      # The workbook mixes EU regimes: Russia, DPRK and Libya, each with
      # the measure DMA names. Publishing one fixed pair of effects for all
      # of them stated measures the source does not. Unfamiliar vocabulary
      # is preserved and flagged for review without inferring legal effects;
      # malformed cells still stop the harvest.
      class SubjectTo
        CITATION = %r{
          \bCouncil[[:space:]]+Regulation
          (?:[[:space:]]+\(EU\))?(?:[[:space:]]+No\.?)?
          [[:space:]]+(?<regulation>\d+/\d+)\b
        }ix
        CELL = /\A(?<measures>.+?)[[:space:]]+\((?<citation>#{CITATION})\)\z/im

        # Regime codes and names match the EU consolidated list source, so
        # an entry from either source links to the same regime node.
        REGULATIONS = {
          '833/2014' => {
            regime: { code: 'RUSSIA', name: 'Russia/Ukraine' },
            instrument: {
              identifier: 'Council Regulation (EU) No 833/2014',
              url: 'https://eur-lex.europa.eu/eli/reg/2014/833/oj'
            },
            measures: {
              'Article 3s' => [
                { effect_type: 'entry_ban',
                  description: 'Access to ports and locks prohibited (Article 3s, Annex XLII)' },
                { effect_type: 'service_prohibition',
                  description: 'Provision of services to the vessel prohibited (Article 3s, Annex XLII)' }
              ]
            }
          },
          '2016/44' => {
            regime: { code: 'LIBYA', name: 'Libya' },
            instrument: {
              identifier: 'Council Regulation (EU) 2016/44',
              url: 'https://eur-lex.europa.eu/eli/reg/2016/44/oj'
            },
            # Article 15 includes measures conditional on the designation
            # in Annex V. DMA's workbook names only the article, so retain
            # that statement rather than assert every possible prohibition.
            measures: {
              'Article 15' => [{ effect_type: 'other', description: 'Article 15' }]
            }
          },
          '2017/1509' => {
            regime: { code: 'DPRK', name: "Democratic People's Republic of Korea" },
            instrument: {
              identifier: 'Council Regulation (EU) 2017/1509',
              url: 'https://eur-lex.europa.eu/eli/reg/2017/1509/oj'
            },
            # The ontology has no seizure or de-registration effect, and
            # neither is an asset freeze or a port ban, so they are
            # published as `other` carrying DMA's own words.
            measures: {
              'Asset freeze' => [{ effect_type: 'asset_freeze', description: 'Asset freeze' }],
              'Seizure' => [{ effect_type: 'other', description: 'Seizure' }],
              'Port entry ban' => [{ effect_type: 'entry_ban', description: 'Port entry ban' }],
              'De-registration' => [{ effect_type: 'other', description: 'De-registration' }]
            }
          }
        }.freeze

        attr_reader :text, :regulation, :measures

        # @param text [String, nil] the cell as DMA publishes it
        # @return [SubjectTo]
        # @raise [Ammitto::ParseError] when the legal citation is malformed
        #   or any measure clause is empty
        def self.parse(text)
          new(text)
        end

        def initialize(text)
          @text = text.to_s
          match = CELL.match(trim(@text))
          raise unknown('does not read as "<measure> (Council Regulation <number>)"') unless match
          raise unknown('contains multiple legal citations') if match[:measures].match?(CITATION)

          @citation = match[:citation]
          @regulation_number = match[:regulation]
          @regulation = REGULATIONS[match[:regulation]]
          @measures = match[:measures].split('+', -1).map { |measure| trim(measure) }
          raise unknown('contains an empty measure clause') if @measures.any? { |measure| measure.gsub(/[[:space:]\p{Cf}\p{Cc}]/, '').empty? }

          unmapped = @measures.reject { |measure| mapped_effects(measure) }
          warn_unmapped(unmapped) if unmapped.any?
        end

        # @return [Hash, nil] verified regime code and name, if known
        def regime
          regulation && regulation[:regime]
        end

        # @return [Hash] instrument identifier and url
        def instrument
          regulation ? regulation[:instrument] : { identifier: @citation }
        end

        # @return [Boolean] whether every clause has a verified mapping
        def fully_mapped?
          measures.all? { |measure| mapped_effects(measure) }
        end

        # Unmapped clauses do not establish scope; nil overrides the
        # transformer's default for verified effects.
        # @return [Array<Hash>] effect_type and description, per measure
        def effects
          measures.flat_map do |measure|
            mapped_effects(measure) || [{ effect_type: 'other', scope: nil, description: "Unmapped source measure: #{measure}" }]
          end
        end

        private

        def trim(value)
          value.gsub(/\A[[:space:]]+|[[:space:]]+\z/, '')
        end

        def normalized(value)
          value.gsub(/[[:space:]]+/, ' ').downcase
        end

        def mapped_effects(measure)
          return unless regulation

          regulation[:measures].find { |name, _| normalized(name) == normalized(measure) }&.last
        end

        def warn_unmapped(measures)
          reason = regulation ? "measure(s) #{measures.join(', ')} under #{@regulation_number}" : "regulation #{@regulation_number}"
          Ammitto::Logger.warn(
            "eu_vessels: unmapped #{reason} in #{@text.inspect}; preserving source text without inferred effects; review mapping"
          )
        end

        def unknown(why)
          Ammitto::ParseError.new("eu_vessels: \"Subject to\" value #{@text.inspect} #{why}")
        end
      end
    end
  end
end
