# frozen_string_literal: true

require 'lingodotdev'

class TranslateController < ApplicationController
  def translate
    api_key = ENV['LINGODOTDEV_API_KEY'] || 'your-api-key-here'
    engine_id = ENV['LINGODOTDEV_ENGINE_ID'] || 'your-engine-id-here'

    engine = LingoDotDev::Engine.new(api_key: api_key, engine_id: engine_id)
    translated = engine.localize_text('Hello world', target_locale: 'es', source_locale: 'en')

    render json: {
      original: 'Hello world',
      translated: translated,
      target_locale: 'es'
    }
  rescue LingoDotDev::Error => e
    render json: {
      error: e.class.name,
      message: e.message
    }, status: :unprocessable_entity
  end
end
