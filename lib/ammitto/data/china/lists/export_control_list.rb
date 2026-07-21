# frozen_string_literal: true

require_relative '../list'

module Ammitto
  module Data
    module China
      module Lists
        # Handler for Export Control List (出口管制管控名单)
        # Published by Ministry of Commerce (MOFCOM)
        #
        # @example
        #   list = ExportControlList.from_yaml_file(content)
        #   list.announcement.authority # => "中华人民共和国商务部"
        #
        class ExportControlList < List
          # List metadata
          LIST_NAME_ZH = '出口管制管控名单'
          LIST_NAME_EN = 'Export Control List'
          LIST_TYPE = 'export-control-list'
          AUTHORITY = '中华人民共和国商务部'
          AUTHORITY_EN = 'Ministry of Commerce of the PRC'

          # Common sanction measures for export control
          DEFAULT_MEASURES = %w[
            prohibit_export_dual_use_items
            prohibit_transfer_provide_dual_use_items
            prohibit_export_specific_product
            export_license_requirement
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
