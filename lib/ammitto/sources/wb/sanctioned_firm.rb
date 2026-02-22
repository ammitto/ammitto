# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Wb
      # Sanctioned firm/individual from World Bank
      class SanctionedFirm < Lutaml::Model::Serializable
        attribute :mandt, :string
        attribute :supp_id, :integer
        attribute :supp_name, :string
        attribute :supp_type_code, :string
        attribute :supp_pre_acrn, :string
        attribute :supp_post_acrn, :string
        attribute :land1, :string
        attribute :country_name, :string
        attribute :supp_state_code, :string
        attribute :supp_city, :string
        attribute :supp_addr, :string
        attribute :supp_zip_code, :string
        attribute :supp_post_code, :string
        attribute :supp_prov_name, :string
        attribute :legacy_flg, :string
        attribute :un_supp_flg, :string
        attribute :inelig_flg, :string
        attribute :debar_type, :string
        attribute :debar_from_date, :string
        attribute :debar_to_date, :string
        attribute :debar_reason, :string
        attribute :add_supp_info, :string
        attribute :supp_elig_stat, :string
        attribute :crpd_match, :string
        attribute :crpd_stat, :string
        attribute :elig_stat, :string
        attribute :ineligibly_status, :string

        json do
          map 'MANDT', to: :mandt
          map 'SUPP_ID', to: :supp_id
          map 'SUPP_NAME', to: :supp_name
          map 'SUPP_TYPE_CODE', to: :supp_type_code
          map 'SUPP_PRE_ACRN', to: :supp_pre_acrn
          map 'SUPP_POST_ACRN', to: :supp_post_acrn
          map 'LAND1', to: :land1
          map 'COUNTRY_NAME', to: :country_name
          map 'SUPP_STATE_CODE', to: :supp_state_code
          map 'SUPP_CITY', to: :supp_city
          map 'SUPP_ADDR', to: :supp_addr
          map 'SUPP_ZIP_CODE', to: :supp_zip_code
          map 'SUPP_POST_CODE', to: :supp_post_code
          map 'SUPP_PROV_NAME', to: :supp_prov_name
          map 'LEGACY_FLG', to: :legacy_flg
          map 'UN_SUPP_FLG', to: :un_supp_flg
          map 'INELIG_FLG', to: :inelig_flg
          map 'DEBAR_TYPE', to: :debar_type
          map 'DEBAR_FROM_DATE', to: :debar_from_date
          map 'DEBAR_TO_DATE', to: :debar_to_date
          map 'DEBAR_REASON', to: :debar_reason
          map 'ADD_SUPP_INFO', to: :add_supp_info
          map 'SUPP_ELIG_STAT', to: :supp_elig_stat
          map 'CRPD_MATCH', to: :crpd_match
          map 'CRPD_STAT', to: :crpd_stat
          map 'ELIG_STAT', to: :elig_stat
          map 'INELIGIBLY_STATUS', to: :ineligibly_status
        end

        yaml do
          map 'mandt', to: :mandt
          map 'supp_id', to: :supp_id
          map 'supp_name', to: :supp_name
          map 'supp_type_code', to: :supp_type_code
          map 'supp_pre_acrn', to: :supp_pre_acrn
          map 'supp_post_acrn', to: :supp_post_acrn
          map 'land1', to: :land1
          map 'country_name', to: :country_name
          map 'supp_state_code', to: :supp_state_code
          map 'supp_city', to: :supp_city
          map 'supp_addr', to: :supp_addr
          map 'supp_zip_code', to: :supp_zip_code
          map 'supp_post_code', to: :supp_post_code
          map 'supp_prov_name', to: :supp_prov_name
          map 'legacy_flg', to: :legacy_flg
          map 'un_supp_flg', to: :un_supp_flg
          map 'inelig_flg', to: :inelig_flg
          map 'debar_type', to: :debar_type
          map 'debar_from_date', to: :debar_from_date
          map 'debar_to_date', to: :debar_to_date
          map 'debar_reason', to: :debar_reason
          map 'add_supp_info', to: :add_supp_info
          map 'supp_elig_stat', to: :supp_elig_stat
          map 'crpd_match', to: :crpd_match
          map 'crpd_stat', to: :crpd_stat
          map 'elig_stat', to: :elig_stat
          map 'ineligibly_status', to: :ineligibly_status
        end

        # Helper methods
        def entity_type
          supp_type_code == 'I' ? 'person' : 'organization'
        end

        def person?
          entity_type == 'person'
        end

        def primary_name
          supp_name
        end

        def cross_debarred?
          crpd_match == 'Y'
        end

        def active?
          debar_to_date && Date.parse(debar_to_date) > Date.today
        end
      end
    end
  end
end
