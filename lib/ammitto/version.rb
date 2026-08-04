# frozen_string_literal: true

module Ammitto
  # 2.0.0: entries moved from being embedded inside their entity to
  # first-class @graph nodes referenced by IRI, and groupId and
  # legalCitations are serialized for the first time. The previous embedded
  # form was valid JSON-LD, so this is a breaking change to the compact JSON
  # representation rather than a correction of invalid output: a consumer
  # reading the nested object now finds an IRI string, and one that does not
  # follow the reference finds nothing.
  VERSION = '2.0.0'
end
