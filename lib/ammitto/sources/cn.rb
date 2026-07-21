# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# China Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to Chinese sanctions
# announcements published by MOFCOM and MFA. Since China publishes data as
# HTML announcements (not structured XML/JSON), these models are populated
# after HTML parsing.
#
# China has multiple list types:
# - Unreliable Entity List (不可靠实体清单) - MOFCOM
# - Anti-Sanctions List (反制裁清单) - MFA
# - Export Control List (出口管制管控名单) - MOFCOM
#
# @example Using CN models
#   require 'ammitto/sources/cn'
#
#   # After HTML parsing, create models
#   announcement = Ammitto::Sources::Cn::Announcement.from_parsed_data({
#     announcement_number: "2025年 第5号",
#     date: "2025-01-15",
#     list_type: "unreliable_entity",
#     entities: [{ chinese_name: "...", english_name: "..." }]
#   })
#
# @example Saving to YAML
#   yaml = announcement.to_yaml
#   File.write("cn_announcement_2025_5.yaml", yaml)
#
# @example Loading from YAML
#   announcement = Ammitto::Sources::Cn::Announcement.from_yaml(yaml)
#

module Ammitto
  module Sources
    module Cn
      # Source code for China
      SOURCE_CODE = :cn

      # Human-readable source name
      SOURCE_NAME = 'China (MOFCOM/MFA)'

      # Source URLs (multiple list types)
      SOURCE_URLS = {
        mofcom: 'https://www.mofcom.gov.cn',
        mfa: 'https://www.mfa.gov.cn'
      }.freeze

      # Country code (ISO 3166-1 alpha-2)
      COUNTRY_CODE = 'CN'
    end
  end
end

# Load all CN source models
require_relative 'cn/sanctions_list'
require_relative 'cn/transformer'
