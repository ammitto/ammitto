# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module EuVessels
      # One row of the DMA workbook for a vessel: when a measure applies
      # from, and the "Subject to" text naming the measure and regulation,
      # transcribed as DMA publishes it.
      #
      # A vessel carries one of these per row because DMA lists a vessel
      # again when a later act adds a measure (a DPRK vessel first banned
      # from ports and later de-registered) or re-lists it under Annex XLII,
      # and each row is a designation in its own right.
      class Designation < Lutaml::Model::Serializable
        attribute :date_of_application, :date
        attribute :subject_to, :string

        # The order that decides which designation is a vessel's earliest,
        # shared by the workbook merge and the transformer so a file read
        # back from YAML gives the bare IRI to the same row the fetch did.
        # @return [Array]
        def sort_key
          [date_of_application, subject_to]
        end
      end
    end
  end
end
