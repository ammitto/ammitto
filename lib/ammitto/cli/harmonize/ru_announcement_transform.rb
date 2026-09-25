# frozen_string_literal: true

module Ammitto
  module Cmd
    module Harmonize
      # RU announcement handling, kept apart from MultiShapeSourceTransforms
      # for the same reason JpAnnouncementTransform is: it reads a whole
      # document rather than one record, and would push that module past
      # the Metrics/ModuleLength budget.
      module RuAnnouncementTransform
        private

        # Transform one RU announcement and everyone it names.
        #
        # A file with an `announcement` block but no `sanction_details` is
        # refused rather than handed to the per-entity path: that path reads
        # it as one nameless organisation, actively entry-banned, which is a
        # sanction nobody published.
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Array<Hash>] one entity/entry pair per party named
        # @raise [SourceTransforms::AnnouncementFormatError] when the file
        #   has no sanction_details
        def transform_ru_announcement(transformer, data)
          unless data.key?('sanction_details')
            raise SourceTransforms::AnnouncementFormatError,
                  'RU announcement has no sanction_details, so it names ' \
                  'no parties; refusing to harmonize this file'
          end

          announcement = Ammitto::Sources::Ru::Announcement.from_hash(data)
          result = transformer.transform_announcement(announcement)

          @exporter.add_group(result[:group], source: :ru) if result[:group]

          result[:entities].zip(result[:entries]).map do |entity, entry|
            {
              entity: entity_to_hash(entity),
              entry: entry_to_hash(entry)
            }
          end
        end
      end
    end
  end
end
