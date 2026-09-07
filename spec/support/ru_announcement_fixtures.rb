# frozen_string_literal: true

# Russian announcements in the shape data-ru actually stores.
#
# Lives here rather than inside a `describe` so the model spec and the
# transformer spec share one definition; `spec_helper` already globs
# `spec/support/**/*.rb`.
module RuAnnouncementFixtures
  # The first two parties of `sources/announcements/20220413-1.yml`.
  #
  # Every field is copied from that file on 2026-08-28 — document id,
  # times, URL, both announcement titles, both party titles, both reasons
  # and both name scripts — EXCEPT the two content blocks, which run to
  # 775 and 778 characters. Those carry an exact opening excerpt and
  # nothing else. Excerpt, not sentence: the Russian runs past `с.г.`,
  # which is an abbreviation rather than a full stop, and the English
  # runs past `2022,`. The example asserting content asserts the excerpt.
  #
  # Copied rather than composed: a fixture that agrees with the model
  # instead of with the source is how Canada's element rename went
  # unnoticed for three days. The first draft of this file invented its
  # values while claiming to be a transcription, and the second shortened
  # four fields while claiming to be a copy.
  #
  # @return [String] the YAML document
  def ru_announcement_yaml
    <<~YAML
      ---
      announcement:
        title:
          ru: Заявление МИД России об ответных персональных санкциях в
            отношении конгрессменов США
          en: Foreign Ministry statement regarding response personal
            sanctions against members of the US Congress
        url: https://mid.ru/ru/foreign_policy/news/1809216/
        lang: ru
        publish_date: '2022-04-13'
        publish_time: '21:01'
        authority: ru/ministry-of-foreign-affairs
        publisher: ru/ministry-of-foreign-affairs
        type: ru/ministry-of-foreign-affairs-announcement
        document_id: 806-13-04-2022
        signatory: ru/ministry-of-foreign-affairs
        content:
          ru: В порядке реакции на очередную «волну» антироссийских
            санкций, введенных Администрацией Дж.Байдена 24 марта с.г.
          en: In response to the latest wave of anti-Russia sanctions
            imposed by the Biden Administration on March 24, 2022,
      sanction_details:
        instruments:
        - id: ru/federal-law-114
        entities:
        - name:
            ru: Питер Агилар
            en: Peter Rey Aguilar
          type: individual
          nationality: US
          title:
            ru: член Палаты представителей Конгресса США от
              Демократической партии (шт. Калифорния)
            en: member of the House of Representatives of the US Congress
          effective_date: '2022-04-13'
          sanction_list: черного списка
          reason:
          - ru: За участие в формировании русофобского курса США.
            en: For participation in formulating the Russophobic policy
              of the United States.
          measures:
          - type:
            - entry_ban
            ru: Запрещен въезд в Российскую Федерацию.
            en: Entry into the Russian Federation is prohibited.
        - name:
            ru: Альма Адамс
            en: Alma Shealey Adams
          type: individual
          nationality: US
          title:
            ru: член Палаты представителей от Демократической партии
              (шт. Северная Каролина)
            en: member of the House of Representatives of the US Congress
          effective_date: '2022-04-13'
          sanction_list: черного списка
          reason:
          - ru: За участие в формировании русофобского курса США.
            en: For participation in formulating the Russophobic policy
              of the United States.
          measures:
          - type:
            - entry_ban
            ru: Запрещен въезд в Российскую Федерацию.
            en: Entry into the Russian Federation is prohibited.
    YAML
  end

  # @return [Ammitto::Sources::Ru::Announcement] the copied announcement
  def ru_announcement
    Ammitto::Sources::Ru::Announcement.from_yaml(ru_announcement_yaml)
  end

  # Two parties whose names sanitize to nothing, and a repeated name.
  #
  # Constructed, not copied — but from measured shapes. Every name here
  # is Cyrillic-only, which `IriSanitizer` reduces to the shared literal
  # "unknown"; `20250926.yml` has seven such parties in one announcement
  # and `20230412.yml` has two. The repeated English name is the shape of
  # the three malformed records in `20220427.yml`.
  #
  # @return [Ammitto::Sources::Ru::Announcement] the announcement
  def ru_colliding_announcement
    Ammitto::Sources::Ru::Announcement.from_hash(
      'announcement' => { 'document_id' => '1585-26-09-2025' },
      'sanction_details' => {
        'entities' => [
          { 'name' => { 'ru' => 'Бирн, Джеймс' }, 'type' => 'individual' },
          { 'name' => { 'ru' => 'Дуган, Дэвид' }, 'type' => 'individual' },
          { 'name' => { 'en' => 'Repeated Name' }, 'type' => 'individual',
            'nationality' => 'GB' },
          { 'name' => { 'en' => 'Repeated Name' }, 'type' => 'individual',
            'nationality' => 'US' }
        ]
      }
    )
  end

  # One party, an organization — a branch the corpus does not exercise.
  #
  # Constructed and labelled as such: every one of data-ru's 2,428
  # records is `individual`, so nothing here is copied from a file.
  #
  # @return [Ammitto::Sources::Ru::Announcement] the announcement
  def ru_organization_announcement
    Ammitto::Sources::Ru::Announcement.from_hash(
      'announcement' => { 'document_id' => 'X-1' },
      'sanction_details' => {
        'entities' => [
          { 'name' => { 'en' => 'Some Institute', 'ru' => 'Институт' },
            'type' => 'organization', 'sanction_list' => 'черного списка' }
        ]
      }
    )
  end
end
