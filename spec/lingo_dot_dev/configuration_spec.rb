# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LingoDotDev::Configuration do
  describe 'initialization' do
    it 'creates a configuration with valid api_key' do
      config = described_class.new(api_key: 'test-key')
      expect(config.api_key).to eq('test-key')
    end

    it 'uses default api_url' do
      config = described_class.new(api_key: 'test-key')
      expect(config.api_url).to eq('https://engine.lingo.dev')
    end

    it 'uses default batch_size' do
      config = described_class.new(api_key: 'test-key')
      expect(config.batch_size).to eq(25)
    end

    it 'uses default ideal_batch_item_size' do
      config = described_class.new(api_key: 'test-key')
      expect(config.ideal_batch_item_size).to eq(250)
    end

    it 'allows customizing api_url' do
      config = described_class.new(
        api_key: 'test-key',
        api_url: 'https://custom.example.com'
      )
      expect(config.api_url).to eq('https://custom.example.com')
    end

    it 'allows customizing batch_size' do
      config = described_class.new(
        api_key: 'test-key',
        batch_size: 50
      )
      expect(config.batch_size).to eq(50)
    end

    it 'allows customizing ideal_batch_item_size' do
      config = described_class.new(
        api_key: 'test-key',
        ideal_batch_item_size: 500
      )
      expect(config.ideal_batch_item_size).to eq(500)
    end
  end

  describe 'validation' do
    it 'raises ValidationError when api_key is nil' do
      expect {
        described_class.new(api_key: nil)
      }.to raise_error(LingoDotDev::ValidationError, /API key is required/)
    end

    it 'raises ValidationError when api_key is empty' do
      expect {
        described_class.new(api_key: '')
      }.to raise_error(LingoDotDev::ValidationError, /API key is required/)
    end

    it 'raises ValidationError when api_url does not start with http/https' do
      expect {
        described_class.new(
          api_key: 'test-key',
          api_url: 'ftp://example.com'
        )
      }.to raise_error(LingoDotDev::ValidationError, /valid HTTP\/HTTPS URL/)
    end

    it 'raises ValidationError when batch_size is less than 1' do
      expect {
        described_class.new(
          api_key: 'test-key',
          batch_size: 0
        )
      }.to raise_error(LingoDotDev::ValidationError, /between 1 and 250/)
    end

    it 'raises ValidationError when batch_size is greater than 250' do
      expect {
        described_class.new(
          api_key: 'test-key',
          batch_size: 251
        )
      }.to raise_error(LingoDotDev::ValidationError, /between 1 and 250/)
    end

    it 'raises ValidationError when ideal_batch_item_size is less than 1' do
      expect {
        described_class.new(
          api_key: 'test-key',
          ideal_batch_item_size: 0
        )
      }.to raise_error(LingoDotDev::ValidationError, /between 1 and 2500/)
    end

    it 'raises ValidationError when ideal_batch_item_size is greater than 2500' do
      expect {
        described_class.new(
          api_key: 'test-key',
          ideal_batch_item_size: 2501
        )
      }.to raise_error(LingoDotDev::ValidationError, /between 1 and 2500/)
    end

    it 'accepts valid batch_size and ideal_batch_item_size values' do
      config = described_class.new(
        api_key: 'test-key',
        batch_size: 100,
        ideal_batch_item_size: 1000
      )
      expect(config.batch_size).to eq(100)
      expect(config.ideal_batch_item_size).to eq(1000)
    end
  end

  describe 'attribute accessors' do
    it 'allows setting api_key after initialization' do
      config = described_class.new(api_key: 'initial-key')
      config.api_key = 'new-key'
      expect(config.api_key).to eq('new-key')
    end

    it 'allows setting api_url after initialization' do
      config = described_class.new(api_key: 'test-key')
      config.api_url = 'https://new-url.com'
      expect(config.api_url).to eq('https://new-url.com')
    end

    it 'allows setting batch_size after initialization' do
      config = described_class.new(api_key: 'test-key')
      config.batch_size = 100
      expect(config.batch_size).to eq(100)
    end

    it 'allows setting ideal_batch_item_size after initialization' do
      config = described_class.new(api_key: 'test-key')
      config.ideal_batch_item_size = 1500
      expect(config.ideal_batch_item_size).to eq(1500)
    end
  end
end
