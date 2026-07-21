# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Entity (organization) from UN sanctions list
      #
      # Example XML:
      # <ENTITY>
      #   <DATAID>...</DATAID>
      #   <FIRST_NAME>Entity Name</FIRST_NAME>
      #   <UN_LIST_TYPE>...</UN_LIST_TYPE>
      #   <REFERENCE_NUMBER>...</REFERENCE_NUMBER>
      #   <LISTED_ON>...</LISTED_ON>
      #   <ENTITY_ALIAS>...</ENTITY_ALIAS>
      #   <ENTITY_ADDRESS>...</ENTITY_ADDRESS>
      # </ENTITY>
      class Entity < Lutaml::Model::Serializable
        attribute :dataid, :string
        attribute :versionnum, :string
        attribute :first_name, :string
        attribute :un_list_type, :string
        attribute :reference_number, :string
        attribute :listed_on, :string
        attribute :comments1, :string
        attribute :list_type, ValueWrapper
        attribute :last_day_updated, ValueWrapper
        attribute :aliases, EntityAlias, collection: true
        attribute :addresses, EntityAddress, collection: true
        attribute :sort_key, :string
        attribute :sort_key_last_mod, :string

        xml do
          root 'ENTITY'
          map_element 'DATAID', to: :dataid
          map_element 'VERSIONNUM', to: :versionnum
          map_element 'FIRST_NAME', to: :first_name
          map_element 'UN_LIST_TYPE', to: :un_list_type
          map_element 'REFERENCE_NUMBER', to: :reference_number
          map_element 'LISTED_ON', to: :listed_on
          map_element 'COMMENTS1', to: :comments1
          map_element 'LIST_TYPE', to: :list_type
          map_element 'LAST_DAY_UPDATED', to: :last_day_updated
          map_element 'ENTITY_ALIAS', to: :aliases
          map_element 'ENTITY_ADDRESS', to: :addresses
          map_element 'SORT_KEY', to: :sort_key
          map_element 'SORT_KEY_LAST_MOD', to: :sort_key_last_mod
        end

        yaml do
          map 'dataid', to: :dataid
          map 'versionnum', to: :versionnum
          map 'first_name', to: :first_name
          map 'un_list_type', to: :un_list_type
          map 'reference_number', to: :reference_number
          map 'listed_on', to: :listed_on
          map 'comments1', to: :comments1
          map 'list_type', to: :list_type
          map 'last_day_updated', to: :last_day_updated
          map 'aliases', to: :aliases
          map 'addresses', to: :addresses
          map 'sort_key', to: :sort_key
          map 'sort_key_last_mod', to: :sort_key_last_mod
        end

        # Helper methods
        def primary_name
          first_name
        end
      end
    end
  end
end
