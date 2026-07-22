# frozen_string_literal: true

module Ammitto
  module Sources
    module Us
      # XML namespace for the OFAC SDN publication export format
      # (lutaml-model >= 0.8 requires namespace classes instead of string URIs)
      class SdnNamespace < Lutaml::Xml::Namespace
        uri 'https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/XML'
      end
    end
  end
end
