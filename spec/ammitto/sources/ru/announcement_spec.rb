# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/ru'

# The document data-ru stores, and the class that reads it.
#
# `lib/ammitto/sources/ru.rb` documented `Ru::Announcement` in three worked
# examples from before this class existed, against a flat
# `{ russian_name:, english_name: }` entity shape. The repository has never
# stored that shape: it stores one file per MID announcement with the
# parties named inside, `name` keyed by language — the same schema data-cn
# uses and publishes 322 entities from.
RSpec.describe Ammitto::Sources::Ru::Announcement do
  # Two classes held this name, in two files with incompatible schemas, so
  # whichever loaded last won: after a plain `require "ammitto"` the
  # constant resolved to the flat stop-list model and the announcement
  # models were unreachable. The other is `ListAnnouncement` now.
  describe 'the name the constant resolves to' do
    it 'is the announcement-file model, not the flat stop-list one' do
      expect(described_class.attributes.keys)
        .to contain_exactly(:announcement, :sanction_details)
    end

    it 'leaves the flat stop-list model reachable under its own name' do
      expect(Ammitto::Sources::Ru::ListAnnouncement.attributes.keys)
        .to include(:number, :list_type, :entities)
    end
  end

  include RuAnnouncementFixtures

  subject(:announcement) { ru_announcement }

  describe 'the announcement block' do
    it 'reads a title keyed by language' do
      # data-cn writes a list of single-language maps here and data-ru
      # writes one map; the repositories genuinely differ.
      expect(announcement.announcement.title['en'])
        .to eq('Foreign Ministry statement regarding response personal ' \
               'sanctions against members of the US Congress')
    end

    it 'reads content keyed by language, where data-cn has a bare string' do
      expect(announcement.announcement.content['ru'])
        .to eq('В порядке реакции на очередную «волну» антироссийских ' \
               'санкций, введенных Администрацией Дж.Байдена 24 марта с.г.')
    end

    it 'carries the document identifier and date' do
      expect(announcement.document_id).to eq('806-13-04-2022')
      expect(announcement.publish_date).to eq('2022-04-13')
    end
  end

  describe 'the parties it names' do
    it 'reads every one of them' do
      expect(announcement.entities.length).to eq(2)
    end

    it 'reads both scripts of a name' do
      person = announcement.entities.first

      expect(person.russian_name).to eq('Питер Агилар')
      expect(person.english_name).to eq('Peter Rey Aguilar')
    end

    it 'distinguishes a person from an organization' do
      # Every record in data-ru is `individual`, so the organization here
      # is constructed rather than copied.
      expect(announcement.entities).to all(be_person)
      expect(ru_organization_announcement.entities.first).to be_organization
    end

    it 'reads the nationality data-cn does not carry' do
      expect(announcement.entities.first.nationality).to eq('US')
    end

    it 'reads a reason in both languages' do
      reason = announcement.entities.first.reason.first

      expect(reason['en'])
        .to eq('For participation in formulating the Russophobic policy ' \
               'of the United States.')
      expect(reason['ru'])
        .to eq('За участие в формировании русофобского курса США.')
    end

    it 'reads the measures and their types' do
      measure = announcement.entities.first.measures.first

      expect(measure.type).to eq(['entry_ban'])
      expect(measure.english_description)
        .to eq('Entry into the Russian Federation is prohibited.')
    end
  end

  describe 'the list a party is on' do
    it 'resolves the label MID actually publishes' do
      # Every one of data-ru's records reads "черного списка", the
      # genitive the announcements are written in.
      expect(announcement.entities.first.list_type_code).to eq('stop_list')
    end

    it 'resolves the other inflections of the same list' do
      ['чёрного списка', 'черный список', 'стоп-лист'].each do |label|
        entity = Ammitto::Sources::Ru::Entity.new(sanction_list: label)

        expect(entity.list_type_code).to eq('stop_list')
      end
    end

    it 'says unknown rather than guessing at a label it does not know' do
      entity = Ammitto::Sources::Ru::Entity.new(sanction_list: 'нечто иное')

      expect(entity.list_type_code).to eq('unknown')
    end
  end

  describe 'the instruments it cites' do
    it 'reads them' do
      expect(announcement.instruments.map(&:id)).to eq(['ru/federal-law-114'])
    end
  end

  describe 'a document with no sanction_details at all' do
    it 'has no entities rather than raising' do
      bare = described_class.from_yaml("---\nannouncement:\n  url: x\n")

      expect(bare.entities).to eq([])
      expect(bare.instruments).to eq([])
    end
  end
end
