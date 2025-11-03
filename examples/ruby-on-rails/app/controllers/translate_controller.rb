# frozen_string_literal: true

require 'lingodotdev'

class TranslateController < ApplicationController
  def translate
    api_key = ENV['LINGODOTDEV_API_KEY'] || 'your-api-key-here'

    engine = LingoDotDev::Engine.new(api_key: api_key)
    translated = engine.localize_text('Hello world', target_locale: 'es')

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
