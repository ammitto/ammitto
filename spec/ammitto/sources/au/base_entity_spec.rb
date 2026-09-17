# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au/individual'
require 'ammitto/sources/au/organization'
require 'ammitto/sources/au/vessel'

# Exercised through the three real subclasses rather than instantiating
# BaseEntity directly, since #identifier lives here so all three answer
# it identically — the same reason #primary_name and the alias helpers
# above are tested that way nowhere near their own class files.
RSpec.describe Ammitto::Sources::Au::BaseEntity do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  #
  # The old `identifier_candidates` case tried `item.reference` then
  # `item.id` for every AU item, but no class in this hierarchy has ever
  # defined `id` — confirmed by reading this file and its three
  # subclasses, and by calling `.id` on a real instance, which raises
  # NoMethodError. That second candidate was live-broken: it raised
  # rather than falling through, on every real AU item whose reference
  # was blank. This class drops `id` rather than reproducing it.
  describe '#identifier' do
    it 'is reference when present, for an Individual' do
      individual = Ammitto::Sources::Au::Individual.new(reference: 'AU9')

      expect(individual.identifier).to eq('AU9')
    end

    it 'is reference when present, for an Organization' do
      organization = Ammitto::Sources::Au::Organization.new(reference: 'AU10')

      expect(organization.identifier).to eq('AU10')
    end

    it 'is reference when present, for a Vessel' do
      vessel = Ammitto::Sources::Au::Vessel.new(reference: 'AU11')

      expect(vessel.identifier).to eq('AU11')
    end

    it 'is nil, not a NoMethodError, when reference is blank' do
      individual = Ammitto::Sources::Au::Individual.new(reference: nil)

      expect { individual.identifier }.not_to raise_error
      expect(individual.identifier).to be_nil
    end

    it 'treats whitespace as absent, not as an identifier' do
      individual = Ammitto::Sources::Au::Individual.new(reference: '   ')

      expect(individual.identifier).to be_nil
    end
  end
end
