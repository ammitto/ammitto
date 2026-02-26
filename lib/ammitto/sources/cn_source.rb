# frozen_string_literal: true

# CN source models (Lutaml::Model)
require_relative 'cn/sanctions_list'
require_relative 'cn/transformer'

module Ammitto
  # CnSource handles China (MOFCOM/MFA) sanctions data
  #
  # China publishes multiple lists including:
  # - 不可靠实体清单 (Unreliable Entity List) by MOFCOM
  # - 反制裁清单 (Anti-Sanctions List) by MFA
  # - 出口管制管控名单 (Export Control List) by MOFCOM
  #
  # Data is published as HTML announcements, not structured data.
  #
  # @example
  #   source = CnSource.new
  #   data = source.load_data
  #   results = source.search("岩崎茂", data)
  #
  class CnSource < BaseSource
    # List types in China sanctions
    LIST_TYPES = {
      unreliable_entity: '不可靠实体清单',
      anti_sanctions: '反制裁清单',
      export_control: '出口管制管控名单'
    }.freeze

    # @return [Symbol] the source code
    def code
      :cn
    end

    # @return [Authority] the China authority
    def authority
      @authority ||= Authority.find('cn')
    end

    # Get the MOFCOM website
    # @return [String] the MOFCOM URL
    def mofcom_url
      'https://www.mofcom.gov.cn'
    end

    # Get the MFA website
    # @return [String] the MFA URL
    def mfa_url
      'https://www.mfa.gov.cn'
    end
  end

  # Register the source
  Registry.register(:cn, CnSource)
end
