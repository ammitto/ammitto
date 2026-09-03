# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/ru'

# Reading an announcement, rather than one flat record at a time.
#
# `Sources::Ru::Transformer` models `{ russian_name:, english_name: }`
# records that data-ru has never stored. What it stores is a document per
# MID announcement with the parties named inside — so harmonize ingested
# one entity per file and none of the people in them.
RSpec.describe Ammitto::Sources::Ru::AnnouncementTransformer do
  include RuAnnouncementFixtures

  subject(:transformer) { described_class.new }

  let(:result) { transformer.transform_announcement(ru_announcement) }

  describe 'the parties named' do
    it 'produces one entity and one entry per party' do
      expect(result[:entities].length).to eq(2)
      expect(result[:entries].length).to eq(2)
    end

    it 'makes a person of an individual' do
      expect(result[:entities].map(&:entity_type)).to eq(%w[person person])
    end

    it 'makes an organization of one, a branch the corpus has none of' do
      transformed =
        transformer.transform_announcement(ru_organization_announcement)

      expect(transformed[:entities].first.entity_type).to eq('organization')
    end

    it 'carries both scripts of a name, English primary' do
      names = result[:entities].first.names

      expect(names.map(&:full_name))
        .to eq(['Peter Rey Aguilar', 'Питер Агилар'])
      expect(names.map(&:script)).to eq(%w[Latn Cyrl])
      expect(names.first.is_primary).to be true
    end

    it 'records the nationality MID states' do
      # data-cn fills gender here; MID publishes nationality and never
      # gender, so the other field stays empty rather than being guessed.
      expect(result[:entities].first.nationalities).to eq(['US'])
    end

    it 'links each entity to its entry, in both representations' do
      entity = result[:entities].first

      # `sanction_entry_ids` alone would also be satisfied by setting it
      # at construction, which leaves `sanction_entries` empty.
      expect(entity.sanction_entry_ids).to eq([result[:entries].first.id])
      expect(entity.sanction_entries).to eq([result[:entries].first])
    end
  end

  describe 'the entry' do
    subject(:entry) { result[:entries].first }

    it 'names the regime the list maps to' do
      expect(entry.regime.code).to eq('RU_STOP_LIST')
    end

    it 'takes its effects from the measures, not from an assumption' do
      expect(entry.effects.map(&:effect_type)).to eq(['entry_ban'])
    end

    it 'keeps the reason in both languages' do
      expect(entry.reasons.first.description.map(&:language)).to eq(%w[ru en])
    end

    it 'dates the period from the party, not the announcement' do
      expect(entry.period.effective_date.to_s).to eq('2022-04-13')
    end

    it 'cites the instrument the announcement acts under' do
      expect(entry.legal_citations.map(&:legal_instrument_id))
        .to eq(['https://www.ammitto.org/legal_instrument/ru/federal-law-114'])
    end

    it 'puts the list in the entry IRI, so two lists cannot collide' do
      expect(entry.id).to include('/entry/ru/stop-list/')
    end
  end

  describe 'the announcement itself' do
    it 'becomes an official announcement with its own identifier' do
      expect(result[:official_announcement].document_id)
        .to eq('806-13-04-2022')
    end

    it 'keeps the translation the document declares as its language' do
      # The block says `lang: ru`, and OfficialAnnouncement holds one
      # string, so the Russian text is the one that survives.
      expect(result[:official_announcement].content)
        .to eq('В порядке реакции на очередную «волну» антироссийских ' \
               'санкций, введенных Администрацией Дж.Байдена 24 марта с.г.')
    end
  end

  describe 'a group' do
    it 'gathers parties named in one announcement' do
      expect(result[:group].entity_count).to eq(2)
      expect(result[:group].entry_ids).to eq(result[:entries].map(&:id))
    end

    it 'is stamped onto every entry it gathers' do
      expect(result[:entries].map(&:group_id).uniq).to eq([result[:group].id])
    end

    it 'is absent when an announcement names only one party' do
      one = Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => 'X-1' },
        'sanction_details' => {
          'entities' => [{ 'name' => { 'en' => 'Someone' },
                           'type' => 'individual' }]
        }
      )

      expect(transformer.transform_announcement(one)[:group]).to be_nil
    end
  end

  describe 'parties whose names cannot tell them apart' do
    # `IriSanitizer` reduces a Cyrillic-only name to the shared literal
    # "unknown". Seven distinct people in `20250926.yml` and two in
    # `20230412.yml` took that same IRI, and the exporter kept the last
    # one written: nine sanctioned individuals disappeared from a
    # sanctions dataset without anything reporting it.
    subject(:transformed) do
      transformer.transform_announcement(ru_colliding_announcement)
    end

    it 'gives every party its own identifier' do
      ids = transformed[:entities].map(&:id)

      expect(ids.uniq.length).to eq(4)
    end

    it 'gives every entry its own identifier too' do
      ids = transformed[:entries].map(&:id)

      expect(ids.uniq.length).to eq(4)
    end

    it 'keeps the readable part and appends only what is needed' do
      first = transformed[:entities].first.id

      expect(first).to include('1585-26-09-2025-unknown-')
    end

    it 'derives the suffix from content, so it survives a reordering' do
      reordered = Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => '1585-26-09-2025' },
        'sanction_details' => {
          'entities' => ru_colliding_announcement.entities.reverse.map(&:to_hash)
        }
      )

      expect(transformer.transform_announcement(reordered)[:entities]
               .map(&:id).sort)
        .to eq(transformed[:entities].map(&:id).sort)
    end
  end

  describe 'a measure imposing more than one thing' do
    it 'becomes one effect per type, where CN keeps only the first' do
      # No record in data-ru carries two, so this is constructed.
      many = Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => 'X-2' },
        'sanction_details' => {
          'entities' => [{ 'name' => { 'en' => 'Someone' },
                           'type' => 'individual',
                           'measures' => [{ 'type' => %w[entry_ban
                                                         asset_freeze] }] }]
        }
      )

      effects = transformer.transform_announcement(many)[:entries]
                           .first.effects

      expect(effects.map(&:effect_type)).to eq(%w[entry_ban asset_freeze])
    end
  end

  describe 'an instrument with a blank identifier' do
    it 'falls back to the law rather than raising' do
      blank = Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => 'X-9' },
        'sanction_details' => {
          'instruments' => [{ 'id' => '', 'law' => 'Decree 123' }],
          'entities' => [{ 'name' => { 'en' => 'Someone' },
                           'type' => 'individual' }]
        }
      )

      citations = transformer.transform_announcement(blank)[:legal_citations]

      expect(citations.length).to eq(1)
      expect(citations.first.legal_instrument_id).to include('decree-123')
    end
  end

  describe 'an announcement whose parties were lost in extraction' do
    # Real shape: data-ru sources/announcements/20220407.yml records an
    # empty entity list while its own text lists the people by number.
    def announcement_listing(text, entities: [])
      Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => '755-07-04-2022',
                            'content' => { 'ru' => text } },
        'sanction_details' => { 'entities' => entities }
      )
    end

    let(:party_list) do
      "Ниже следует список граждан Австралии.\n\n" \
        "1        Скотт Моррисон (Scott Morrison)    премьер-министр\n\n" \
        "2        Барнаби Джойс (Barnaby Joyce)       заместитель\n\n" \
        '3        Карен Эндрюс (Karen Andrews)       министр'
    end

    it 'refuses rather than publishing an announcement against nobody' do
      expect { transformer.transform_announcement(announcement_listing(party_list)) }
        .to raise_error(Ammitto::ParseError, /parsed no parties.*lists 3 of them/m)
    end

    it 'lets a statement that genuinely names no one through' do
      prose = 'Заявление МИД России о недружественных действиях. ' \
              'Никаких персональных санкций не вводится.'

      result = transformer.transform_announcement(announcement_listing(prose))

      expect(result[:entities]).to eq([])
      expect(result[:entries]).to eq([])
    end

    it 'says nothing when the parties did parse' do
      listed = announcement_listing(
        party_list,
        entities: [{ 'name' => { 'en' => 'Scott Morrison' },
                     'type' => 'individual' }]
      )

      expect(transformer.transform_announcement(listed)[:entities].length)
        .to eq(1)
    end
  end

  describe 'a Cyrillic name filed under the English field' do
    it 'reports the script the text is in, not the field it came from' do
      # Real shape: seven parties in
      # data-ru sources/announcements/20250926.yml carry an empty `ru`
      # and a Cyrillic name under `en`. This is one of them.
      misfiled = Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => 'X-5' },
        'sanction_details' => {
          'entities' => [{ 'name' => { 'en' => 'Бирн, Джеймс', 'ru' => '' },
                           'type' => 'individual' }]
        }
      )

      names = transformer.transform_announcement(misfiled)[:entities]
                         .first.names

      expect(names.length).to eq(1)
      expect(names.first.full_name).to eq('Бирн, Джеймс')
      expect(names.first.script).to eq('Cyrl')
      # The `en` field still decides which name leads, whatever script
      # the text turns out to be in.
      expect(names.first.is_primary).to be(true)
    end

    it 'still reports Latn for a romanised name' do
      normal = Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => 'X-6' },
        'sanction_details' => {
          'entities' => [{ 'name' => { 'en' => 'Byrne, James',
                                       'ru' => 'Бирн, Джеймс' },
                           'type' => 'individual' }]
        }
      )

      names = transformer.transform_announcement(normal)[:entities]
                         .first.names

      expect(names.map(&:script)).to eq(%w[Latn Cyrl])
      expect(names.map(&:is_primary)).to eq([true, false])
    end
  end

  describe 'a measure that says something but does not say what' do
    it 'keeps the wording and claims no type' do
      untyped = Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => 'X-3' },
        'sanction_details' => {
          'entities' => [{ 'name' => { 'en' => 'Someone' },
                           'type' => 'individual',
                           'measures' => [{ 'en' => 'Measures apply.' }] }]
        }
      )

      effects = transformer.transform_announcement(untyped)[:entries]
                           .first.effects

      # The description is evidence and survives; the category is not
      # stated and is not guessed.
      expect(effects.length).to eq(1)
      expect(effects.first.effect_type).to be_nil
      expect(effects.first.description.map(&:value)).to eq(['Measures apply.'])
    end

    it 'produces nothing when it says neither a type nor a word' do
      silent = Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => 'X-4' },
        'sanction_details' => {
          'entities' => [{ 'name' => { 'en' => 'Someone' },
                           'type' => 'individual',
                           'measures' => [{}] }]
        }
      )

      expect(transformer.transform_announcement(silent)[:entries]
               .first.effects).to eq([])
    end
  end

  describe 'a party with nothing recorded against it' do
    it 'produces an entry that claims no effect' do
      bare = Ammitto::Sources::Ru::Announcement.from_hash(
        'announcement' => { 'document_id' => 'X-1' },
        'sanction_details' => {
          'entities' => [{ 'name' => { 'en' => 'Someone' },
                           'type' => 'individual' }]
        }
      )

      transformed = transformer.transform_announcement(bare)

      expect(transformed[:entities].length).to eq(1)
      expect(transformed[:entries].first.reasons).to eq([])
      # Not ['entry_ban']. The announcement records no measure against
      # this party, and an entry ban it never stated must not appear
      # against a named person.
      expect(transformed[:entries].first.effects).to eq([])
    end
  end
end
