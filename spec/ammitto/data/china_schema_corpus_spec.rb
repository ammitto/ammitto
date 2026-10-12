# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'ammitto'
require 'ammitto/data/china'
require 'ammitto/sources/cn/entity'

# `ammitto validate china` rejected most of the files in data-cn. The
# announcement schema listed the Chinese list labels while the corpus writes
# the cn/... ids the gem maps; legal instruments carry authority/publisher
# like announcements do; and supporting/sanction-lists.yml was checked as an
# announcement because its name contains the sanction-lists directory.
RSpec.describe 'China schemas against the data-cn layout' do
  let(:validator) { Ammitto::Data::China::Validator.new }

  def announcement(list)
    {
      'announcement' => {
        'title' => [{ 'zh-Hans' => '公告', 'en' => 'Announcement' }],
        'url' => 'https://www.mofcom.gov.cn/a.html',
        'lang' => 'zh-Hans',
        'publish_date' => '2025-03-04',
        'authority' => 'cn/unreliable-entity-list-working-mechanism',
        'publisher' => 'cn/ministry-of-commerce',
        'type' => 'cn/unreliable-entity-list-working-mechanism-announcement',
        'document_id' => '〔2025〕6号',
        'signatory' => 'cn/unreliable-entity-list-working-mechanism',
        'content' => '公告'
      },
      'sanction_details' => {
        'instruments' => [{ 'id' => 'cn/npc-anti-foreign-sanctions-law' }],
        'entities' => [{
          'name' => { 'zh-Hans' => '因美纳公司', 'en' => 'Illumina, Inc.' },
          'type' => 'organization',
          'effective_date' => '2025-03-04',
          'sanction_list' => list,
          'reason' => [{ 'zh-Hans' => '理由' }],
          'measures' => [{ 'type' => ['prohibit_export_specific_product'], 'zh-Hans' => '禁止' }]
        }]
      }
    }
  end

  def legal_instrument(extra = {})
    {
      'id' => 'cn/npc-anti-foreign-sanctions-law',
      'title' => [{ 'zh-Hans' => '中华人民共和国反外国制裁法' }],
      'authority' => 'cn/npc-standing-committee',
      'publisher' => 'cn/npc',
      'content' => [{ 'type' => 'clause', 'index' => 1, 'label' => '第一条', 'content' => ['条文'] }]
    }.merge(extra)
  end

  def registry(id)
    { 'sanction_lists' => [{ 'id' => id, 'name' => { 'zh-Hans' => '反制裁清单', 'en' => 'Anti-Sanction List' } }] }
  end

  def valid?(relative, data)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sources', relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, data.to_yaml)
      validator.validate(path)
    end
  end

  %w[cn/anti-sanction-list cn/unreliable-entity-list cn/export-control-list].each do |list|
    it "accepts sanction_list #{list}, as data-cn writes it" do
      expect(valid?('sanction-lists/x/202501.yml', announcement(list))).to be true
    end
  end

  it 'still rejects a sanction_list the gem cannot map' do
    expect(valid?('sanction-lists/x/202501.yml', announcement('cn/no-such-list'))).to be false
  end

  it 'lists only values Entity maps to a list type, and every cn/ id it maps' do
    enum = YAML.safe_load_file(File.join(Ammitto::Data::China::SchemaLoader::SCHEMAS_DIR, 'cn-announcement.yml'))
               .dig('properties', 'sanction_details', 'properties', 'entities', 'items',
                    'properties', 'sanction_list', 'enum')
    codes = Ammitto::Sources::Cn::Entity::LIST_TYPE_CODES

    expect(enum.map { |v| Ammitto::Sources::Cn::Entity.list_type_code_for(v) }).not_to include('unknown')
    expect(enum).to include(*codes.keys.map { |k| k.ascii_only? ? "cn/#{k}" : k })
  end

  it 'accepts authority and publisher on a legal instrument' do
    expect(valid?('legal-instruments/law.yml', legal_instrument)).to be true
  end

  it 'still rejects an unknown legal instrument key' do
    expect(valid?('legal-instruments/law.yml', legal_instrument('authoritee' => 'x'))).to be false
  end

  it 'checks supporting/sanction-lists.yml as the list registry' do
    expect(Ammitto::Data::China::SchemaResolver.resolve('sources/supporting/sanction-lists.yml'))
      .to eq(:sanction_lists)
    expect(Ammitto::Data::China::SchemaResolver.resolve('sources/legal-instruments/sanction-lists.yml'))
      .to eq(:legal_instrument)
    expect(valid?('supporting/sanction-lists.yml', registry('cn/anti-sanction-list'))).to be true
    expect(valid?('supporting/sanction-lists.yml', registry('cn/import-export-control-list'))).to be true
    expect(valid?('supporting/sanction-lists.yml', registry('cn/no-such-list'))).to be false
  end
end
