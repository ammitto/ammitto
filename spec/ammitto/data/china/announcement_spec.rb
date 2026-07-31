# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/data/china'

RSpec.describe Ammitto::Data::China::Announcement do
  describe '.new' do
    it 'creates an announcement' do
      announcement = build_announcement

      expect(announcement.title).to eq('测试公告')
      expect(announcement.authority).to eq('中华人民共和国商务部')
    end
  end

  describe '#published_at' do
    it 'combines date and time' do
      announcement = build_announcement(
        publish_date: Date.new(2024, 1, 15),
        publish_time: '16:00'
      )

      expect(announcement.published_at).to eq(
        DateTime.new(2024, 1, 15, 16, 0)
      )
    end

    it 'returns nil without date' do
      announcement = build_announcement(publish_date: nil)
      expect(announcement.published_at).to be_nil
    end
  end

  def build_announcement(attrs = {})
    Ammitto::Data::China::Announcement.new({
      id: 'cn/test-001',
      title: '测试公告',
      authority: '中华人民共和国商务部',
      publish_date: Date.new(2024, 1, 15)
    }.merge(attrs))
  end
end
