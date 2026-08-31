# frozen_string_literal: true

require 'lutaml/model'
require_relative 'modification_block'
# Nothing references ModificationLocalizedTitleEntry — not this class,
# not the transformer, not a spec. It was reachable only because it
# shared a file with this one, and this require keeps that true rather
# than deleting a class on a grep. Whether it should exist at all is a
# separate question from where it lives.
require_relative 'modification_localized_title_entry'
require_relative 'modification_announcement_block'

module Ammitto
  module Sources
    module Cn
      # Source model for data-cn YAML measure modification format
      #
      # This model matches the schema defined in data-cn/schemas/cn-measure-modification.yml
      # and is used to parse YAML files from sources/sanction-updates/
      #
      # @example Parsing a modification YAML file
      #   data = YAML.load_file('sources/sanction-updates/20250514.yml')
      #   modification = MeasureModification.from_hash(data)
      #   modification.measure_modifications.modifications.each do |mod|
      #     puts "#{mod.action} - #{mod.target_announcement_id}"
      #   end
      #
      class MeasureModification < Lutaml::Model::Serializable
        attribute :announcement, ModificationAnnouncementBlock
        attribute :measure_modifications, ModificationBlock

        key_value do
          map 'announcement', to: :announcement
          map 'measure_modifications', to: :measure_modifications
        end

        # Get all modifications
        # @return [Array<Modification>]
        def modifications
          measure_modifications&.modifications || []
        end

        # Get all instruments
        # @return [Array<ModificationInstrument>]
        def instruments
          measure_modifications&.instruments || []
        end
      end
    end
  end
end
