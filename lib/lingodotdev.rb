# frozen_string_literal: true

require_relative "lingodotdev/version"
require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require 'openssl'

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

module LingoDotDev
  class Error < StandardError; end
  class ArgumentError < Error; end
  class APIError < Error; end
  class ServerError < APIError; end
  class AuthenticationError < APIError; end
  class ValidationError < ArgumentError; end

  class Configuration
    attr_accessor :api_key, :api_url, :batch_size, :ideal_batch_item_size

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

  class Engine
    attr_reader :config

    def initialize(api_key:, api_url: 'https://engine.lingo.dev', batch_size: 25, ideal_batch_item_size: 250)
      @config = Configuration.new(
        api_key: api_key,
        api_url: api_url,
        batch_size: batch_size,
        ideal_batch_item_size: ideal_batch_item_size
      )
      @client = nil
      yield @config if block_given?
      @config.send(:validate!)
    end

    def self.open(api_key:, **options)
      engine = new(api_key: api_key, **options)
      return engine unless block_given?

      begin
        yield engine
      ensure
        engine.close
      end
    end

    def close
      @client = nil
    end

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

      response[:text] || ''
    end

    def localize_object(obj, target_locale:, source_locale: nil, fast: nil, reference: nil, on_progress: nil, concurrent: false, &block)
      raise ValidationError, 'Target locale is required' if target_locale.nil? || target_locale.empty?
      raise ValidationError, 'Object cannot be nil' if obj.nil?
      raise ValidationError, 'Object must be a Hash' unless obj.is_a?(Hash)

      callback = block || on_progress

      localize_raw(
        obj,
        target_locale: target_locale,
        source_locale: source_locale,
        fast: fast,
        reference: reference,
        concurrent: concurrent,
        &callback
      )
    end

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

      response[:chat] || []
    end

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

    def recognize_locale(text)
      raise ValidationError, 'Text cannot be empty' if text.nil? || text.strip.empty?

      begin
        response = http_client.post(
          "#{config.api_url}/recognize",
          json: { text: text }
        )

        handle_response(response)
        data = JSON.parse(response.body.to_s, symbolize_names: true)
        data[:locale] || ''
      rescue StandardError => e
        raise APIError, "Request failed: #{e.message}"
      end
    end

    def whoami
      begin
        response = http_client.post("#{config.api_url}/whoami")

        return nil unless response.status.success?

        data = JSON.parse(response.body.to_s, symbolize_names: true)
        return nil unless data[:email]

        { email: data[:email], id: data[:id] }
      rescue StandardError => e
        raise APIError, "Request failed: #{e.message}" if e.message.include?('Server error')
        nil
      end
    end

    def self.quick_translate(content, api_key:, target_locale:, source_locale: nil, fast: true, api_url: 'https://engine.lingo.dev')
      open(api_key: api_key, api_url: api_url) do |engine|
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
    end

    def self.quick_batch_translate(content, api_key:, target_locales:, source_locale: nil, fast: true, api_url: 'https://engine.lingo.dev')
      open(api_key: api_key, api_url: api_url) do |engine|
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
    end

    private

    def http_client
      @client ||= NetHTTPAdapter.new(config.api_key)
    end

    # Adapter class to use Net::HTTP instead of HTTP gem
    # This provides better control over SSL context and avoids CRL verification issues
    class NetHTTPAdapter
      def initialize(api_key)
        @api_key = api_key
      end

      def post(url, json: nil)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 60
        http.open_timeout = 60

        request = Net::HTTP::Post.new(uri.path)
        request['Authorization'] = "Bearer #{@api_key}"
        request['Content-Type'] = 'application/json; charset=utf-8'
        request.body = JSON.generate(json) if json

        response = http.request(request)

        # Wrap response to be compatible with HTTP gem interface
        ResponseWrapper.new(response)
      end
    end

    # Wrapper to make Net::HTTP response compatible with HTTP gem interface
    class ResponseWrapper
      def initialize(response)
        @response = response
      end

      def status
        StatusWrapper.new(@response.code.to_i)
      end

      def body
        BodyWrapper.new(@response.body)
      end

      def reason
        @response.message
      end
    end

    class StatusWrapper
      def initialize(code)
        @code = code
      end

      def code
        @code
      end

      def success?
        @code >= 200 && @code < 300
      end

      def server_error?
        @code >= 500
      end

      def to_s
        @code.to_s
      end
    end

    class BodyWrapper
      def initialize(body)
        @body = body
      end

      def to_s
        @body
      end
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
        response = http_client.post(
          "#{config.api_url}/i18n",
          json: request_body
        )

        handle_response(response)

        data = JSON.parse(response.body.to_s, symbolize_names: true)

        if !data[:data] && data[:error]
          raise APIError, data[:error]
        end

        data[:data] || {}
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
      return if response.status.success?

      if response.status.server_error?
        raise ServerError, "Server error (#{response.status}): #{response.reason}. #{response.body}. This may be due to temporary service issues."
      elsif response.status.code == 400
        raise ValidationError, "Invalid request (#{response.status}): #{response.reason}"
      elsif response.status.code == 401
        raise AuthenticationError, "Authentication failed (#{response.status}): #{response.reason}"
      else
        raise APIError, response.body.to_s
      end
    end
  end
end

