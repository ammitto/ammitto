# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/ru'
require 'ammitto/serialization/json_ld_serializer'

RSpec.describe Ammitto::Sources::Ru::AnnouncementTransformer do
  include RuAnnouncementFixtures

  subject(:transformer) { described_class.new }

  let(:official_url) { 'https://www.mid.ru/ru/detail-material-page/1817739/' }

  def snapshot(url:, document_id: nil)
    data = YAML.safe_load(ru_announcement_yaml)
    data['announcement']['document_id'] = document_id
    data['announcement']['url'] = url
    Ammitto::Sources::Ru::Announcement.from_hash(data)
  end

  def identifiers(result)
    [result[:official_announcement].id, result[:group].id,
     *result[:entities].map(&:id), *result[:entries].map(&:id)]
  end

  it 'uses the official page for identity without inventing a document number' do
    result = transformer.transform_announcement(snapshot(url: official_url))
    official = result[:official_announcement]
    serializer = Ammitto::Serialization::JsonLdSerializer.new
    serialized = serializer.serialize_entry(result[:entries].first)

    expect(official.id).to match(%r{/announcement/ru/url-[0-9a-f]{19}\z})
    expect(official.document_id).to be_nil
    expect(official.url).to eq(official_url)
    expect(serialized['announcement']).not_to have_key('documentId')
    expect(serialized).not_to have_key('referenceNumber')
    expect(result[:entries].map { |entry| entry.announcement.id }.uniq)
      .to eq([official.id])
    expect(result[:group].announcement_id).to eq(official.id)
    expect(result[:entries].map(&:group_id).uniq).to eq([result[:group].id])
  end

  it 'keeps the same identifiers across canonical host and trailing-slash variants' do
    original = transformer.transform_announcement(snapshot(url: official_url))
    canonical = transformer.transform_announcement(
      snapshot(url: 'https://mid.ru/ru/detail-material-page/1817739')
    )

    expect(identifiers(canonical)).to eq(identifiers(original))
  end

  it 'keeps different official pages separate even when their parties match' do
    first = transformer.transform_announcement(snapshot(url: official_url))
    second = transformer.transform_announcement(
      snapshot(url: official_url.sub('1817739', '1817740'))
    )

    expect(identifiers(first) & identifiers(second)).to be_empty
  end

  it 'preserves identifiers when source parties are reordered' do
    original = snapshot(url: official_url)
    reordered = snapshot(url: official_url)
    reordered.sanction_details.entities = reordered.entities.reverse
    first = transformer.transform_announcement(original)
    second = transformer.transform_announcement(reordered)

    expect(identifiers(second).sort).to eq(identifiers(first).sort)
  end

  it 'leaves official document identifiers and their existing IRIs unchanged' do
    result = transformer.transform_announcement(
      snapshot(url: official_url, document_id: '806-13-04-2022')
    )

    original = transformer.transform_announcement(ru_announcement)

    expect(identifiers(result)).to eq(identifiers(original))
    expect(result[:entries].map(&:reference_number)).to eq(original[:entries].map(&:reference_number))
    expect(result[:official_announcement].document_id).to eq('806-13-04-2022')
  end

  [nil, '', ' '].each do |absent|
    it "keeps document metadata absent for #{absent.inspect}" do
      result = transformer.transform_announcement(
        snapshot(url: official_url, document_id: absent)
      )

      expect(result[:official_announcement].document_id).to be_nil
    end
  end

  ['!!!', 'unknown', '制裁'].each do |invalid|
    it "rejects a corrupt document identifier #{invalid.inspect} despite an official URL" do
      expect do
        transformer.transform_announcement(snapshot(url: official_url, document_id: invalid))
      end.to raise_error(Ammitto::ParseError, /no usable document_id/)
    end
  end

  [
    nil, '', ' ',
    'http://mid.ru/ru/detail-material-page/1817739/',
    'https://example.com/ru/detail-material-page/1817739/',
    'https://mid.ru.example.com/ru/detail-material-page/1817739/',
    'https://mid.ru@evil.example/ru/detail-material-page/1817739/',
    'https://user@mid.ru/ru/detail-material-page/1817739/',
    'https://mid.ru:8443/ru/detail-material-page/1817739/',
    'https://mid.ru/ru/detail-material-page/1817739/?id=another',
    'https://mid.ru/ru/detail-material-page/1817739/#another',
    'https://mid.ru/',
    'https://mid.ru/ru/detail-material-page/../1817739/',
    'https://mid.ru/ru/detail-material-page/not-a-page/'
  ].each do |untrusted|
    it "rejects an absent document number with URL #{untrusted.inspect}" do
      expect do
        transformer.transform_announcement(snapshot(url: untrusted))
      end.to raise_error(Ammitto::ParseError, /no usable document_id/)
    end
  end
end
