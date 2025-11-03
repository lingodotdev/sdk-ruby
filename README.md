# Lingo.dev Ruby SDK

A Ruby SDK for integrating with the [Lingo.dev](https://lingo.dev) localization and translation API. Localize text, objects, and chat messages with support for batch operations, progress tracking, and concurrent processing.

## Overview

The Lingo.dev Ruby SDK provides a simple and powerful interface for localizing content in your Ruby applications. It supports:

- Text, object (Hash), and chat message localization
- Batch operations for multiple locales or objects
- Automatic locale recognition
- Progress tracking with callbacks
- Concurrent processing for improved performance
- Comprehensive error handling and validation

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lingodotdev'
```

And then execute:

```bash
bundle install
```

Or install it yourself with:

```bash
gem install lingodotdev
```

## Quick start

```ruby
require 'lingodotdev'

# Create an engine instance
engine = LingoDotDev::Engine.new(api_key: 'your-api-key')

# Localize text
result = engine.localize_text('Hello world', target_locale: 'es')
puts result # => "Hola mundo"
```

## Usage

### Basic text localization

Localize a simple string to a target locale:

```ruby
engine = LingoDotDev::Engine.new(api_key: 'your-api-key')

result = engine.localize_text(
  'Hello world',
  target_locale: 'es'
)
# => "Hola mundo"

# With source locale specified
result = engine.localize_text(
  'Hello world',
  target_locale: 'fr',
  source_locale: 'en'
)
# => "Bonjour le monde"

# Fast mode for quicker results
result = engine.localize_text(
  'Hello world',
  target_locale: 'de',
  fast: true
)
# => "Hallo Welt"
```

### Object localization

Localize all string values in a Hash:

```ruby
data = {
  greeting: 'Hello',
  farewell: 'Goodbye',
  message: 'Welcome to our app'
}

result = engine.localize_object(data, target_locale: 'es')
# => {
#   greeting: "Hola",
#   farewell: "Adiós",
#   message: "Bienvenido a nuestra aplicación"
# }
```

### Chat message localization

Localize chat conversations while preserving structure:

```ruby
chat = [
  { name: 'user', text: 'Hello!' },
  { name: 'assistant', text: 'Hi there! How can I help you?' },
  { name: 'user', text: 'I need some information.' }
]

result = engine.localize_chat(chat, target_locale: 'ja')
# => [
#   { name: 'user', text: 'こんにちは！' },
#   { name: 'assistant', text: 'こんにちは！どのようにお手伝いできますか？' },
#   { name: 'user', text: '情報が必要です。' }
# ]
```

### Batch localization to multiple locales

Localize the same content to multiple target locales:

```ruby
# Batch localize text
results = engine.batch_localize_text(
  'Hello world',
  target_locales: ['es', 'fr', 'de']
)
# => ["Hola mundo", "Bonjour le monde", "Hallo Welt"]

# With concurrent processing for better performance
results = engine.batch_localize_text(
  'Hello world',
  target_locales: ['es', 'fr', 'de', 'ja'],
  concurrent: true
)
```

### Batch localization of multiple objects

Localize multiple objects to the same target locale:

```ruby
objects = [
  { title: 'Welcome', body: 'Hello there' },
  { title: 'About', body: 'Learn more about us' },
  { title: 'Contact', body: 'Get in touch' }
]

results = engine.batch_localize_objects(
  objects,
  target_locale: 'es',
  concurrent: true
)
# => [
#   { title: "Bienvenido", body: "Hola" },
#   { title: "Acerca de", body: "Aprende más sobre nosotros" },
#   { title: "Contacto", body: "Ponte en contacto" }
# ]
```

### Locale recognition

Automatically detect the locale of a given text:

```ruby
locale = engine.recognize_locale('Bonjour le monde')
# => "fr"

locale = engine.recognize_locale('こんにちは世界')
# => "ja"
```

### Progress tracking

Monitor localization progress with callbacks:

```ruby
# Using a block
result = engine.localize_text('Hello world', target_locale: 'es') do |progress|
  puts "Progress: #{progress}%"
end

# Using the on_progress parameter
callback = proc { |progress| puts "Progress: #{progress}%" }
result = engine.localize_text(
  'Hello world',
  target_locale: 'es',
  on_progress: callback
)
```

### Reference context

Provide additional context to improve translation accuracy:

```ruby
reference = {
  context: 'greeting',
  tone: 'formal',
  domain: 'business'
}

result = engine.localize_text(
  'Hello',
  target_locale: 'ja',
  reference: reference
)
```

### Quick translate convenience methods

For one-off translations without managing engine instances:

```ruby
# Quick translate a string
result = LingoDotDev::Engine.quick_translate(
  'Hello world',
  api_key: 'your-api-key',
  target_locale: 'es'
)

# Quick translate a hash
result = LingoDotDev::Engine.quick_translate(
  { greeting: 'Hello', farewell: 'Goodbye' },
  api_key: 'your-api-key',
  target_locale: 'fr'
)

# Quick batch translate to multiple locales
results = LingoDotDev::Engine.quick_batch_translate(
  'Hello',
  api_key: 'your-api-key',
  target_locales: ['es', 'fr', 'de']
)
```

### User information

Check the authenticated user details:

```ruby
user = engine.whoami
# => { email: "user@example.com", id: "user-id" }
```

## Configuration

The SDK can be configured when creating an engine instance:

```ruby
engine = LingoDotDev::Engine.new(
  api_key: 'your-api-key',          # Required: Your Lingo.dev API key
  api_url: 'https://engine.lingo.dev', # Optional: API endpoint URL
  batch_size: 25,                    # Optional: Max items per batch (1-250)
  ideal_batch_item_size: 250         # Optional: Target word count per batch (1-2500)
)
```

You can also configure using a block:

```ruby
engine = LingoDotDev::Engine.new(api_key: 'your-api-key') do |config|
  config.batch_size = 50
  config.ideal_batch_item_size = 500
end
```

### Configuration options

| Option                  | Type    | Default                    | Description                               |
| ----------------------- | ------- | -------------------------- | ----------------------------------------- |
| `api_key`               | String  | Required                   | Your Lingo.dev API key                    |
| `api_url`               | String  | `https://engine.lingo.dev` | API endpoint URL                          |
| `batch_size`            | Integer | `25`                       | Maximum items per batch (1-250)           |
| `ideal_batch_item_size` | Integer | `250`                      | Target word count per batch item (1-2500) |

## API reference

### Instance methods

#### `localize_text(text, target_locale:, source_locale: nil, fast: nil, reference: nil, on_progress: nil, concurrent: false, &block)`

Localizes a string to the target locale.

- **Parameters:**
  - `text` (String): Text to localize
  - `target_locale` (String): Target locale code (e.g., 'es', 'fr', 'ja')
  - `source_locale` (String, optional): Source locale code
  - `fast` (Boolean, optional): Enable fast mode
  - `reference` (Hash, optional): Additional context for translation
  - `on_progress` (Proc, optional): Progress callback
  - `concurrent` (Boolean): Enable concurrent processing
  - `&block`: Alternative progress callback
- **Returns:** Localized string

#### `localize_object(obj, target_locale:, source_locale: nil, fast: nil, reference: nil, on_progress: nil, concurrent: false, &block)`

Localizes all string values in a Hash.

- **Parameters:** Same as `localize_text`, with `obj` (Hash) instead of `text`
- **Returns:** Localized Hash

#### `localize_chat(chat, target_locale:, source_locale: nil, fast: nil, reference: nil, on_progress: nil, concurrent: false, &block)`

Localizes chat messages. Each message must have `:name` and `:text` keys.

- **Parameters:** Same as `localize_text`, with `chat` (Array) instead of `text`
- **Returns:** Array of localized chat messages

#### `batch_localize_text(text, target_locales:, source_locale: nil, fast: nil, reference: nil, concurrent: false)`

Localizes text to multiple target locales.

- **Parameters:**
  - `text` (String): Text to localize
  - `target_locales` (Array): Array of target locale codes
  - Other parameters same as `localize_text`
- **Returns:** Array of localized strings

#### `batch_localize_objects(objects, target_locale:, source_locale: nil, fast: nil, reference: nil, concurrent: false)`

Localizes multiple objects to the same target locale.

- **Parameters:**
  - `objects` (Array): Array of Hash objects
  - `target_locale` (String): Target locale code
  - Other parameters same as `localize_object`
- **Returns:** Array of localized Hash objects

#### `recognize_locale(text)`

Detects the locale of the given text.

- **Parameters:**
  - `text` (String): Text to analyze
- **Returns:** Locale code string

#### `whoami`

Returns information about the authenticated user.

- **Returns:** Hash with `:email` and `:id` keys, or `nil` if authentication fails

### Class methods

#### `Engine.quick_translate(content, api_key:, target_locale:, source_locale: nil, fast: true, api_url: 'https://engine.lingo.dev')`

One-off translation without managing engine lifecycle.

- **Parameters:**
  - `content` (String or Hash): Content to translate
  - Other parameters as in instance methods
- **Returns:** Translated String or Hash

#### `Engine.quick_batch_translate(content, api_key:, target_locales:, source_locale: nil, fast: true, api_url: 'https://engine.lingo.dev')`

One-off batch translation to multiple locales.

- **Parameters:**
  - `content` (String or Hash): Content to translate
  - `target_locales` (Array): Array of target locale codes
  - Other parameters as in instance methods
- **Returns:** Array of translated results

## Error handling

The SDK defines custom exception classes for different error scenarios:

```ruby
begin
  engine = LingoDotDev::Engine.new(api_key: 'your-api-key')
  result = engine.localize_text('Hello', target_locale: 'es')
rescue LingoDotDev::ValidationError => e
  # Invalid input or configuration
  puts "Validation error: #{e.message}"
rescue LingoDotDev::AuthenticationError => e
  # Invalid API key or authentication failure
  puts "Authentication error: #{e.message}"
rescue LingoDotDev::ServerError => e
  # Server-side error (5xx)
  puts "Server error: #{e.message}"
rescue LingoDotDev::APIError => e
  # General API error
  puts "API error: #{e.message}"
rescue LingoDotDev::Error => e
  # Base error class for all SDK errors
  puts "Error: #{e.message}"
end
```

### Exception hierarchy

- `LingoDotDev::Error` (base class)
  - `LingoDotDev::ArgumentError`
    - `LingoDotDev::ValidationError` - Invalid input or configuration
  - `LingoDotDev::APIError` - API request errors
    - `LingoDotDev::AuthenticationError` - Authentication failures
    - `LingoDotDev::ServerError` - Server-side errors (5xx)

## Development

After checking out the repository, run `bin/setup` to install dependencies.

To run the test suite:

```bash
# Set your API key
export LINGODOTDEV_API_KEY='your-api-key'

# Run tests
bundle exec rspec
```

You can also run `bin/console` for an interactive prompt to experiment with the SDK.

To install this gem onto your local machine, run:

```bash
bundle exec rake install
```

## Requirements

- Ruby >= 3.2.0

## Dependencies

- `http` ~> 5.0
- `json` ~> 2.0

## License

See the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
