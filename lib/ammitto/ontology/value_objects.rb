# frozen_string_literal: true

# Value Objects for the Ammitto Sanctions Ontology
#
# Value objects are immutable data containers that represent
# attributes and properties of entities. They have no identity
# of their own - two value objects with the same attributes are
# considered equal.

require_relative 'value_objects/name_variant'
require_relative 'value_objects/address'
require_relative 'value_objects/identification'
require_relative 'value_objects/birth_info'
require_relative 'value_objects/legal_instrument'
require_relative 'value_objects/sanction_effect'
require_relative 'value_objects/temporal_period'
require_relative 'value_objects/contact_info'
require_relative 'value_objects/entity_link'
require_relative 'value_objects/source_reference'
require_relative 'value_objects/tonnage'

module Ammitto
  module Ontology
    # Namespace for all value objects
    module ValueObjects
    end
  end
end
