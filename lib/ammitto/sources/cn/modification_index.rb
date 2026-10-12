# frozen_string_literal: true

require 'yaml'
require 'date'
require_relative 'measure_modification'
require_relative 'entity'
require_relative '../../status_change'
require_relative '../../notice_reference'

module Ammitto
  module Sources
    module Cn
      # Every measure modification of the CN source, collected before any
      # announcement is transformed so the file order of updates and lists
      # cannot change the output.
      #
      # A modification names its target announcement by document number
      # only, and document numbers repeat across lists, so targets are keyed
      # by (list slug, document number). The list comes from the
      # `<list>-updates` directory the file sits in: the modification files
      # carry no list field of their own.
      #
      # Problems that would leave a modification silently unapplied (an
      # unknown updates directory, a target matching no announcement or
      # more than one, a target date that disagrees with the announcement,
      # an action after a stop) are collected in #errors so the harmonize
      # health gate fails instead.
      class ModificationIndex
        # The current status is left as published; these only describe the
        # history the modification records.
        STATUS_FOR_ACTION = { 'suspend' => 'suspended', 'stop' => 'terminated' }.freeze

        Record = Struct.new(:file, :list, :modification, :announcement, :publish_date, :position)

        # @param updates_dir [String, nil] the data-cn sanction-updates directory
        # @param transformer [Ammitto::Sources::Cn::Transformer]
        # @return [ModificationIndex]
        def self.build(updates_dir, transformer)
          index = new
          return index unless updates_dir && Dir.exist?(updates_dir)

          Dir.children(updates_dir).sort.each do |child|
            dir = File.join(updates_dir, child)
            next unless File.directory?(dir)

            files = Dir.glob(%w[*.yml *.yaml], base: dir).sort.map { |f| File.join(dir, f) }
            code = Entity.list_type_code_for(child.delete_suffix('-updates'))
            if code == 'unknown' || !child.end_with?('-updates')
              index.error(dir, "updates directory #{child} names no known CN list")
              next
            end
            files.each { |file| index.load_file(file, code, transformer) }
          end
          index.finalize!
        end

        def initialize
          @records = Hash.new { |h, k| h[k] = [] }
          @errors = {}
          @matched = Hash.new { |h, k| h[k] = Set.new }
          @history = {}
        end

        # @return [Array<String>] one line per problem, file name first
        def errors
          (@errors.values + match_errors).sort
        end

        def error(file, message)
          # Both transform passes reach the date check; key by full path so
          # that dedups without merging same-named files from other dirs.
          @errors[[file, message]] = "#{File.basename(file)}: #{message}"
        end

        def load_file(file, code, transformer)
          list = Transformer::LIST_TYPE_MAPPING.fetch(code)[:list_slug]
          data = YAML.safe_load_file(file, permitted_classes: [Date, Time], aliases: true)
          result = transformer.transform_modification(MeasureModification.from_hash(data), list_type_code: code)
          publish_date = result[:official_announcement]&.publish_date
          result[:modifications].each_with_index do |mod, position|
            key = [list, mod.target_announcement_document_id]
            @records[key] << Record.new(file, list, mod, result[:official_announcement], publish_date, position)
          end
        rescue StandardError => e
          error(file, e.message)
        end

        def finalize!
          @records.each do |key, records|
            # Two modifications of one target in one notice share an id, and
            # sort_by is not stable, so file and position settle the order.
            records.sort_by! do |r|
              [r.modification.effective_date.to_s, r.publish_date.to_s, r.modification.id.to_s, r.file, r.position]
            end
            @history[key] = status_changes(records)
          end
          self
        end

        # Attach every modification of the announcement these entries came
        # from, with the status history it implies. The published status is
        # not touched.
        # @param entries [Array<Ammitto::SanctionEntry>]
        # @param list [String, nil] list slug the entries are published under
        # @param announcement [Ammitto::OfficialAnnouncement]
        def attach(entries, list, announcement)
          key = [list, announcement&.document_id]
          records = @records.fetch(key, nil)
          return unless records

          # Identity must survive the second transform pass, which builds new
          # objects and may mint different IRIs, yet tell apart two files that
          # share url and date.
          @matched[key] << [announcement.url, announcement.publish_date, entries.map(&:reference_number).sort]
          records.each { |r| check_target_date(r, announcement) }
          entries.each do |entry|
            entry.modifications = records.map(&:modification)
            entry.status_history = @history[key].dup
          end
        end

        private

        def check_target_date(record, announcement)
          target = record.modification.target_announcement_date
          return if target.nil? || target == announcement.publish_date

          error(record.file, "modification target #{record.list}/#{record.modification.target_announcement_document_id} " \
                             "dated #{target} but the announcement was published #{announcement.publish_date}")
        end

        def match_errors
          @records.flat_map do |(list, doc), records|
            matches = @matched[[list, doc]].size
            next [] if matches == 1

            problem = matches.zero? ? 'matches no announcement' : "matches #{matches} announcements"
            records.map(&:file).uniq.map { |f| "#{File.basename(f)}: modification target #{list}/#{doc} #{problem}" }
          end
        end

        def status_changes(records)
          previous = nil
          records.filter_map do |record|
            change = status_change(record, previous)
            previous = change if change
            change
          end
        end

        def status_change(record, previous)
          mod = record.modification
          to_status = STATUS_FOR_ACTION[mod.action]
          return invalid(record, "action #{mod.action.inspect} is not suspend or stop") unless to_status
          return invalid(record, 'conflicts with another action the same day') if conflicting?(previous, mod, to_status)
          return invalid(record, 'follows a stop of the same announcement') if previous&.termination?

          Ammitto::StatusChange.new(
            date: mod.effective_date.to_s,
            from_status: status_before(previous, mod.effective_date),
            to_status: to_status,
            suspension_end_date: to_status == 'suspended' ? mod.until_date : nil,
            notice_reference: notice_reference(record.announcement)
          )
        end

        def conflicting?(previous, mod, to_status)
          previous && previous.date == mod.effective_date.to_s && previous.to_status != to_status
        end

        # A suspension that lapsed before this change took effect left the
        # measures in force again.
        def status_before(previous, date)
          return 'active' unless previous
          return 'active' if previous.suspension? && previous.suspension_end_date &&
                             date && previous.suspension_end_date < date

          previous.to_status
        end

        def invalid(record, message)
          error(record.file, "modification of #{record.list}/#{record.modification.target_announcement_document_id} " \
                             "effective #{record.modification.effective_date} #{message}")
          nil
        end

        def notice_reference(announcement)
          return nil unless announcement

          Ammitto::NoticeReference.new(
            notice_number: announcement.document_id,
            notice_date: announcement.publish_date,
            notice_title: announcement.title,
            notice_url: announcement.url
          )
        end
      end
    end
  end
end
