# frozen_string_literal: true

module Ammitto
  module Sources
    module Eu
      # XML namespace for the EU FSF export format (lutaml-model >= 0.8
      # requires namespace classes instead of string URIs)
      class ExportNamespace < Lutaml::Xml::Namespace
        uri 'http://eu.europa.ec/fpi/fsd/export'
      end
    end
  end
end
