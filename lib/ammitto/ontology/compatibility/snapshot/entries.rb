# frozen_string_literal: true

require_relative '../snapshot'

module Ammitto
  module Ontology
    module Compatibility
      # Compare the normalized entry sequence as a multiset. Matching uses
      # Ruby equality directly, so neither encoding nor string formatting
      # changes the values, and equal identity entries retain multiplicity.
      # Snapshot has its own file so both definitions satisfy one class per file.
      class Snapshot::Entries < Array # rubocop:disable Style/ClassAndModuleChildren
        def ==(other)
          return false unless other.is_a?(Snapshot.const_get(:Entries, false)) && size == other.size

          remaining = other.to_a
          all? do |entry|
            index = remaining.index { |candidate| entry == candidate }
            next false unless index

            remaining.delete_at(index)
            true
          end
        end
      end
      Snapshot.private_constant :Entries
    end
  end
end
