# frozen_string_literal: true

require_relative 'wb/sanctioned_firm'
require_relative 'wb/response'
require_relative 'wb/transformer'

module Ammitto
  module Sources
    # World Bank sanctions source models
    #
    # Source: https://apigwext.worldbank.org/dvns/v1/ols/SanctionedFirms
    # Format: JSON
    module Wb
    end
  end
end
