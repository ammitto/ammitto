# frozen_string_literal: true

require 'lutaml/model'

require_relative 'entity'
require_relative 'announcement'
require_relative 'list'
require_relative 'field_mapping'
require_relative 'extractor'

module Ammitto
  module Data
    module Japan
      # MOF (Ministry of Finance) data sources
      #
      # MOF maintains the Asset Freeze List (資産凍結リ対象者一覧), which lists
      # individuals and entities subject to asset freezing sanctions under FEFTA.
      #
      # Source URL: https://www.mof.go.jp/policy/international_policy/gaitame_kawase/gaitame/economic_sanctions/list.html
      #
      # @example Fetching MOF sanctions
      #   require 'ammitto/data/japan/mof'
      #
      #   extractor = Ammitto::Data::Japan::Mof::Extractor.new
      #   xlsx_path = extractor.download
      #   list = Ammitto::Data::Japan::Mof::List.from_xlsx(xlsx_path)
      #
      module Mof
        # Source code for MOF
        SOURCE_CODE = :jp_mof

        # Human-readable source name
        SOURCE_NAME = 'Japan MOF Asset Freeze List'

        # Index page URL
        INDEX_URL = 'https://www.mof.go.jp/policy/international_policy/gaitame_kawase/gaitame/economic_sanctions/list.html'

        # Authority ID
        AUTHORITY_ID = 'jp/mof'

        # Legal basis
        LEGAL_BASIS = 'Foreign Exchange and Foreign Trade Act (FEFTA)'

        # Base URL for Excel files
        BASE_URL = 'https://www.mof.go.jp'

        class << self
          # Get list of available sanction lists
          # @return [Array<String>] List of available list IDs
          def available_lists
            SANCTION_LIST_CONFIG.keys
          end

          # Get config for a specific list
          # @param list_id [String] The list ID (e.g., "jp/mof-asset-freeze-taliban")
          # @return [Hash, nil] The list config or nil if not found
          def list_config(list_id)
            SANCTION_LIST_CONFIG.each_value do |config|
              return config if config[:id] == list_id
            end
            nil
          end

          # Get English name for a list
          # @param list_id [String] The list ID
          # @return [String, nil] The English name or nil if not found
          def list_name_en(list_id)
            SANCTION_LIST_NAMES_EN[list_id]
          end

          # Fetch a specific sanction list
          # @param list_id [String] The list ID to fetch
          # @param output_dir [String] Output directory for YAML files
          # @param options [Hash] Options
          # @return [String] Path to the generated YAML file
          def fetch(list_id, output_dir, options = {})
            extractor = Extractor.new(options)
            xlsx_path = extractor.download
            return nil unless xlsx_path

            list = List.from_xlsx(xlsx_path, source_url: extractor.source_url, list_id: list_id)
            return nil unless list

            date_str = Date.today.strftime('%Y%m%d')
            list.first.to_yaml_file(output_dir, date_str)
          end

          # Fetch all sanction lists
          # @param output_dir [String] Output directory for YAML files
          # @param options [Hash] Options
          # @return [Array<String>] List of generated YAML file paths
          def fetch_all(output_dir, options = {})
            extractor = Extractor.new(options)
            xlsx_path = extractor.download
            return [] unless xlsx_path

            lists = List.from_xlsx(xlsx_path, source_url: extractor.source_url)
            date_str = Date.today.strftime('%Y%m%d')

            lists.map { |list| list.to_yaml_file(output_dir, date_str) }
          end
        end

        # Sanction list directory mapping from sheet name to config
        # Format: "sheet_name" => { index: NN, slug: "name", id: "canonical-id" }
        SANCTION_LIST_CONFIG = {
          '1.ミロシェビッチ前ユーゴ大統領関係者' => { index: 1, slug: 'milosevic', id: 'jp/mof-asset-freeze-milosevic' },
          '2.タリバーン関係者等' => { index: 2, slug: 'taliban', id: 'jp/mof-asset-freeze-taliban' },
          '3.テロリスト等 (1)' => { index: 3, slug: 'terrorists-g7', id: 'jp/mof-asset-freeze-terrorists-g7' },
          '4.テロリスト等 (2)' => { index: 4, slug: 'terrorists-us', id: 'jp/mof-asset-freeze-terrorists-us' },
          '5.イラク前政権関係者等（Ⅰ）' => { index: 5, slug: 'iraq-1', id: 'jp/mof-asset-freeze-iraq-1' },
          '6.イラク前政権関係者等 (Ⅱ)' => { index: 6, slug: 'iraq-2', id: 'jp/mof-asset-freeze-iraq-2' },
          '7.イラク前政権関係者等 (Ⅲ)' => { index: 7, slug: 'iraq-3', id: 'jp/mof-asset-freeze-iraq-3' },
          '9.コンゴ民主共和国（個人）' => { index: 9, slug: 'drc-individuals', id: 'jp/mof-asset-freeze-drc-individuals' },
          '10.コンゴ民主共和国 (団体)' => { index: 10, slug: 'drc-organizations', id: 'jp/mof-asset-freeze-drc-organizations' },
          '12.スーダン' => { index: 12, slug: 'sudan', id: 'jp/mof-asset-freeze-sudan' },
          '13.北朝鮮(決議1695号)' => { index: 13, slug: 'dprk-1695', id: 'jp/mof-asset-freeze-dprk-1695' },
          '14.北朝鮮(決議1718号等；団体)' => { index: 14, slug: 'dprk-un-organizations', id: 'jp/mof-asset-freeze-dprk-un-organizations' },
          '15.北朝鮮(決議1718号等；個人)' => { index: 15, slug: 'dprk-un-individuals', id: 'jp/mof-asset-freeze-dprk-un-individuals' },
          '16.北朝鮮(協調；団体)' => { index: 16, slug: 'dprk-coord-organizations', id: 'jp/mof-asset-freeze-dprk-coord-organizations' },
          '17.北朝鮮(協調;個人)' => { index: 17, slug: 'dprk-coord-individuals', id: 'jp/mof-asset-freeze-dprk-coord-individuals' },
          '19.イラン（個人）' => { index: 19, slug: 'iran-individuals', id: 'jp/mof-asset-freeze-iran-individuals' },
          '20.イラン (団体)' => { index: 20, slug: 'iran-organizations', id: 'jp/mof-asset-freeze-iran-organizations' },
          '21.ソマリア' => { index: 21, slug: 'somalia', id: 'jp/mof-asset-freeze-somalia' },
          '22.リビア(Ⅰ)' => { index: 22, slug: 'libya-1', id: 'jp/mof-asset-freeze-libya-1' },
          '23.リビア (Ⅱ)' => { index: 23, slug: 'libya-2', id: 'jp/mof-asset-freeze-libya-2' },
          '24.シリア（個人）' => { index: 24, slug: 'syria-individuals', id: 'jp/mof-asset-freeze-syria-individuals' },
          '25.シリア（団体）' => { index: 25, slug: 'syria-organizations', id: 'jp/mof-asset-freeze-syria-organizations' },
          '26.クリミア等（個人）' => { index: 26, slug: 'crimea-individuals', id: 'jp/mof-asset-freeze-crimea-individuals' },
          '27.クリミア等 (団体)' => { index: 27, slug: 'crimea-organizations', id: 'jp/mof-asset-freeze-crimea-organizations' },
          '28.ロシア連邦(団体(特定銀行を除く))' => { index: 28, slug: 'russia-organizations', id: 'jp/mof-asset-freeze-russia-organizations' },
          '29.ロシア連邦(個人)' => { index: 29, slug: 'russia-individuals', id: 'jp/mof-asset-freeze-russia-individuals' },
          '30.ロシア連邦(特定銀行）' => { index: 30, slug: 'russia-banks', id: 'jp/mof-asset-freeze-russia-banks' },
          '31.ベラルーシ(個人)' => { index: 31, slug: 'belarus-individuals', id: 'jp/mof-asset-freeze-belarus-individuals' },
          '32.ベラルーシ(団体(特定銀行を除く))' => { index: 32, slug: 'belarus-organizations', id: 'jp/mof-asset-freeze-belarus-organizations' },
          '33.ベラルーシ(特定銀行)' => { index: 33, slug: 'belarus-banks', id: 'jp/mof-asset-freeze-belarus-banks' },
          '34.ロシア及びベラルーシ以外（団体(特定銀行を除く)）' => { index: 34, slug: 'other-organizations', id: 'jp/mof-asset-freeze-other-organizations' },
          '35.ロシア及びベラルーシ以外(個人)' => { index: 35, slug: 'other-individuals', id: 'jp/mof-asset-freeze-other-individuals' },
          '36.ロシア及びベラルーシ以外(特定銀行)' => { index: 36, slug: 'other-banks', id: 'jp/mof-asset-freeze-other-banks' },
          '37.中央アフリカ共和国（個人）' => { index: 37, slug: 'car-individuals', id: 'jp/mof-asset-freeze-car-individuals' },
          '38.中央アフリカ共和国（団体）' => { index: 38, slug: 'car-organizations', id: 'jp/mof-asset-freeze-car-organizations' },
          '39.イエメン共和国' => { index: 39, slug: 'yemen', id: 'jp/mof-asset-freeze-yemen' },
          '40.南スーダン' => { index: 40, slug: 'south-sudan', id: 'jp/mof-asset-freeze-south-sudan' },
          '41.マリ共和国' => { index: 41, slug: 'mali', id: 'jp/mof-asset-freeze-mali' },
          '42.ハイチ共和国（個人）' => { index: 42, slug: 'haiti-individuals', id: 'jp/mof-asset-freeze-haiti-individuals' },
          '43.イスラエル' => { index: 43, slug: 'israel-settlers', id: 'jp/mof-asset-freeze-israel-settlers' },
          '44.ハイチ共和国（団体）' => { index: 44, slug: 'haiti-organizations', id: 'jp/mof-asset-freeze-haiti-organizations' }
        }.freeze

        # English names for sanction lists
        SANCTION_LIST_NAMES_EN = {
          'jp/mof-asset-freeze-milosevic' => 'Associates of Former Yugoslav President Milosevic',
          'jp/mof-asset-freeze-taliban' => 'Taliban, Al-Qaeda and ISIL (Daesh) Associates',
          'jp/mof-asset-freeze-terrorists-g7' => 'Terrorists (G7 Coordinated)',
          'jp/mof-asset-freeze-terrorists-us' => 'Terrorists (US Designated)',
          'jp/mof-asset-freeze-iraq-1' => 'Former Iraqi Regime Officials (I)',
          'jp/mof-asset-freeze-iraq-2' => 'Former Iraqi Regime Officials (II)',
          'jp/mof-asset-freeze-iraq-3' => 'Former Iraqi Regime Officials (III)',
          'jp/mof-asset-freeze-drc-individuals' => 'Democratic Republic of the Congo (Individuals)',
          'jp/mof-asset-freeze-drc-organizations' => 'Democratic Republic of the Congo (Entities)',
          'jp/mof-asset-freeze-sudan' => 'Sudan',
          'jp/mof-asset-freeze-dprk-1695' => 'DPRK (Resolution 1695)',
          'jp/mof-asset-freeze-dprk-un-organizations' => 'DPRK (Resolution 1718 - Entities)',
          'jp/mof-asset-freeze-dprk-un-individuals' => 'DPRK (Resolution 1718 - Individuals)',
          'jp/mof-asset-freeze-dprk-coord-organizations' => 'DPRK (Coordinated - Entities)',
          'jp/mof-asset-freeze-dprk-coord-individuals' => 'DPRK (Coordinated - Individuals)',
          'jp/mof-asset-freeze-iran-individuals' => 'Iran (Individuals)',
          'jp/mof-asset-freeze-iran-organizations' => 'Iran (Entities)',
          'jp/mof-asset-freeze-somalia' => 'Somalia',
          'jp/mof-asset-freeze-libya-1' => 'Libya (I)',
          'jp/mof-asset-freeze-libya-2' => 'Libya (II)',
          'jp/mof-asset-freeze-syria-individuals' => 'Syria (Individuals)',
          'jp/mof-asset-freeze-syria-organizations' => 'Syria (Entities)',
          'jp/mof-asset-freeze-crimea-individuals' => 'Crimea and Sevastopol (Individuals)',
          'jp/mof-asset-freeze-crimea-organizations' => 'Crimea and Sevastopol (Entities)',
          'jp/mof-asset-freeze-russia-organizations' => 'Russian Federation (Entities excl. Banks)',
          'jp/mof-asset-freeze-russia-individuals' => 'Russian Federation (Individuals)',
          'jp/mof-asset-freeze-russia-banks' => 'Russian Federation (Designated Banks)',
          'jp/mof-asset-freeze-belarus-individuals' => 'Belarus (Individuals)',
          'jp/mof-asset-freeze-belarus-organizations' => 'Belarus (Entities excl. Banks)',
          'jp/mof-asset-freeze-belarus-banks' => 'Belarus (Designated Banks)',
          'jp/mof-asset-freeze-other-organizations' => 'Other Countries (Entities excl. Banks)',
          'jp/mof-asset-freeze-other-individuals' => 'Other Countries (Individuals)',
          'jp/mof-asset-freeze-other-banks' => 'Other Countries (Designated Banks)',
          'jp/mof-asset-freeze-car-individuals' => 'Central African Republic (Individuals)',
          'jp/mof-asset-freeze-car-organizations' => 'Central African Republic (Entities)',
          'jp/mof-asset-freeze-yemen' => 'Republic of Yemen',
          'jp/mof-asset-freeze-south-sudan' => 'South Sudan',
          'jp/mof-asset-freeze-mali' => 'Republic of Mali',
          'jp/mof-asset-freeze-haiti-individuals' => 'Republic of Haiti (Individuals)',
          'jp/mof-asset-freeze-israel-settlers' => 'Israel (Settlers)',
          'jp/mof-asset-freeze-haiti-organizations' => 'Republic of Haiti (Entities)'
        }.freeze
      end
    end
  end
end
