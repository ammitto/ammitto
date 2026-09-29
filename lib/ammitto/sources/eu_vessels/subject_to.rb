# frozen_string_literal: true

require_relative '../../errors/base_error'

module Ammitto
  module Sources
    module EuVessels
      # The legal basis and measures one "Subject to" cell of the DMA
      # workbook states, e.g. "Article 3s (Council Regulation 833/2014)" or
      # "De-registration + Port entry ban (Council Regulation 2017/1509)".
      #
      # The workbook mixes two EU regimes: vessels under Article 3s of the
      # Russia regulation, which closes ports and services to them but
      # freezes nothing, and vessels under the DPRK regulation, each with
      # the measure DMA names. Publishing one fixed pair of effects for all
      # of them stated measures the source does not, so every cell is
      # read, and a cell outside this vocabulary stops the harvest: a new
      # measure has to be mapped by a person before it is published.
      class SubjectTo
        CELL = %r{\A(?<measures>.+?) \(Council Regulation (?<regulation>\d+/\d+)\)\z}

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
        # @raise [Ammitto::ParseError] when the cell names a regulation or a
        #   measure this vocabulary does not know
        def self.parse(text)
          new(text)
        end

        def initialize(text)
          @text = text.to_s.strip
          match = CELL.match(@text)
          raise unknown('does not read as "<measure> (Council Regulation <number>)"') unless match

          @regulation = REGULATIONS[match[:regulation]]
          raise unknown("names regulation #{match[:regulation]}, which is not mapped") unless @regulation

          @measures = match[:measures].split(' + ').map(&:strip)
          unmapped = @measures.reject { |measure| @regulation[:measures].key?(measure) }
          raise unknown("names measure(s) #{unmapped.join(', ')}, not mapped under #{match[:regulation]}") if unmapped.any?
        end

        # @return [Hash] regime code and name
        def regime
          regulation[:regime]
        end

        # @return [Hash] instrument identifier and url
        def instrument
          regulation[:instrument]
        end

        # @return [Array<Hash>] effect_type and description, per measure
        def effects
          measures.flat_map { |measure| regulation[:measures].fetch(measure) }
        end

        private

        def unknown(why)
          Ammitto::ParseError.new("eu_vessels: \"Subject to\" value #{@text.inspect} #{why}")
        end
      end
    end
  end
end
