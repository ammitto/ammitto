# frozen_string_literal: true

module Ammitto
  module Sources
    # Guards hand-written from_hash readers against container values
    # landing in scalar slots.
    #
    # Models deserialized by Lutaml never need this: a collection in a
    # non-collection attribute raises CollectionTrueMissingError, and
    # from_yaml runs the same check. The two hand-written from_hash
    # readers (Jp::Entity, UnVessels::Vessel) assign straight from the
    # hash and had no equivalent, so an Array survived, stringified, and
    # sanitized into a colliding IRI: an id of ["a", "b"] and an id of
    # "a-b" both become entity/jp/jp-a-b, merging two distinct designees
    # into one record — the exact collapse this pipeline must refuse.
    #
    # Array rejection restores the from_yaml behaviour these readers
    # replaced. Hash is rejected on the same grounds even though
    # from_yaml stringifies it, because it flattens into a colliding
    # identifier the same way and is never a valid scalar value.
    module ScalarField
      # Read a field that must hold a single value.
      #
      # @param data [Hash] source data
      # @param field [String] key to read
      # @return [Object, nil] the value, unchanged
      # @raise [ArgumentError] when the value is an Array or a Hash
      def fetch_scalar(data, field)
        value = data[field]
        return value unless value.is_a?(Array) || value.is_a?(Hash)

        raise ArgumentError,
              "#{field} must hold a single value, got #{value.class} " \
              '— a container here flattens into a colliding identifier'
      end
    end
  end
end
