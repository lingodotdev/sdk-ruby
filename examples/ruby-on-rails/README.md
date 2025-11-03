# Ruby on Rails Example with Lingo.dev SDK

This example demonstrates how to integrate and use the Lingo.dev Ruby SDK in a Ruby on Rails application.

## Overview

This minimal Rails application includes a simple translation controller that uses the SDK to translate "Hello world" from English to Spanish. It demonstrates:

- Integrating the SDK gem via local path reference
- Basic SDK usage with `LingoDotDev::Engine`
- Error handling for SDK operations
- A simple REST endpoint that returns JSON

## Prerequisites

- Ruby >= 3.2.0
- Bundler
- A Lingo.dev API key

## Setup

1. Navigate to this directory:

   ```bash
   cd examples/ruby-on-rails
   ```

2. Install dependencies:

   ```bash
   bundle install
   ```

3. Set your Lingo.dev API key:
   ```bash
   export LINGODOTDEV_API_KEY='your-api-key-here'
   ```

## Running

Start the Rails server:

```bash
bin/rails server
```

The server will start on `http://localhost:3000`.

## Testing the SDK

Once the server is running, test the translation endpoint:

```bash
curl http://localhost:3000/translate
```

Or visit `http://localhost:3000/translate` in your browser.

### Expected Response

On success:

```json
{
  "original": "Hello world",
  "translated": "Hola mundo",
  "target_locale": "es"
}
```

On error (e.g., missing or invalid API key):

```json
{
  "error": "LingoDotDev::AuthenticationError",
  "message": "Authentication failed..."
}
```

## SDK Integration Details

The SDK is integrated via a local path reference in the `Gemfile`:

```ruby
gem "sdk-ruby", path: "../../"
```

The translation logic is implemented in `app/controllers/translate_controller.rb`:

- Creates a `LingoDotDev::Engine` instance with the API key
- Calls `localize_text` to translate "Hello world" to Spanish (`es`)
- Returns JSON with the original and translated text
- Handles SDK errors and returns appropriate error responses

This demonstrates the simplest possible SDK usage - a single translation call to confirm the SDK works correctly in a Rails environment.
