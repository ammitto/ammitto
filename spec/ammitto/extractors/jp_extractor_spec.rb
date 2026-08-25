# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/extractors/jp_extractor'

RSpec.describe Ammitto::Extractors::JpExtractor do
  # This class has never read its source. It used to say so in a way that
  # was itself wrong: #fetch returned format 'pdf' and
  # requires_manual_conversion, and #api_endpoint named a .pdf that METI
  # does not publish — the End-User List is a spreadsheet, and data-jp
  # downloads and converts it automatically. A caller who believed either
  # would go looking for a document that does not exist.
  #
  # FetchCommand::NO_FETCH_PATH stops `ammitto fetch jp` before any of
  # this is reached, so these examples exist to hold the programmatic
  # surface, which that guard does not cover.
  subject(:extractor) { described_class.new }

  describe '#fetch' do
    it 'refuses instead of describing a source it cannot read' do
      expect { extractor.fetch }.to raise_error(NotImplementedError)
    end

    it 'names the class that can actually read the source' do
      expect { extractor.fetch }
        .to raise_error(/Ammitto::Data::Japan::Meti::Extractor/)
    end

    it 'says that replacement is programmatic, because the source CLI ' \
       'cannot reach it' do
      expect { extractor.fetch }.to raise_error(/programmatic/)
    end
  end

  describe '#api_endpoint' do
    it 'refuses rather than naming a URL that does not serve the list' do
      expect { extractor.api_endpoint }.to raise_error(NotImplementedError)
    end
  end

  describe 'the identity it still answers for' do
    it 'reports its source code' do
      expect(extractor.code).to eq(:jp)
    end

    it 'names the publishing authority' do
      expect(extractor.authority_name).to include('METI')
    end
  end
end
