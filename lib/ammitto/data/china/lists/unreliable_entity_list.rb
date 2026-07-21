# frozen_string_literal: true

require_relative '../list'

module Ammitto
  module Data
    module China
      module Lists
        # Handler for Unreliable Entity List (不可靠实体清单)
        # Published by Ministry of Commerce (MOFCOM)
        #
        # @example
        #   list = UnreliableEntityList.from_yaml_file(content)
        #   list.announcement.authority # => "中华人民共和国商务部"
        #
        class UnreliableEntityList < List
          # List metadata
          LIST_NAME_ZH = '不可靠实体清单'
          LIST_NAME_EN = 'Unreliable Entity List'
          LIST_TYPE = 'unreliable-entity-list'
          AUTHORITY = '中华人民共和国商务部'
          AUTHORITY_EN = 'Ministry of Commerce of the PRC'

          # Common sanction measures for UEL
          DEFAULT_MEASURES = %w[
            prohibit_import_export
            prohibit_investment_new
            prohibit_data_transmission
            prohibit_sensitive_information_provision
          ].freeze

          def list_name
            LIST_NAME_ZH
          end

          def list_type
            LIST_TYPE
          end

          def authority
            AUTHORITY
          end
        end
      end
    end
  end
end
