# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Validation::Result do
  describe '#valid?' do
    it 'is true when there are no errors' do
      expect(described_class.new.valid?).to be true
    end

    it 'is false when errors are present' do
      result = described_class.new(errors: ['broken'])
      expect(result.valid?).to be false
    end

    it 'is not affected by warnings' do
      result = described_class.new(warnings: ['minor issue'])
      expect(result.valid?).to be true
    end
  end

  describe '#errors' do
    it 'represents plain string errors' do
      result = described_class.new(errors: ['Missing required field: id'])
      expect(result.errors).to eq(['Missing required field: id'])
    end

    it 'represents { path:, message: } hash errors' do
      error = { path: 'a.yml', message: 'File not found' }
      result = described_class.new(errors: [error])
      expect(result.errors).to eq([error])
    end
  end

  describe '#details' do
    it 'defaults to an empty hash' do
      expect(described_class.new.details).to eq({})
    end

    it 'carries validator-specific extras such as file counts' do
      result = described_class.new(
        details: { total_files: 3, valid_files: 2, invalid_files: 1 }
      )
      expect(result.details[:total_files]).to eq(3)
      expect(result.details[:invalid_files]).to eq(1)
    end
  end

  describe '#error_messages' do
    it 'extracts messages from string and hash errors alike' do
      result = described_class.new(
        errors: ['plain error', { path: 'a.yml', message: 'hash error' }]
      )
      expect(result.error_messages).to eq(['plain error', 'hash error'])
    end
  end

  describe '.success' do
    it 'builds a passing result' do
      result = described_class.success(details: { source: :test })
      expect(result.valid?).to be true
      expect(result.details).to eq(source: :test)
    end
  end

  describe '.failure' do
    it 'builds a failing result from a list of errors' do
      result = described_class.failure(%w[one two])
      expect(result.valid?).to be false
      expect(result.errors).to eq(%w[one two])
    end

    it 'wraps a single error into an array' do
      result = described_class.failure({ message: 'boom' })
      expect(result.errors).to eq([{ message: 'boom' }])
    end
  end

  describe '#merge' do
    it 'concatenates errors and warnings' do
      merged = described_class.new(errors: ['a'], warnings: ['w1'])
                              .merge(described_class.new(errors: ['b'],
                                                         warnings: ['w2']))
      expect(merged.errors).to eq(%w[a b])
      expect(merged.warnings).to eq(%w[w1 w2])
    end

    it 'shallow-merges details with the other result winning' do
      merged = described_class.new(details: { a: 1, b: 1 })
                              .merge(described_class.new(details: { b: 2 }))
      expect(merged.details).to eq(a: 1, b: 2)
    end

    it 'returns a new result without mutating the originals' do
      original = described_class.new(errors: ['a'])
      merged = original.merge(described_class.new(errors: ['b']))
      expect(original.errors).to eq(['a'])
      expect(merged).not_to be(original)
    end
  end

  describe 'deep immutability' do
    it 'is not affected by later mutation of the input structures' do
      error = { path: 'a.yml', message: 'original' }
      details = { file_errors: [{ file: 'a.yml', errors: [error] }] }
      result = described_class.new(errors: [error], details: details)

      error[:message] = 'mutated'
      details[:file_errors] << { file: 'b.yml', errors: [] }

      expect(result.errors.first[:message]).to eq('original')
      expect(result.details[:file_errors].length).to eq(1)
    end

    it 'freezes nested structures against mutation through readers' do
      result = described_class.new(
        errors: [{ path: 'a.yml', message: 'boom' }],
        details: { file_errors: [] }
      )

      expect { result.errors.first[:message] = 'changed' }
        .to raise_error(FrozenError)
      expect { result.details[:file_errors] << :extra }
        .to raise_error(FrozenError)
    end
  end

  describe '.combine' do
    it 'folds many results into one' do
      combined = described_class.combine(
        [
          described_class.new(errors: ['a'], details: { total: 1 }),
          described_class.new(warnings: ['w']),
          described_class.new(errors: ['b'])
        ]
      )
      expect(combined.valid?).to be false
      expect(combined.errors).to eq(%w[a b])
      expect(combined.warnings).to eq(['w'])
      expect(combined.details).to eq(total: 1)
    end

    it 'returns a valid result for an empty list' do
      expect(described_class.combine([]).valid?).to be true
    end
  end
end
