# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LingoDotDev::Engine do
  let(:api_key) { ENV['LINGODOTDEV_API_KEY'] }
  let(:api_url) { 'https://engine.lingo.dev' }
  let(:target_locale) { 'es' }
  let(:source_locale) { 'en' }

  describe 'initialization' do
    it 'creates an engine with valid api_key' do
      engine = described_class.new(api_key: api_key)
      expect(engine.config.api_key).to eq(api_key)
    end

    it 'creates engine with custom configuration' do
      engine = described_class.new(
        api_key: api_key,
        api_url: 'https://custom.example.com',
        batch_size: 50,
        ideal_batch_item_size: 500
      )
      expect(engine.config.api_url).to eq('https://custom.example.com')
      expect(engine.config.batch_size).to eq(50)
      expect(engine.config.ideal_batch_item_size).to eq(500)
    end

    it 'allows block-based configuration' do
      engine = described_class.new(api_key: api_key) do |config|
        config.batch_size = 75
      end
      expect(engine.config.batch_size).to eq(75)
    end
  end

  describe '#localize_text' do
    it 'localizes text to target locale' do
      engine = described_class.new(api_key: api_key)
      result = engine.localize_text(
        'Hello world',
        target_locale: target_locale
      )
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it 'localizes text with source locale specified' do
      engine = described_class.new(api_key: api_key)
      result = engine.localize_text(
        'Hello world',
        target_locale: target_locale,
        source_locale: source_locale
      )
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it 'localizes text with fast flag' do
      engine = described_class.new(api_key: api_key)
      result = engine.localize_text(
        'Hello world',
        target_locale: target_locale,
        fast: true
      )
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it 'localizes text with reference context' do
      engine = described_class.new(api_key: api_key)
      reference = { context: 'greeting' }
      result = engine.localize_text(
        'Hello',
        target_locale: target_locale,
        reference: reference
      )
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it 'supports progress callback block' do
      engine = described_class.new(api_key: api_key)
      progress_updates = []
      result = engine.localize_text(
        'Hello world',
        target_locale: target_locale
      ) { |progress| progress_updates << progress }
      expect(result).to be_a(String)
      expect(progress_updates).not_to be_empty if result.length > 0
    end

    it 'supports on_progress callback parameter' do
      engine = described_class.new(api_key: api_key)
      progress_updates = []
      result = engine.localize_text(
        'Hello world',
        target_locale: target_locale,
        on_progress: proc { |progress| progress_updates << progress }
      )
      expect(result).to be_a(String)
    end

    it 'raises ValidationError when target_locale is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_text('Hello', target_locale: nil)
      }.to raise_error(LingoDotDev::ValidationError, /Target locale is required/)
    end

    it 'raises ValidationError when target_locale is empty' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_text('Hello', target_locale: '')
      }.to raise_error(LingoDotDev::ValidationError, /Target locale is required/)
    end

    it 'raises ValidationError when text is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_text(nil, target_locale: target_locale)
      }.to raise_error(LingoDotDev::ValidationError, /Text cannot be nil/)
    end
  end

  describe '#localize_object' do
    it 'localizes a hash object to target locale' do
      engine = described_class.new(api_key: api_key)
      obj = { greeting: 'Hello', farewell: 'Goodbye' }
      result = engine.localize_object(
        obj,
        target_locale: target_locale
      )
      expect(result).to be_a(Hash)
      expect(result.keys).to include('greeting', 'farewell')
    end

    it 'localizes object with source locale' do
      engine = described_class.new(api_key: api_key)
      obj = { message: 'Hello world' }
      result = engine.localize_object(
        obj,
        target_locale: target_locale,
        source_locale: source_locale
      )
      expect(result).to be_a(Hash)
    end

    it 'localizes object with fast flag' do
      engine = described_class.new(api_key: api_key)
      obj = { greeting: 'Hi' }
      result = engine.localize_object(
        obj,
        target_locale: target_locale,
        fast: true
      )
      expect(result).to be_a(Hash)
    end

    it 'supports progress callback for objects' do
      engine = described_class.new(api_key: api_key)
      obj = { text: 'Hello' }
      progress_updates = []
      result = engine.localize_object(
        obj,
        target_locale: target_locale
      ) { |progress| progress_updates << progress }
      expect(result).to be_a(Hash)
    end

    it 'raises ValidationError when target_locale is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_object({ text: 'Hello' }, target_locale: nil)
      }.to raise_error(LingoDotDev::ValidationError, /Target locale is required/)
    end

    it 'raises ValidationError when object is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_object(nil, target_locale: target_locale)
      }.to raise_error(LingoDotDev::ValidationError, /Object cannot be nil/)
    end

    it 'raises ValidationError when object is not a Hash' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_object('not a hash', target_locale: target_locale)
      }.to raise_error(LingoDotDev::ValidationError, /Object must be a Hash/)
    end
  end

  describe '#localize_chat' do
    it 'localizes chat messages to target locale' do
      engine = described_class.new(api_key: api_key)
      chat = [
        { name: 'user', text: 'Hello!' },
        { name: 'assistant', text: 'Hi there!' }
      ]
      result = engine.localize_chat(
        chat,
        target_locale: target_locale
      )
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
    end

    it 'localizes chat with source locale' do
      engine = described_class.new(api_key: api_key)
      chat = [{ name: 'user', text: 'Hello' }]
      result = engine.localize_chat(
        chat,
        target_locale: target_locale,
        source_locale: source_locale
      )
      expect(result).to be_an(Array)
    end

    it 'localizes chat with fast flag' do
      engine = described_class.new(api_key: api_key)
      chat = [{ name: 'user', text: 'Hi' }]
      result = engine.localize_chat(
        chat,
        target_locale: target_locale,
        fast: true
      )
      expect(result).to be_an(Array)
    end

    it 'supports progress callback for chat' do
      engine = described_class.new(api_key: api_key)
      chat = [{ name: 'user', text: 'Hello' }]
      progress_updates = []
      result = engine.localize_chat(
        chat,
        target_locale: target_locale
      ) { |progress| progress_updates << progress }
      expect(result).to be_an(Array)
    end

    it 'raises ValidationError when target_locale is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_chat([], target_locale: nil)
      }.to raise_error(LingoDotDev::ValidationError, /Target locale is required/)
    end

    it 'raises ValidationError when chat is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_chat(nil, target_locale: target_locale)
      }.to raise_error(LingoDotDev::ValidationError, /Chat cannot be nil/)
    end

    it 'raises ValidationError when chat is not an Array' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_chat({}, target_locale: target_locale)
      }.to raise_error(LingoDotDev::ValidationError, /Chat must be an Array/)
    end

    it 'raises ValidationError when chat messages lack name' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_chat(
          [{ text: 'Hello' }],
          target_locale: target_locale
        )
      }.to raise_error(LingoDotDev::ValidationError, /:name and :text keys/)
    end

    it 'raises ValidationError when chat messages lack text' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_chat(
          [{ name: 'user' }],
          target_locale: target_locale
        )
      }.to raise_error(LingoDotDev::ValidationError, /:name and :text keys/)
    end
  end

  describe '#localize_html' do
    it 'correctly extracts, localizes, and reconstructs HTML content' do
      input_html = <<~HTML.strip
        <!DOCTYPE html>
        <html>
          <head>
            <title>Test Page</title>
            <meta name="description" content="Page description">
          </head>
          <body>
            standalone text
            <div>
              <h1>Hello World</h1>
              <p>
                This is a paragraph with
                <a href="/test" title="Link title">a link</a>
                and an
                <img src="/test.jpg" alt="Test image">
                and some <b>bold <i>and italic</i></b> text.
              </p>
              <script>
                const doNotTranslate = "this text should be ignored";
              </script>
              <input type="text" placeholder="Enter text">
            </div>
          </body>
        </html>
      HTML

      engine = described_class.new(api_key: api_key)
      extracted_content = nil
      call_params = nil

      allow(engine).to receive(:localize_raw) do |content, params, &block|
        extracted_content = content
        call_params = params
        localized = {}
        content.each do |key, value|
          localized[key] = "ES:#{value}"
        end
        localized
      end

      result = engine.localize_html(input_html, target_locale: 'es', source_locale: 'en')

      expect(call_params[:target_locale]).to eq('es')
      expect(call_params[:source_locale]).to eq('en')
      expect(extracted_content).to include(
        'head/0/0' => 'Test Page',
        'head/1#content' => 'Page description',
        'body/0' => 'standalone text',
        'body/1/0/0' => 'Hello World',
        'body/1/1/0' => 'This is a paragraph with',
        'body/1/1/1#title' => 'Link title',
        'body/1/1/1/0' => 'a link',
        'body/1/1/2' => 'and an',
        'body/1/1/3#alt' => 'Test image',
        'body/1/1/4' => 'and some',
        'body/1/1/5/0' => 'bold',
        'body/1/1/5/1/0' => 'and italic',
        'body/1/1/6' => 'text.',
        'body/1/3#placeholder' => 'Enter text'
      )

      expect(result).to include('lang="es"')
      expect(result).to include('<title>ES:Test Page</title>')
      expect(result).to include('content="ES:Page description"')
      expect(result).to include('>ES:standalone text<')
      expect(result).to include('<h1>ES:Hello World</h1>')
      expect(result).to include('title="ES:Link title"')
      expect(result).to include('alt="ES:Test image"')
      expect(result).to include('placeholder="ES:Enter text"')
      expect(result).to include('const doNotTranslate = "this text should be ignored"')
    end

    it 'localizes HTML with source locale' do
      html = '<html><head><title>Hello</title></head><body><p>World</p></body></html>'
      engine = described_class.new(api_key: api_key)
      call_params = nil
      allow(engine).to receive(:localize_raw) do |content, params, &block|
        call_params = params
        { 'head/0/0' => 'Hola', 'body/0/0' => 'Mundo' }
      end

      result = engine.localize_html(html, target_locale: 'es', source_locale: 'en')

      expect(call_params[:source_locale]).to eq('en')
      expect(call_params[:target_locale]).to eq('es')
      expect(result).to include('lang="es"')
    end

    it 'localizes HTML with fast flag' do
      html = '<html><head><title>Hello</title></head><body><p>World</p></body></html>'
      engine = described_class.new(api_key: api_key)
      call_params = nil
      allow(engine).to receive(:localize_raw) do |content, params, &block|
        call_params = params
        { 'head/0/0' => 'Hola', 'body/0/0' => 'Mundo' }
      end

      result = engine.localize_html(html, target_locale: 'es', fast: true)

      expect(call_params[:fast]).to eq(true)
    end

    it 'supports progress callback for HTML' do
      html = '<html><head><title>Hello</title></head><body><p>World</p></body></html>'
      engine = described_class.new(api_key: api_key)
      progress_updates = []
      allow(engine).to receive(:localize_raw) do |content, params, &block|
        block&.call(100, {}, {})
        { 'head/0/0' => 'Hola', 'body/0/0' => 'Mundo' }
      end

      result = engine.localize_html(html, target_locale: 'es') { |progress| progress_updates << progress }

      expect(progress_updates).not_to be_empty
    end

    it 'raises ValidationError when target_locale is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_html('<html></html>', target_locale: nil)
      }.to raise_error(LingoDotDev::ValidationError, /Target locale is required/)
    end

    it 'raises ValidationError when target_locale is empty' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_html('<html></html>', target_locale: '')
      }.to raise_error(LingoDotDev::ValidationError, /Target locale is required/)
    end

    it 'raises ValidationError when html is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.localize_html(nil, target_locale: 'es')
      }.to raise_error(LingoDotDev::ValidationError, /HTML cannot be nil/)
    end
  end

  describe '#batch_localize_text' do
    it 'batch localizes text to multiple locales' do
      engine = described_class.new(api_key: api_key)
      results = engine.batch_localize_text(
        'Hello world',
        target_locales: ['es', 'fr']
      )
      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
      expect(results.all? { |r| r.is_a?(String) }).to be true
    end

    it 'batch localizes with source locale' do
      engine = described_class.new(api_key: api_key)
      results = engine.batch_localize_text(
        'Hello',
        target_locales: ['es', 'de'],
        source_locale: source_locale
      )
      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
    end

    it 'batch localizes with fast flag' do
      engine = described_class.new(api_key: api_key)
      results = engine.batch_localize_text(
        'Hi',
        target_locales: ['es', 'fr'],
        fast: true
      )
      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
    end

    it 'batch localizes concurrently' do
      engine = described_class.new(api_key: api_key)
      results = engine.batch_localize_text(
        'Hello world',
        target_locales: ['es', 'fr', 'de'],
        concurrent: true
      )
      expect(results).to be_an(Array)
      expect(results.length).to eq(3)
    end

    it 'raises ValidationError when text is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.batch_localize_text(nil, target_locales: ['es'])
      }.to raise_error(LingoDotDev::ValidationError, /Text cannot be nil/)
    end

    it 'raises ValidationError when target_locales is not an Array' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.batch_localize_text('Hello', target_locales: 'es')
      }.to raise_error(LingoDotDev::ValidationError, /Target locales must be an Array/)
    end

    it 'raises ValidationError when target_locales is empty' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.batch_localize_text('Hello', target_locales: [])
      }.to raise_error(LingoDotDev::ValidationError, /Target locales cannot be empty/)
    end
  end

  describe '#batch_localize_objects' do
    it 'batch localizes multiple objects to same locale' do
      engine = described_class.new(api_key: api_key)
      objects = [
        { greeting: 'Hello' },
        { farewell: 'Goodbye' }
      ]
      results = engine.batch_localize_objects(
        objects,
        target_locale: target_locale
      )
      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
      expect(results.all? { |r| r.is_a?(Hash) }).to be true
    end

    it 'batch localizes objects with source locale' do
      engine = described_class.new(api_key: api_key)
      objects = [{ text: 'Hello' }]
      results = engine.batch_localize_objects(
        objects,
        target_locale: target_locale,
        source_locale: source_locale
      )
      expect(results).to be_an(Array)
    end

    it 'batch localizes objects with fast flag' do
      engine = described_class.new(api_key: api_key)
      objects = [{ text: 'Hi' }]
      results = engine.batch_localize_objects(
        objects,
        target_locale: target_locale,
        fast: true
      )
      expect(results).to be_an(Array)
    end

    it 'batch localizes objects concurrently' do
      engine = described_class.new(api_key: api_key)
      objects = [
        { text: 'Hello' },
        { text: 'Hi' },
        { text: 'Hey' }
      ]
      results = engine.batch_localize_objects(
        objects,
        target_locale: target_locale,
        concurrent: true
      )
      expect(results).to be_an(Array)
      expect(results.length).to eq(3)
    end

    it 'raises ValidationError when objects is not an Array' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.batch_localize_objects(
          { text: 'Hello' },
          target_locale: target_locale
        )
      }.to raise_error(LingoDotDev::ValidationError, /Objects must be an Array/)
    end

    it 'raises ValidationError when objects is empty' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.batch_localize_objects([], target_locale: target_locale)
      }.to raise_error(LingoDotDev::ValidationError, /Objects cannot be empty/)
    end

    it 'raises ValidationError when target_locale is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.batch_localize_objects(
          [{ text: 'Hello' }],
          target_locale: nil
        )
      }.to raise_error(LingoDotDev::ValidationError, /Target locale is required/)
    end

    it 'raises ValidationError when object is not a Hash' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.batch_localize_objects(
          ['not a hash'],
          target_locale: target_locale
        )
      }.to raise_error(LingoDotDev::ValidationError, /Each object must be a Hash/)
    end
  end

  describe '#recognize_locale' do
    it 'recognizes locale of given text' do
      engine = described_class.new(api_key: api_key)
      locale = engine.recognize_locale('Hello world')
      expect(locale).to be_a(String)
      expect(locale.length).to be > 0
    end

    it 'raises ValidationError when text is nil' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.recognize_locale(nil)
      }.to raise_error(LingoDotDev::ValidationError, /Text cannot be empty/)
    end

    it 'raises ValidationError when text is empty' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.recognize_locale('')
      }.to raise_error(LingoDotDev::ValidationError, /Text cannot be empty/)
    end

    it 'raises ValidationError when text is only whitespace' do
      engine = described_class.new(api_key: api_key)
      expect {
        engine.recognize_locale('   ')
      }.to raise_error(LingoDotDev::ValidationError, /Text cannot be empty/)
    end
  end

  describe '#whoami' do
    it 'returns user information' do
      engine = described_class.new(api_key: api_key)
      result = engine.whoami
      if result
        expect(result).to be_a(Hash)
        expect(result).to include(:email, :id)
      end
    end
  end

  describe '.quick_translate' do
    it 'quickly translates a string' do
      result = described_class.quick_translate(
        'Hello world',
        api_key: api_key,
        target_locale: target_locale
      )
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it 'quickly translates a hash with concurrent processing' do
      result = described_class.quick_translate(
        { greeting: 'Hello', farewell: 'Goodbye' },
        api_key: api_key,
        target_locale: target_locale
      )
      expect(result).to be_a(Hash)
    end

    it 'raises ValidationError for invalid content type' do
      expect {
        described_class.quick_translate(
          123,
          api_key: api_key,
          target_locale: target_locale
        )
      }.to raise_error(LingoDotDev::ValidationError, /Content must be a String or Hash/)
    end
  end

  describe '.quick_batch_translate' do
    it 'quickly batch translates a string to multiple locales' do
      results = described_class.quick_batch_translate(
        'Hello',
        api_key: api_key,
        target_locales: ['es', 'fr']
      )
      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
      expect(results.all? { |r| r.is_a?(String) }).to be true
    end

    it 'quickly batch translates a hash to multiple locales' do
      results = described_class.quick_batch_translate(
        { greeting: 'Hello' },
        api_key: api_key,
        target_locales: ['es', 'fr']
      )
      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
      expect(results.all? { |r| r.is_a?(Hash) }).to be true
    end

    it 'raises ValidationError for invalid content type' do
      expect {
        described_class.quick_batch_translate(
          123,
          api_key: api_key,
          target_locales: ['es']
        )
      }.to raise_error(LingoDotDev::ValidationError, /Content must be a String or Hash/)
    end
  end
end
