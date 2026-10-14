# frozen_string_literal: true

require 'ammitto'
require 'ammitto/sources/tr'

RSpec.describe Ammitto::Sources::Tr::Transformer do
  subject(:transformer) { described_class.new }

  def listing_date(value)
    source = Ammitto::Sources::Tr::SanctionedEntity.new(
      name: 'Example organization', entity_type: 'organization',
      reference_number: 'test-listing-date', listed_date: value
    )
    transformer.transform(source)[:entry].period.listed_date
  end

  {
    '2 Haziran 2017 (26 Temmuz 2022 tarihinde gözden geçirilmiştir.)' => '2017-06-02',
    "2 Haziran 2017 (değişiklik 26 Temmuz\n2022)\n" => '2017-06-02',
    "5 Ağustos 2017 (değişiklik 26 Temmuz\n2022)\n" => '2017-08-05',
    '30 Mart 2018 (değişiklik 26 Temmuz 2022)' => '2018-03-30',
    '2 Mart 2016 (1 Haziran 2017 ve 26 Temmuz 2022 tarihlerinde gözden geçirilmiştir.)' => '2016-03-02',
    '5 AĞUSTOS 2017' => '2017-08-05',
    '12 Ekim 2020' => '2020-10-12',
    '2021-02-24' => '2021-02-24'
  }.each do |stated, expected|
    it "preserves the initial listing date in #{stated.inspect}" do
      expect(listing_date(stated).to_s).to eq(expected)
    end
  end

  ['645120196', '31 Haziran 2017',
   '2 Haziran 2017 (date could mean something else)'].each do |stated|
    it "leaves an unreadable authority value visible without inventing a date: #{stated.inspect}" do
      allow(Ammitto::ParseFailureVisibility).to receive(:report)
      expect(listing_date(stated)).to be_nil
      expect(Ammitto::ParseFailureVisibility).to have_received(:report)
        .with(hash_including(source: :tr, field: :listed_date, value: stated))
    end
  end

  it 'keeps a missing listing date absent' do
    allow(Ammitto::ParseFailureVisibility).to receive(:report)
    expect(listing_date(nil)).to be_nil
    expect(Ammitto::ParseFailureVisibility).not_to have_received(:report)
  end
end
