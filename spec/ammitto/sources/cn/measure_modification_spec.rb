# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'ammitto/sources/cn/measure_modification'
require 'ammitto/sources/cn/transformer'

# The shape data-cn publishes under sources/sanction-updates/: a localized
# title list and the same announcement keys as an announcement file.
module CnMeasureModificationSpecData
  def modification_hash
    {
      'announcement' => {
        'title' => [{ 'zh-Hans' => '商务部新闻发言人答记者问', 'en' => 'Spokesperson answers questions' }],
        'url' => 'https://www.mofcom.gov.cn/example.html',
        'lang' => 'zh-Hans',
        'publish_date' => '2025-05-14',
        'publish_time' => '22:00',
        'authority' => 'cn/ministry-of-commerce',
        'type' => 'cn/ministry-of-commerce-spokesperson-speech',
        'document_id' => '2025-05-14-22-00',
        'signatory' => 'cn/ministry-of-commerce',
        'content' => '有记者问'
      },
      'measure_modifications' => {
        'instruments' => [{ 'id' => 'cn/npc-anti-foreign-sanctions-law' }],
        'modifications' => [
          { 'action' => 'suspend', 'target_announcement_id' => '〔2025〕7号',
            'target_announcement_date' => '2025-04-04', 'effective_date' => '2025-05-14' }
        ]
      }
    }
  end
end

RSpec.describe Ammitto::Sources::Cn::MeasureModification do
  include CnMeasureModificationSpecData

  let(:modification) { described_class.from_hash(modification_hash) }

  it 'reads a localized title list' do
    expect(modification.announcement.chinese_title).to eq('商务部新闻发言人答记者问')
    expect(modification.announcement.english_title).to eq('Spokesperson answers questions')
  end

  it 'reads a bare string title, which the schema also allows, as the Chinese title' do
    data = modification_hash.merge('announcement' => modification_hash['announcement'].merge('title' => '公告'))

    expect(described_class.from_hash(data).announcement).to have_attributes(chinese_title: '公告', english_title: nil)
  end

  [[{ 'zh-Hans' => '公告', 'en' => 'Notice' }], '公告'].each do |title|
    it "writes the title back as it read #{title.inspect}" do
      data = modification_hash.merge('announcement' => modification_hash['announcement'].merge('title' => title))

      expect(described_class.from_hash(data).to_hash['announcement']['title']).to eq(title)
    end
  end

  it 'writes no title key for an announcement that has none' do
    data = modification_hash.merge('announcement' => modification_hash['announcement'].except('title'))

    expect(described_class.from_hash(data).to_hash['announcement']).not_to have_key('title')
  end

  it 'reads each language from a title list split into one map per language' do
    title = [{ 'en' => 'Spokesperson answers questions' }, { 'zh-Hans' => '商务部新闻发言人答记者问' }]
    data = modification_hash.merge('announcement' => modification_hash['announcement'].merge('title' => title))

    expect(described_class.from_hash(data).announcement).to have_attributes(
      chinese_title: '商务部新闻发言人答记者问', english_title: 'Spokesperson answers questions'
    )
  end

  it 'passes the repository schema for modification files' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sanction-updates', 'unreliable-entity-list-updates', '20250514.yml')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, modification_hash.to_yaml)
      validator = Ammitto::Data::China::Validator.new

      expect(validator.validate(path)).to be(true), validator.errors.inspect
    end
  end

  it 'reads the announcement document_id, type and signatory' do
    expect(modification.announcement).to have_attributes(
      document_id: '2025-05-14-22-00',
      type: 'cn/ministry-of-commerce-spokesperson-speech',
      signatory: 'cn/ministry-of-commerce'
    )
  end

  it 'transforms into an announcement named by its document_id' do
    result = Ammitto::Sources::Cn::Transformer.new.transform_modification(modification)

    expect(result[:official_announcement].id).to eq('https://www.ammitto.org/announcement/cn/2025-05-14-22-00')
    expect(result[:modifications].size).to eq(1)
  end
end
