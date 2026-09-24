# frozen_string_literal: true

require 'spec_helper'

# `StatusChange` declares `attribute :notice_reference, NoticeReference`, and
# that constant is resolved when the file is read, so the
# `require_relative 'notice_reference'` at the top of `status_change.rb` is the
# only thing that lets the file load by itself. Every other path reaches
# `NoticeReference` through `ammitto.rb` or the `models.rb` autoload, so
# nothing else fails if that line is ever removed as redundant.
#
# Each example loads one file in a fresh process, because RSpec has already
# required the whole tree by the time an example runs.
RSpec.describe 'Ammitto::StatusChange and Ammitto::NoticeReference files' do
  include IsolatedLoadHelper

  %w[ammitto/status_change ammitto/notice_reference].each do |path|
    it "loads #{path} on its own" do
      ok, err = load_in_subprocess(path)
      expect(ok).to be(true), "loading #{path} alone failed:\n#{err}"
    end
  end
end
