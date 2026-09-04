# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ch
      # Date of birth in Swiss sanctions list
      class DayMonthYear < Lutaml::Model::Serializable
        attribute :day, :integer
        attribute :month, :integer
        attribute :year, :integer

        xml do
          root 'day-month-year'
          map_attribute 'day', to: :day
          map_attribute 'month', to: :month
          map_attribute 'year', to: :year
        end

        yaml do
          map 'day', to: :day
          map 'month', to: :month
          map 'year', to: :year
        end

        def to_iso_date
          return nil unless year
          # Year-only or year-month dates must not render as "1975-00-00" —
          # emit the known precision only
          return year.to_s unless month
          return "#{year}-#{month.to_s.rjust(2, '0')}" unless day

          "#{year}-#{month.to_s.rjust(2, '0')}-#{day.to_s.rjust(2, '0')}"
        end
      end
    end
  end
end
