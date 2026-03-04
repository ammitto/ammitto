# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Data
    module Japan
      # Base module for Japan data sources
      #
      # Japan maintains several sanctions and export control lists:
      # - Meti: Ministry of Economy, Trade and Industry (Foreign User List)
      # - MOFA: Ministry of Foreign Affairs (Travel Ban List)
      # - MOF: Ministry of Finance (Asset Freeze List)
      #
      # @example Loading Japan data
      #   require 'ammitto/data/japan'
      #   require 'ammitto/data/japan/meti'
      #
      #   extractor = Ammitto::Data::Japan::Meti::Extractor.new
      #   data = extractor.fetch
      #

      # Country code for Japan
      COUNTRY_CODE = 'JP'

      # ISO 3166-1 alpha-2 to Japanese name mapping
      COUNTRY_NAMES = {
        'AF' => { ja: 'アフガニスタン', en: 'Afghanistan' },
        'AE' => { ja: 'アラブ首長国連邦', en: 'United Arab Emirates' },
        'AM' => { ja: 'アルメニア', en: 'Armenia' },
        'CN' => { ja: '中国', en: 'China' },
        'HK' => { ja: '香港', en: 'Hong Kong' },
        'IR' => { ja: 'イラン', en: 'Iran' },
        'KP' => { ja: '北朝鮮', en: 'North Korea' },
        'KR' => { ja: '大韓民国', en: 'South Korea' },
        'PK' => { ja: 'パキスタン', en: 'Pakistan' },
        'RU' => { ja: 'ロシア', en: 'Russia' },
        'SY' => { ja: 'シリア', en: 'Syria' },
        'TW' => { ja: '台湾', en: 'Taiwan' }
      }.freeze

      # WMD type codes
      WMD_TYPES = {
        'N' => { ja: '核兵器', en: 'Nuclear weapons' },
        'M' => { ja: 'ミサイル', en: 'Missiles' },
        'B' => { ja: '生物兵器', en: 'Biological weapons' },
        'C' => { ja: '化学兵器', en: 'Chemical weapons' },
        'CW' => { ja: '通常兵器', en: 'Conventional weapons' }
      }.freeze
    end
  end
end

# Load submodules
require_relative 'japan/meti'
