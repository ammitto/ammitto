# frozen_string_literal: true

# Models autoloader for Ammitto
#
# Uses Ruby's autoload for lazy loading. Each class is defined in its own file
# following Ruby convention: ammitto/{class_name}.rb defines Ammitto::{ClassName}

module Ammitto
  # Value objects (no identity, immutable)
  autoload :NameVariant, "#{__dir__}/name_variant"
  autoload :Address, "#{__dir__}/address"
  autoload :Identification, "#{__dir__}/identification"
  autoload :BirthInfo, "#{__dir__}/birth_info"
  autoload :ContactInfo, "#{__dir__}/contact_info"
  autoload :EntityLink, "#{__dir__}/entity_link"
  autoload :SourceReference, "#{__dir__}/source_reference"
  autoload :Tonnage, "#{__dir__}/tonnage"

  # Core entities (objects with identity)
  autoload :Entity, "#{__dir__}/entity"
  autoload :PersonEntity, "#{__dir__}/person_entity"
  autoload :OrganizationEntity, "#{__dir__}/organization_entity"
  autoload :VesselEntity, "#{__dir__}/vessel_entity"
  autoload :AircraftEntity, "#{__dir__}/aircraft_entity"

  # Sanction models
  autoload :Authority, "#{__dir__}/authority"
  autoload :SanctionRegime, "#{__dir__}/sanction_regime"
  autoload :SanctionEffect, "#{__dir__}/sanction_effect"
  autoload :SanctionReason, "#{__dir__}/sanction_reason"
  autoload :ListType, "#{__dir__}/list_type"
  autoload :TemporalPeriod, "#{__dir__}/temporal_period"
  autoload :StatusChange, "#{__dir__}/status_change"
  autoload :NoticeReference, "#{__dir__}/status_change" # Same file as StatusChange
  autoload :LegalInstrument, "#{__dir__}/legal_instrument"
  autoload :OfficialAnnouncement, "#{__dir__}/official_announcement"
  autoload :RawSourceData, "#{__dir__}/raw_source_data"
  autoload :SanctionEntry, "#{__dir__}/sanction_entry"
end
