# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Data
    module Japan
      # Meti (Ministry of Economy, Trade and Industry) data sources
      #
      # Meti maintains the Foreign User List (外国ユーザーリスト), which lists
      # entities with concerns about involvement in WMD proliferation.
      #
      # Source URL: https://www.meti.go.jp/policy/anpo/law00.html
      #
      # @example Fetching the Foreign User List
      #   require 'ammitto/data/japan/meti'
      #
      #   extractor = Ammitto::Data::Japan::Meti::Extractor.new
      #   xlsx_path = extractor.download
      #   list = Ammitto::Data::Japan::Meti::ForeignUserList.from_xlsx(xlsx_path)
      #
      module Meti
        # Source code for Meti
        SOURCE_CODE = :jp_meti

        # Human-readable source name
        SOURCE_NAME = 'Japan Meti Foreign User List'

        # Index page URL
        INDEX_URL = 'https://www.meti.go.jp/policy/anpo/law00.html'

        # Authority ID
        AUTHORITY_ID = 'jp/meti'

        # Legal basis
        LEGAL_BASIS = 'Foreign Exchange and Foreign Trade Act (FEFTA)'
      end
    end
  end
end

# Load Meti models
require_relative 'meti/entity'
require_relative 'meti/foreign_user_list'
require_relative 'meti/extractor'
require_relative 'meti/transformer'
