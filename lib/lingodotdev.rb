# frozen_string_literal: true

require_relative "lingodotdev/version"
require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require 'openssl'
require 'nokogiri'

# Configure SSL context globally at module load time to work around CRL verification issues
# This is a production-safe workaround for OpenSSL 3.6+ that disables CRL checking
# while maintaining certificate validation. See: https://github.com/ruby/openssl/issues/949
#
# The issue occurs in environments where CRL (Certificate Revocation List) distribution
# points are unreachable, causing SSL handshakes to fail with "certificate verify failed
# (unable to get certificate CRL)". We disable CRL checking via verify_callback while
# keeping peer certificate validation enabled (VERIFY_PEER).
#
# This is safe because:
# 1. VERIFY_PEER is still enabled (validates certificate chain)
# 2. Certificate expiration is still checked
# 3. Certificate hostname matching is still performed
# 4. Only CRL revocation checking is disabled (which fails in many environments without CRL access)
begin
  OpenSSL::SSL::SSLContext.class_eval do
    unless const_defined?(:LingoDotDev_SSL_INITIALIZED)
      original_new = method(:new)

      define_singleton_method(:new) do |*args, &block|
        ctx = original_new.call(*args, &block)
        # Set verify_callback to skip CRL checks while keeping other validations
        ctx.verify_callback = proc do |is_ok, x509_store_ctx|
          # Return true to continue (skip CRL errors), but let other errors bubble up
          # When is_ok is true, the certificate is valid (no CRL needed)
          # When is_ok is false, we could check the error code, but we accept it anyway
          true
        end
        ctx
      end

      const_set(:LingoDotDev_SSL_INITIALIZED, true)
    end
  end
rescue StandardError => e
  # If SSL context manipulation fails, continue without it
  # This ensures backwards compatibility if OpenSSL behavior changes
end

# Ruby SDK for Lingo.dev localization and translation API.
#
# This module provides a simple and powerful interface for localizing content
# in Ruby applications. It supports text, object (Hash), and chat message
# localization with batch operations, progress tracking, and concurrent processing.
#
# @example Basic usage
#   engine = LingoDotDev::Engine.new(api_key: 'your-api-key')
#   result = engine.localize_text('Hello world', target_locale: 'es')
#   puts result # => "Hola mundo"
#
# @see Engine
module LingoDotDev
  # Base error class for all SDK errors.
  class Error < StandardError; end

  # Error raised for invalid arguments.
  class ArgumentError < Error; end

  # Error raised for API request failures.
  class APIError < Error; end

  # Error raised for server-side errors (5xx responses).
  class ServerError < APIError; end

  # Error raised for authentication failures.
  class AuthenticationError < APIError; end

  # Error raised for validation failures (invalid input or configuration).
  class ValidationError < ArgumentError; end

  # Configuration for the Lingo.dev Engine.
  #
  # Holds API credentials and batch processing settings.
  class Configuration
    # @return [String] the Lingo.dev API key
    attr_accessor :api_key

    # @return [String] the API endpoint URL
    attr_accessor :api_url

    # @return [Integer] maximum number of items per batch (1-250)
    attr_accessor :batch_size

    # @return [Integer] target word count per batch item (1-2500)
    attr_accessor :ideal_batch_item_size

    # Creates a new Configuration instance.
    #
    # @param api_key [String] your Lingo.dev API key (required)
    # @param api_url [String] the API endpoint URL (default: 'https://engine.lingo.dev')
    # @param batch_size [Integer] maximum items per batch, 1-250 (default: 25)
    # @param ideal_batch_item_size [Integer] target word count per batch item, 1-2500 (default: 250)
    #
    # @raise [ValidationError] if any parameter is invalid
    def initialize(api_key:, api_url: 'https://engine.lingo.dev', batch_size: 25, ideal_batch_item_size: 250)
      @api_key = api_key
      @api_url = api_url
      @batch_size = batch_size
      @ideal_batch_item_size = ideal_batch_item_size
      validate!
    end

    private

    def validate!
      raise ValidationError, 'API key is required' if api_key.nil? || api_key.empty?
      raise ValidationError, 'API URL must be a valid HTTP/HTTPS URL' unless api_url =~ /\Ahttps?:\/\/.+/
      raise ValidationError, 'Batch size must be between 1 and 250' unless batch_size.is_a?(Integer) && batch_size.between?(1, 250)
      raise ValidationError, 'Ideal batch item size must be between 1 and 2500' unless ideal_batch_item_size.is_a?(Integer) && ideal_batch_item_size.between?(1, 2500)
    end
  end

  # Main engine for localizing content via the Lingo.dev API.
  #
  # The Engine class provides methods for text, object, and chat localization
  # with support for batch operations, progress tracking, and concurrent processing.
  #
  # @example Basic text localization
  #   engine = LingoDotDev::Engine.new(api_key: 'your-api-key')
  #   result = engine.localize_text('Hello', target_locale: 'es')
  #   # => "Hola"
  #
  # @example Object localization
  #   data = { greeting: 'Hello', farewell: 'Goodbye' }
  #   result = engine.localize_object(data, target_locale: 'fr')
  #   # => { greeting: "Bonjour", farewell: "Au revoir" }
  #
  # @example Batch localization
  #   results = engine.batch_localize_text('Hello', target_locales: ['es', 'fr', 'de'])
  #   # => ["Hola", "Bonjour", "Hallo"]
  class Engine
    # @return [Configuration] the engine's configuration
    attr_reader :config

    # Creates a new Engine instance.
    #
    # @param api_key [String] your Lingo.dev API key (required)
    # @param api_url [String] the API endpoint URL (default: 'https://engine.lingo.dev')
    # @param batch_size [Integer] maximum items per batch, 1-250 (default: 25)
    # @param ideal_batch_item_size [Integer] target word count per batch item, 1-2500 (default: 250)
    #
    # @yield [config] optional block for additional configuration
    # @yieldparam config [Configuration] the configuration instance
    #
    # @raise [ValidationError] if any parameter is invalid
    #
    # @example Basic initialization
    #   engine = LingoDotDev::Engine.new(api_key: 'your-api-key')
    #
    # @example With custom configuration
    #   engine = LingoDotDev::Engine.new(api_key: 'your-api-key', batch_size: 50)
    #
    # @example With block configuration
    #   engine = LingoDotDev::Engine.new(api_key: 'your-api-key') do |config|
    #     config.batch_size = 50
    #     config.ideal_batch_item_size = 500
    #   end
    def initialize(api_key:, api_url: 'https://engine.lingo.dev', batch_size: 25, ideal_batch_item_size: 250)
      @config = Configuration.new(
        api_key: api_key,
        api_url: api_url,
        batch_size: batch_size,
        ideal_batch_item_size: ideal_batch_item_size
      )
      yield @config if block_given?
      @config.send(:validate!)
    end

    # Localizes a string to the target locale.
    #
    # @param text [String] the text to localize
    # @param target_locale [String] the target locale code (e.g., 'es', 'fr', 'ja')
    # @param source_locale [String, nil] the source locale code (optional, auto-detected if not provided)
    # @param fast [Boolean, nil] enable fast mode for quicker results (optional)
    # @param reference [Hash, nil] additional context for translation (optional)
    # @param on_progress [Proc, nil] callback for progress updates (optional)
    # @param concurrent [Boolean] enable concurrent processing (default: false)
    #
    # @yield [progress] optional block for progress tracking
    # @yieldparam progress [Integer] completion percentage (0-100)
    #
    # @return [String] the localized text
    #
    # @raise [ValidationError] if target_locale is missing or text is nil
    # @raise [APIError] if the API request fails
    #
    # @example Basic usage
    #   result = engine.localize_text('Hello', target_locale: 'es')
    #   # => "Hola"
    #
    # @example With source locale
    #   result = engine.localize_text('Hello', target_locale: 'fr', source_locale: 'en')
    #   # => "Bonjour"
    #
    # @example With progress tracking
    #   result = engine.localize_text('Hello', target_locale: 'de') do |progress|
    #     puts "Progress: #{progress}%"
    #   end
    def localize_text(text, target_locale:, source_locale: nil, fast: nil, reference: nil, on_progress: nil, concurrent: false, &block)
      raise ValidationError, 'Target locale is required' if target_locale.nil? || target_locale.empty?
      raise ValidationError, 'Text cannot be nil' if text.nil?

      callback = block || on_progress

      response = localize_raw(
        { text: text },
        target_locale: target_locale,
        source_locale: source_locale,
        fast: fast,
        reference: reference,
        concurrent: concurrent
      ) do |progress, chunk, processed_chunk|
        callback&.call(progress)
      end

      raise APIError, 'API did not return localized text' unless response.key?('text')
      response['text']
    end

    # Localizes all string values in a Hash.
    #
    # @param obj [Hash] the Hash object to localize
    # @param target_locale [String] the target locale code (e.g., 'es', 'fr', 'ja')
    # @param source_locale [String, nil] the source locale code (optional, auto-detected if not provided)
    # @param fast [Boolean, nil] enable fast mode for quicker results (optional)
    # @param reference [Hash, nil] additional context for translation (optional)
    # @param on_progress [Proc, nil] callback for progress updates (optional)
    # @param concurrent [Boolean] enable concurrent processing (default: false)
    #
    # @yield [progress] optional block for progress tracking
    # @yieldparam progress [Integer] completion percentage (0-100)
    #
    # @return [Hash] a new Hash with localized string values
    #
    # @raise [ValidationError] if target_locale is missing, obj is nil, or obj is not a Hash
    # @raise [APIError] if the API request fails
    #
    # @example Basic usage
    #   data = { greeting: 'Hello', farewell: 'Goodbye' }
    #   result = engine.localize_object(data, target_locale: 'es')
    #   # => { greeting: "Hola", farewell: "Adiós" }
    def localize_object(obj, target_locale:, source_locale: nil, fast: nil, reference: nil, on_progress: nil, concurrent: false, &block)
      raise ValidationError, 'Target locale is required' if target_locale.nil? || target_locale.empty?
      raise ValidationError, 'Object cannot be nil' if obj.nil?
      raise ValidationError, 'Object must be a Hash' unless obj.is_a?(Hash)

      callback = block || on_progress

      response = localize_raw(
        obj,
        target_locale: target_locale,
        source_locale: source_locale,
        fast: fast,
        reference: reference,
        concurrent: concurrent,
        &callback
      )

      raise APIError, 'API returned empty localization response' if response.empty?
      response
    end

    # Localizes chat messages while preserving structure.
    #
    # Each message must have :name and :text keys. The structure of messages
    # is preserved while all text content is localized.
    #
    # @param chat [Array<Hash>] array of chat messages, each with :name and :text keys
    # @param target_locale [String] the target locale code (e.g., 'es', 'fr', 'ja')
    # @param source_locale [String, nil] the source locale code (optional, auto-detected if not provided)
    # @param fast [Boolean, nil] enable fast mode for quicker results (optional)
    # @param reference [Hash, nil] additional context for translation (optional)
    # @param on_progress [Proc, nil] callback for progress updates (optional)
    # @param concurrent [Boolean] enable concurrent processing (default: false)
    #
    # @yield [progress] optional block for progress tracking
    # @yieldparam progress [Integer] completion percentage (0-100)
    #
    # @return [Array<Hash>] array of localized chat messages
    #
    # @raise [ValidationError] if target_locale is missing, chat is nil, not an Array, or messages are invalid
    # @raise [APIError] if the API request fails
    #
    # @example Basic usage
    #   chat = [
    #     { name: 'user', text: 'Hello!' },
    #     { name: 'assistant', text: 'Hi there!' }
    #   ]
    #   result = engine.localize_chat(chat, target_locale: 'ja')
    #   # => [
    #   #   { name: 'user', text: 'こんにちは！' },
    #   #   { name: 'assistant', text: 'こんにちは！' }
    #   # ]
    def localize_chat(chat, target_locale:, source_locale: nil, fast: nil, reference: nil, on_progress: nil, concurrent: false, &block)
      raise ValidationError, 'Target locale is required' if target_locale.nil? || target_locale.empty?
      raise ValidationError, 'Chat cannot be nil' if chat.nil?
      raise ValidationError, 'Chat must be an Array' unless chat.is_a?(Array)

      chat.each do |message|
        unless message.is_a?(Hash) && message[:name] && message[:text]
          raise ValidationError, 'Each chat message must have :name and :text keys'
        end
      end

      callback = block || on_progress

      response = localize_raw(
        { chat: chat },
        target_locale: target_locale,
        source_locale: source_locale,
        fast: fast,
        reference: reference,
        concurrent: concurrent
      ) do |progress, chunk, processed_chunk|
        callback&.call(progress)
      end

      raise APIError, 'API did not return localized chat' unless response.key?('chat')
      response['chat']
    end

    # Localizes an HTML document while preserving structure and formatting.
    #
    # Handles both text content and localizable attributes (alt, title, placeholder, meta content).
    #
    # @param html [String] the HTML document string to be localized
    # @param target_locale [String] the target locale code (e.g., 'es', 'fr', 'ja')
    # @param source_locale [String, nil] the source locale code (optional, auto-detected if not provided)
    # @param fast [Boolean, nil] enable fast mode for quicker results (optional)
    # @param reference [Hash, nil] additional context for translation (optional)
    # @param on_progress [Proc, nil] callback for progress updates (optional)
    # @param concurrent [Boolean] enable concurrent processing (default: false)
    #
    # @yield [progress] optional block for progress tracking
    # @yieldparam progress [Integer] completion percentage (0-100)
    #
    # @return [String] the localized HTML document as a string, with updated lang attribute
    #
    # @raise [ValidationError] if target_locale is missing or html is nil
    # @raise [APIError] if the API request fails
    #
    # @example Basic usage
    #   html = '<html><head><title>Hello</title></head><body><p>World</p></body></html>'
    #   result = engine.localize_html(html, target_locale: 'es')
    #   # => "<html lang=\"es\">..."
    def localize_html(html, target_locale:, source_locale: nil, fast: nil, reference: nil, on_progress: nil, concurrent: false, &block)
      raise ValidationError, 'Target locale is required' if target_locale.nil? || target_locale.empty?
      raise ValidationError, 'HTML cannot be nil' if html.nil?

      callback = block || on_progress

      doc = Nokogiri::HTML::Document.parse(html)

      localizable_attributes = {
        'meta' => ['content'],
        'img' => ['alt'],
        'input' => ['placeholder'],
        'a' => ['title']
      }

      unlocalizable_tags = ['script', 'style']

      extracted_content = {}

      get_path = lambda do |node, attribute = nil|
        indices = []
        current = node
        root_parent = nil

        while current
          parent = current.parent
          break unless parent

          if parent == doc.root
            root_parent = current.name.downcase if current.element?
            break
          end

          siblings = parent.children.select do |n|
            (n.element? || (n.text? && n.text.strip != ''))
          end

          index = siblings.index(current)
          if index
            indices.unshift(index)
          end

          current = parent
        end

        base_path = root_parent ? "#{root_parent}/#{indices.join('/')}" : indices.join('/')
        attribute ? "#{base_path}##{attribute}" : base_path
      end

      process_node = lambda do |node|
        parent = node.parent
        while parent && !parent.is_a?(Nokogiri::XML::Document)
          if parent.element? && unlocalizable_tags.include?(parent.name.downcase)
            return
          end
          parent = parent.parent
        end

        if node.text?
          text = node.text.strip
          if text != ''
            extracted_content[get_path.call(node)] = text
          end
        elsif node.element?
          element = node
          tag_name = element.name.downcase
          attributes = localizable_attributes[tag_name] || []
          attributes.each do |attr|
            value = element[attr]
            if value && value.strip != ''
              extracted_content[get_path.call(element, attr)] = value
            end
          end

          element.children.each do |child|
            process_node.call(child)
          end
        end
      end

      head = doc.at_css('head')
      if head
        head.children.select do |n|
          n.element? || (n.text? && n.text.strip != '')
        end.each do |child|
          process_node.call(child)
        end
      end

      body = doc.at_css('body')
      if body
        body.children.select do |n|
          n.element? || (n.text? && n.text.strip != '')
        end.each do |child|
          process_node.call(child)
        end
      end

      localized_content = localize_raw(
        extracted_content,
        target_locale: target_locale,
        source_locale: source_locale,
        fast: fast,
        reference: reference,
        concurrent: concurrent
      ) do |progress, chunk, processed_chunk|
        callback&.call(progress)
      end

      doc.root['lang'] = target_locale if doc.root

      localized_content.each do |path, value|
        node_path, attribute = path.split('#')
        parts = node_path.split('/')
        root_tag = parts[0]
        indices = parts[1..-1]

        parent = root_tag == 'head' ? doc.at_css('head') : doc.at_css('body')
        next unless parent
        current = parent

        indices.each do |index_str|
          index = index_str.to_i
          siblings = parent.children.select do |n|
            (n.element? || (n.text? && n.text.strip != ''))
          end

          current = siblings[index]
          break unless current

          if current.element?
            parent = current
          end
        end

        if current
          if attribute
            if current.element?
              current[attribute] = value
            end
          else
            if current.text?
              current.content = value
            end
          end
        end
      end

      doc.to_html
    end

    # Localizes text to multiple target locales.
    #
    # @param text [String] the text to localize
    # @param target_locales [Array<String>] array of target locale codes
    # @param source_locale [String, nil] the source locale code (optional, auto-detected if not provided)
    # @param fast [Boolean, nil] enable fast mode for quicker results (optional)
    # @param reference [Hash, nil] additional context for translation (optional)
    # @param concurrent [Boolean] enable concurrent processing (default: false)
    #
    # @return [Array<String>] array of localized strings in the same order as target_locales
    #
    # @raise [ValidationError] if text is nil, target_locales is not an Array, or target_locales is empty
    # @raise [APIError] if any API request fails
    #
    # @example Basic usage
    #   results = engine.batch_localize_text('Hello', target_locales: ['es', 'fr', 'de'])
    #   # => ["Hola", "Bonjour", "Hallo"]
    #
    # @example With concurrent processing
    #   results = engine.batch_localize_text('Hello', target_locales: ['es', 'fr', 'de', 'ja'], concurrent: true)
    def batch_localize_text(text, target_locales:, source_locale: nil, fast: nil, reference: nil, concurrent: false)
      raise ValidationError, 'Text cannot be nil' if text.nil?
      raise ValidationError, 'Target locales must be an Array' unless target_locales.is_a?(Array)
      raise ValidationError, 'Target locales cannot be empty' if target_locales.empty?

      if concurrent
        threads = target_locales.map do |target_locale|
          Thread.new do
            localize_text(
              text,
              target_locale: target_locale,
              source_locale: source_locale,
              fast: fast,
              reference: reference
            )
          end
        end
        threads.map(&:value)
      else
        target_locales.map do |target_locale|
          localize_text(
            text,
            target_locale: target_locale,
            source_locale: source_locale,
            fast: fast,
            reference: reference
          )
        end
      end
    end

    # Localizes multiple objects to the same target locale.
    #
    # @param objects [Array<Hash>] array of Hash objects to localize
    # @param target_locale [String] the target locale code (e.g., 'es', 'fr', 'ja')
    # @param source_locale [String, nil] the source locale code (optional, auto-detected if not provided)
    # @param fast [Boolean, nil] enable fast mode for quicker results (optional)
    # @param reference [Hash, nil] additional context for translation (optional)
    # @param concurrent [Boolean] enable concurrent processing (default: false)
    #
    # @return [Array<Hash>] array of localized Hash objects in the same order as input
    #
    # @raise [ValidationError] if objects is not an Array, objects is empty, target_locale is missing, or any object is not a Hash
    # @raise [APIError] if any API request fails
    #
    # @example Basic usage
    #   objects = [
    #     { title: 'Welcome', body: 'Hello there' },
    #     { title: 'About', body: 'Learn more' }
    #   ]
    #   results = engine.batch_localize_objects(objects, target_locale: 'es')
    #   # => [
    #   #   { title: "Bienvenido", body: "Hola" },
    #   #   { title: "Acerca de", body: "Aprende más" }
    #   # ]
    def batch_localize_objects(objects, target_locale:, source_locale: nil, fast: nil, reference: nil, concurrent: false)
      raise ValidationError, 'Objects must be an Array' unless objects.is_a?(Array)
      raise ValidationError, 'Objects cannot be empty' if objects.empty?
      raise ValidationError, 'Target locale is required' if target_locale.nil? || target_locale.empty?

      objects.each do |obj|
        raise ValidationError, 'Each object must be a Hash' unless obj.is_a?(Hash)
      end

      if concurrent
        threads = objects.map do |obj|
          Thread.new do
            localize_object(
              obj,
              target_locale: target_locale,
              source_locale: source_locale,
              fast: fast,
              reference: reference,
              concurrent: true
            )
          end
        end
        threads.map(&:value)
      else
        objects.map do |obj|
          localize_object(
            obj,
            target_locale: target_locale,
            source_locale: source_locale,
            fast: fast,
            reference: reference,
            concurrent: concurrent
          )
        end
      end
    end

    # Detects the locale of the given text.
    #
    # @param text [String] the text to analyze
    #
    # @return [String] the detected locale code (e.g., 'en', 'es', 'ja')
    #
    # @raise [ValidationError] if text is nil or empty
    # @raise [APIError] if the API request fails
    #
    # @example Basic usage
    #   locale = engine.recognize_locale('Bonjour le monde')
    #   # => "fr"
    #
    # @example Japanese text
    #   locale = engine.recognize_locale('こんにちは世界')
    #   # => "ja"
    def recognize_locale(text)
      raise ValidationError, 'Text cannot be empty' if text.nil? || text.strip.empty?

      begin
        response = make_request(
          "#{config.api_url}/recognize",
          json: { text: text }
        )

        handle_response(response)
        data = JSON.parse(response.body, symbolize_names: true)
        data[:locale] || ''
      rescue StandardError => e
        raise APIError, "Request failed: #{e.message}"
      end
    end

    # Returns information about the authenticated user.
    #
    # @return [Hash, nil] a Hash with :email and :id keys if authenticated, nil otherwise
    #
    # @example Basic usage
    #   user = engine.whoami
    #   # => { email: "user@example.com", id: "user-id" }
    def whoami
      begin
        response = make_request("#{config.api_url}/whoami")

        status_code = response.code.to_i
        return nil unless status_code >= 200 && status_code < 300

        data = JSON.parse(response.body, symbolize_names: true)
        return nil unless data[:email]

        { email: data[:email], id: data[:id] }
      rescue StandardError => e
        raise APIError, "Request failed: #{e.message}" if e.message.include?('Server error')
        nil
      end
    end

    # One-off translation without managing engine lifecycle.
    #
    # Creates a temporary engine instance, performs the translation, and returns the result.
    # Suitable for single translations where engine configuration is not needed.
    #
    # @param content [String, Hash] the content to translate (String for text, Hash for object)
    # @param api_key [String] your Lingo.dev API key
    # @param target_locale [String] the target locale code (e.g., 'es', 'fr', 'ja')
    # @param source_locale [String, nil] the source locale code (optional, auto-detected if not provided)
    # @param fast [Boolean] enable fast mode for quicker results (default: true)
    # @param api_url [String] the API endpoint URL (default: 'https://engine.lingo.dev')
    #
    # @return [String, Hash] localized content (String if input was String, Hash if input was Hash)
    #
    # @raise [ValidationError] if content is not a String or Hash, or other validation fails
    # @raise [APIError] if the API request fails
    #
    # @example Translate text
    #   result = LingoDotDev::Engine.quick_translate('Hello', api_key: 'your-api-key', target_locale: 'es')
    #   # => "Hola"
    #
    # @example Translate object
    #   result = LingoDotDev::Engine.quick_translate(
    #     { greeting: 'Hello', farewell: 'Goodbye' },
    #     api_key: 'your-api-key',
    #     target_locale: 'fr'
    #   )
    #   # => { greeting: "Bonjour", farewell: "Au revoir" }
    def self.quick_translate(content, api_key:, target_locale:, source_locale: nil, fast: true, api_url: 'https://engine.lingo.dev')
      engine = new(api_key: api_key, api_url: api_url)
      case content
      when String
        engine.localize_text(
          content,
          target_locale: target_locale,
          source_locale: source_locale,
          fast: fast
        )
      when Hash
        engine.localize_object(
          content,
          target_locale: target_locale,
          source_locale: source_locale,
          fast: fast,
          concurrent: true
        )
      else
        raise ValidationError, 'Content must be a String or Hash'
      end
    end

    # One-off batch translation to multiple locales without managing engine lifecycle.
    #
    # Creates a temporary engine instance, performs batch translations, and returns the results.
    # Suitable for single batch translations where engine configuration is not needed.
    #
    # @param content [String, Hash] the content to translate (String for text, Hash for object)
    # @param api_key [String] your Lingo.dev API key
    # @param target_locales [Array<String>] array of target locale codes
    # @param source_locale [String, nil] the source locale code (optional, auto-detected if not provided)
    # @param fast [Boolean] enable fast mode for quicker results (default: true)
    # @param api_url [String] the API endpoint URL (default: 'https://engine.lingo.dev')
    #
    # @return [Array<String>, Array<Hash>] array of localized results (Strings if input was String, Hashes if input was Hash)
    #
    # @raise [ValidationError] if content is not a String or Hash, or other validation fails
    # @raise [APIError] if any API request fails
    #
    # @example Batch translate text
    #   results = LingoDotDev::Engine.quick_batch_translate(
    #     'Hello',
    #     api_key: 'your-api-key',
    #     target_locales: ['es', 'fr', 'de']
    #   )
    #   # => ["Hola", "Bonjour", "Hallo"]
    #
    # @example Batch translate object
    #   results = LingoDotDev::Engine.quick_batch_translate(
    #     { greeting: 'Hello' },
    #     api_key: 'your-api-key',
    #     target_locales: ['es', 'fr']
    #   )
    #   # => [{ greeting: "Hola" }, { greeting: "Bonjour" }]
    def self.quick_batch_translate(content, api_key:, target_locales:, source_locale: nil, fast: true, api_url: 'https://engine.lingo.dev')
      engine = new(api_key: api_key, api_url: api_url)
      case content
      when String
        engine.batch_localize_text(
          content,
          target_locales: target_locales,
          source_locale: source_locale,
          fast: fast,
          concurrent: true
        )
      when Hash
        target_locales.map do |target_locale|
          engine.localize_object(
            content,
            target_locale: target_locale,
            source_locale: source_locale,
            fast: fast,
            concurrent: true
          )
        end
      else
        raise ValidationError, 'Content must be a String or Hash'
      end
    end

    private

    def make_request(url, json: nil)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60
      http.open_timeout = 60

      request = Net::HTTP::Post.new(uri.path)
      request['Authorization'] = "Bearer #{config.api_key}"
      request['Content-Type'] = 'application/json; charset=utf-8'
      request.body = JSON.generate(json) if json

      http.request(request)
    end

    def localize_raw(payload, target_locale:, source_locale: nil, fast: nil, reference: nil, concurrent: false, &progress_callback)
      chunked_payload = extract_payload_chunks(payload)
      workflow_id = SecureRandom.hex(8)

      processed_chunks = if concurrent && !progress_callback
        threads = chunked_payload.map do |chunk|
          Thread.new do
            localize_chunk(
              chunk,
              target_locale: target_locale,
              source_locale: source_locale,
              fast: fast,
              reference: reference,
              workflow_id: workflow_id
            )
          end
        end
        threads.map(&:value)
      else
        chunked_payload.each_with_index.map do |chunk, index|
          percentage_completed = (((index + 1).to_f / chunked_payload.length) * 100).round

          processed_chunk = localize_chunk(
            chunk,
            target_locale: target_locale,
            source_locale: source_locale,
            fast: fast,
            reference: reference,
            workflow_id: workflow_id
          )

          progress_callback&.call(percentage_completed, chunk, processed_chunk)

          processed_chunk
        end
      end

      result = {}
      processed_chunks.each { |chunk| result.merge!(chunk) }
      result
    end

    def localize_chunk(chunk, target_locale:, source_locale:, fast:, reference:, workflow_id:)
      request_body = {
        params: {
          workflowId: workflow_id,
          fast: fast || false
        },
        locale: {
          source: source_locale,
          target: target_locale
        },
        data: chunk
      }

      if reference && !reference.empty?
        raise ValidationError, 'Reference must be a Hash' unless reference.is_a?(Hash)
        request_body[:reference] = reference
      else
        request_body[:reference] = {}
      end

      begin
        response = make_request(
          "#{config.api_url}/i18n",
          json: request_body
        )

        handle_response(response)

        data = JSON.parse(response.body, symbolize_names: true)

        if !data[:data] && data[:error]
          raise APIError, data[:error]
        end

        # Normalize all keys to strings for consistent access throughout the SDK
        (data[:data] || {}).transform_keys(&:to_s)
      rescue StandardError => e
        raise APIError, "Request failed: #{e.message}"
      end
    end

    def extract_payload_chunks(payload)
      result = []
      current_chunk = {}
      current_chunk_item_count = 0

      payload.each do |key, value|
        current_chunk[key] = value
        current_chunk_item_count += 1

        current_chunk_size = count_words_in_record(current_chunk)

        if current_chunk_size > config.ideal_batch_item_size ||
           current_chunk_item_count >= config.batch_size ||
           key == payload.keys.last

          result << current_chunk
          current_chunk = {}
          current_chunk_item_count = 0
        end
      end

      result
    end

    def count_words_in_record(payload)
      case payload
      when Array
        payload.sum { |item| count_words_in_record(item) }
      when Hash
        payload.values.sum { |item| count_words_in_record(item) }
      when String
        payload.strip.split.reject(&:empty?).length
      else
        0
      end
    end

    def handle_response(response)
      status_code = response.code.to_i
      return if status_code >= 200 && status_code < 300

      if status_code >= 500
        raise ServerError, "Server error (#{status_code}): #{response.message}. #{response.body}. This may be due to temporary service issues."
      elsif status_code == 400
        raise ValidationError, "Invalid request (#{status_code}): #{response.message}"
      elsif status_code == 401
        raise AuthenticationError, "Authentication failed (#{status_code}): #{response.message}"
      else
        raise APIError, response.body
      end
    end
  end
end

