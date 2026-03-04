#!/usr/bin/env ruby
# frozen_string_literal: true

# Verification script for NORMALIZED Knowledge Graph Structure
# Run: ruby scripts/verify_iri_structure.rb

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'ammitto'

puts '=' * 70
puts 'NORMALIZED Knowledge Graph Structure Verification'
puts '=' * 70

puts "\n#{'=' * 70}"
puts '1. NORMALIZED KNOWLEDGE GRAPH STRUCTURE'
puts '=' * 70

puts <<~TEXT

  The knowledge graph follows a NORMALIZED structure where:

  • ENTITIES are LIST-AGNOSTIC (can appear on multiple lists)
  • LISTS define sanctions regimes
  • ENTRIES link entities to lists (junction records)
  • ANNOUNCEMENTS are LIST-AGNOSTIC (can affect multiple lists)
  • LEGAL INSTRUMENTS are LIST-AGNOSTIC (can authorize multiple lists)

TEXT

puts "\n#{'=' * 70}"
puts '2. IRI STRUCTURE'
puts '=' * 70

puts <<~TEXT

  Entity (LIST-AGNOSTIC - can be on multiple lists):
    https://www.ammitto.org/entity/{source}/{local_id}

  Entry (LIST-SPECIFIC - junction record linking entity to list):
    https://www.ammitto.org/entry/{source}/{list_type}/{local_id}

  Announcement (LIST-AGNOSTIC):
    https://www.ammitto.org/announcement/{source}/{local_id}

  Legal Instrument (LIST-AGNOSTIC):
    https://www.ammitto.org/legal_instrument/{source}/{local_id}

  List:
    https://www.ammitto.org/list/{source}/{list_type}

TEXT

puts "\n#{'=' * 70}"
puts '3. IRI EXAMPLES'
puts '=' * 70

puts "\n  Entity IRIs (same entity, different lists = SAME entity IRI):"
entity = Ammitto::Utils::IriSanitizer.entity_iri('cn', 'mitsubishi-heavy-industries')
puts "    #{entity}"

puts "\n  Entry IRIs (same entity, different lists = DIFFERENT entry IRIs):"
entry1 = Ammitto::Utils::IriSanitizer.entry_iri('cn', 'import-export-control-list', 'mitsubishi-heavy-industries')
entry2 = Ammitto::Utils::IriSanitizer.entry_iri('cn', 'unreliable-entity-list', 'mitsubishi-heavy-industries')
puts "    #{entry1}"
puts "    #{entry2}"

puts "\n  Announcement IRI:"
announcement = Ammitto::Utils::IriSanitizer.announcement_iri('cn', 'mofcom-2026-11')
puts "    #{announcement}"

puts "\n  Legal Instrument IRI:"
instrument = Ammitto::Utils::IriSanitizer.legal_instrument_iri('cn', 'export-control-law')
puts "    #{instrument}"

puts "\n  List IRI:"
list = Ammitto::Utils::IriSanitizer.list_type_iri('cn', 'import-export-control-list')
puts "    #{list}"

puts "\n#{'=' * 70}"
puts '4. NAVIGATION: Entry to Entity'
puts '=' * 70

puts "\n  From an entry IRI, you can navigate to the entity:"
entry_iri = 'https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries'
entity_iri = Ammitto::Utils::IriSanitizer.entity_iri_from_entry(entry_iri)
puts "    Entry:   #{entry_iri}"
puts "    Entity:  #{entity_iri}"

puts "\n#{'=' * 70}"
puts '5. LOCAL ID SANITIZATION'
puts '=' * 70

sanitize_tests = [
  'Mitsubishi Heavy Industries',
  "O'Brien & Co.",
  '  Multiple   Spaces  ',
  '---Leading-Trailing---',
  'UPPER CASE',
  '',
  nil
]

sanitize_tests.each do |input|
  result = Ammitto::Utils::IriSanitizer.sanitize(input)
  puts "  #{input.inspect.ljust(35)} => #{result}"
end

puts "\n#{'=' * 70}"
puts '6. AVAILABLE LISTS BY SOURCE'
puts '=' * 70

Ammitto::Utils::ListTypesRegistry.all_sources.each do |source|
  lists = Ammitto::Utils::ListTypesRegistry.list_types_for(source)
  next if lists.nil? || lists.empty?

  puts "\n  #{source.upcase}:"
  lists.each do |list_id, info|
    puts "    - #{list_id}: #{info[:name] || info['name']}"
  end
end

puts "\n#{'=' * 70}"
puts '7. NORMALIZED DIRECTORY STRUCTURE'
puts '=' * 70

puts <<~TEXT

  data-cn/processed/
  ├── entities/                      # NORMALIZED - unique per source
  │   ├── marco-rubio.yaml           # Local ID only
  │   ├── mitsubishi-heavy-industries.yaml
  │   └── kawasaki-heavy-industries.yaml
  ├── entries/                       # Links entity to list via list_type field
  │   ├── entry-marco-rubio-anti-sanction.yaml
  │   ├── entry-mitsubishi-import-export.yaml
  │   └── entry-mitsubishi-unreliable.yaml   # Same entity, different list!
  ├── announcements/                 # NORMALIZED - can affect multiple lists
  │   ├── mofcom-2026-11.yaml
  │   └── mfa-2025-01.yaml
  ├── legal_instruments/             # NORMALIZED - can authorize multiple lists
  │   ├── export-control-law.yaml
  │   └── anti-sanction-law.yaml
  ├── lists/                         # List definitions
  │   ├── anti-sanction-list.yaml
  │   ├── import-export-control-list.yaml
  │   └── unreliable-entity-list.yaml
  └── _index.yaml

TEXT

puts "\n#{'=' * 70}"
puts '8. KEY RELATIONSHIPS'
puts '=' * 70

puts <<~TEXT

  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
  │   Entity    │◄────│    Entry    │────►│    List     │
  │ (agnostic)  │     │ (junction)  │     │  (defines)  │
  └─────────────┘     └─────────────┘     └─────────────┘
        │                   │
        │                   │
        ▼                   ▼
  ┌─────────────┐     ┌─────────────┐
  │   Source    │     │Announcement │
  │  Reference  │     │ (agnostic)  │
  └─────────────┘     └─────────────┘

  • An Entity can have multiple Entries (one per list)
  • An Entry links one Entity to one List
  • An Announcement can affect multiple Lists
  • A Legal Instrument can authorize multiple Lists

TEXT

puts "\n#{'=' * 70}"
puts 'Verification Complete'
puts '=' * 70
