# frozen_string_literal: true

require_relative '../list'

module Ammitto
  module Data
    module China
      module Lists
        # Handler for Anti-Sanctions List (反制裁清单)
        # Published by Ministry of Foreign Affairs (MFA)
        #
        # @example
        #   list = AntiSanctionList.from_yaml_file(content)
        #   list.announcement.authority # => "中华人民共和国外交部"
        #
        class AntiSanctionList < List
          # List metadata
          LIST_NAME_ZH = '反制裁清单'
          LIST_NAME_EN = 'Anti-Sanctions List'
          LIST_TYPE = 'anti-sanction-list'
          AUTHORITY = '中华人民共和国外交部'
          AUTHORITY_EN = 'Ministry of Foreign Affairs of the PRC'

          # Common sanction measures for anti-sanctions list
          DEFAULT_MEASURES = %w[
            asset_freeze
            prohibit_transactions
            entry_ban
            visa_ban
          ].freeze

          # Add list-specific methods
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
