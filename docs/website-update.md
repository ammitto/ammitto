# Website Update Required

The ammitto gem has been updated with the new normalized IRI structure. This document tracks the remaining work to update the website.

## Completed Work

### 1. IRI Structure Normalization ✓

The knowledge graph now uses normalized IRIs:

```
# Entities - LIST-AGNOSTIC (can appear on multiple lists)
https://www.ammitto.org/entity/{source}/{local_id}

# Entries - LIST-SPECIFIC (junction records linking entity to list)
https://www.ammitto.org/entry/{source}/{list_type}/{local_id}

# Lists
https://www.ammitto.org/list/{source}/{list_type}

# Announcements - LIST-AGNOSTIC
https://www.ammitto.org/announcement/{source}/{local_id}

# Legal Instruments - LIST-AGNOSTIC
https://www.ammitto.org/legal_instrument/{source}/{local_id}
```

### 2. Data Migration ✓

- Created `scripts/migrate_iri_structure.rb` to fix existing data
- Removed source prefixes from IDs (e.g., `cn-mitsubishi` → `mitsubishi`)
- Added `list_type` field to entries
- Updated schema version to 3.0

### 3. Export Scripts Updated ✓

- `lib/ammitto/serialization/json_ld_graph_exporter.rb` - Handles entry paths with list_type
- `lib/ammitto/serialization/search_index_exporter.rb` - Includes list_type in search index
- Added `by-list/` slice generation

### 4. Website API Files Regenerated ✓

- Exported 26,425 entities from all 15 sources
- IRIs now follow normalized structure

## Remaining Work

### 1. Generate Individual Node Files

The current export generates:
- `api/v1/sources/{code}.jsonld` - Per-source combined data
- `api/v1/all.jsonld` - Combined graph
- `api/v1/stats.json` - Statistics

Still needed:
- `api/v1/node/entity/{source}/{id}.jsonld` - Individual entity nodes
- `api/v1/node/entry/{source}/{list_type}/{id}.jsonld` - Individual entry nodes
- `api/v1/node/list/{source}/{list_type}.jsonld` - List definition nodes
- `api/v1/search-index.json` - Lightweight search index
- `api/v1/facets/list_types.json` - List type facets
- `api/v1/by-list/{source}/{list_type}.jsonld` - By-list slices

### 2. Update Website Composables

See `ammitto.github.io/TODO-knowledge-graph.md` for detailed tasks:

- Update `useSearchIndex.ts` to handle new IRI format
- Add `listType` to SearchEntity interface
- Create `useListData.ts` for list browsing

### 3. Add Website Routes

- `/entity/:source/:id` - Entity page
- `/entry/:source/:list_type/:id` - Entry page
- `/list/:source/:list_type` - List page
- `/browse/lists` - Browse by list type

## Key Changes Made to the Gem

1. **IriSanitizer** - New utility module for generating normalized IRIs
   - Entity IRIs are list-agnostic: `/entity/{source}/{local_id}`
   - Entry IRIs are list-specific: `/entry/{source}/{list_type}/{local_id}`

2. **ListTypesRegistry** - Registry of all list types per source
   - CN: anti-sanction-list, import-export-control-list, unreliable-entity-list
   - RU: stop-list
   - US: sdn-list, entity-list, nonproliferation-sanctions
   - etc.

3. **KnowledgeGraphLoader** - Updated for normalized structure
   - `load_entities()` - Returns all entities (not per-list)
   - `load_entries()` - Returns entries with list_type
   - `load_lists()` - Returns list definitions
   - `entries_for_entity(id)` - Get all entries for an entity
   - `entries_for_list(type)` - Get all entries for a list

4. **BaseTransformer** - Updated to generate normalized IRIs
   - `generate_entity_id(local_id)` - List-agnostic entity IRI
   - `generate_entry_id(local_id, list_type)` - List-specific entry IRI

5. **Ontology Module** - Added list support
   - `SanctionsList` model for list definitions
   - `list_uri(source, list_type)` method
   - `lists_for_source(source)` method

## Testing

Run the verification script:
```bash
ruby scripts/verify_iri_structure.rb
```

Run the test suite:
```bash
bundle exec rspec
```

## Documentation

Updated documentation files:
- `README.adoc` - Updated IRI structure section
- `docs/architecture/knowledge-graph.adoc` - Complete normalized structure docs
- `data-cn/README.adoc` - Updated for normalized structure
- `data-cn/SCHEMA.yaml` - Updated schema with list_type
- `data/README.adoc` - Updated directory structure and API endpoints
