# frozen_string_literal: true

# Shared environment defaults for the ontology pipeline scripts.
# Empty env values count as unset so defaults stay deterministic.

data_dir = ENV.fetch('AMMITTO_DATA_DIR', '')
# Fallback is the parent of the gem checkout — the sibling-directory
# convention where data-* repositories live next to the gem.
DEFAULT_DATA_DIR =
  data_dir.empty? ? File.expand_path('../../..', __dir__) : data_dir

neo4j_uri = ENV.fetch('NEO4J_URI', '')
NEO4J_URI_DEFAULT = neo4j_uri.empty? ? 'bolt://localhost:7688' : neo4j_uri
