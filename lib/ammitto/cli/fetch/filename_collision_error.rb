# frozen_string_literal: true

require_relative '../../errors/base_error'

module Ammitto
  module Cmd
    module Fetch
      # Raised when two records that are not byte-identical would claim
      # the same output filename, so writing them would silently discard
      # one via truncation.
      #
      # A dedicated class rather than a bare `raise "string"`: this
      # module's other refusals (`refuse_collapse`,
      # `previous_harvest_count`) already raise `Ammitto::ParseError`, and
      # a collision is the same kind of finding — the harvest cannot be
      # trusted as-is — so it belongs in the same hierarchy instead of the
      # implicit `RuntimeError` a bare string raise produces.
      class FilenameCollisionError < Ammitto::ParseError
        # @param source [Symbol] the source code the harvest came from
        # @param collisions [Hash{String => Array}] filename => discarded
        #   claimants, as `CollisionAndCollapseGuard#detect_collisions`
        #   returns it
        def initialize(source, collisions)
          super(build_message(source, collisions))
        end

        private

        # @param source [Symbol]
        # @param collisions [Hash{String => Array}]
        # @return [String]
        def build_message(source, collisions)
          detail = collisions.map do |filename, items|
            "#{filename} (also claimed by #{items.map { |item| describe(item) }.join(', ')})"
          end.join('; ')

          "#{source}: #{collisions.size} filename collision(s) would " \
            "discard #{collisions.values.sum(&:size)} record(s): #{detail}"
        end

        # Best-effort label for a record in an error message.
        #
        # A diagnostic must never mask the error it describes, so a record
        # whose own accessors raise, or whose name is unbounded, degrades
        # to a shorter label instead of escaping as an unrelated exception.
        #
        # @param item [Object] the item
        # @return [String]
        def describe(item)
          %i[name full_name vessel_name english_name].each do |attr|
            value = begin
              item.respond_to?(attr) ? item.public_send(attr).to_s.strip : ''
            rescue StandardError
              ''
            end

            return "#{value[0, 80].inspect}..." if value.length > 80
            return value.inspect unless value.empty?
          end

          begin
            item.class.name.to_s
          rescue StandardError
            '(unprintable record)'
          end
        end
      end
    end
  end
end
