# frozen_string_literal: true

require 'rails_helper'

RSpec.configure do |config|
  # Specify a root folder where Swagger JSON files are generated
  # NOTE: If you're using the rswag-api to serve API descriptions, you'll need
  # to ensure that it's configured to serve Swagger from the same folder
  config.openapi_root = Rails.root.join('swagger').to_s

  # Define one or more Swagger documents and provide global metadata for each one
  # When you run the 'rswag:specs:swaggerize' rake task, the complete Swagger will
  # be generated at the provided relative path under openapi_root
  # By default, the operations defined in spec files are added to the first
  # document below. You can override this behavior by adding a openapi_spec tag to the
  # the root example_group in your specs, e.g. describe '...', openapi_spec: 'v2/swagger.json'
  config.openapi_specs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'Anava API',
        version: 'v1',
        description: 'Recording management API (health, statistics, recordings CRUD, analytics, device models).'
      },
      paths: {},
      servers: [
        {
          url: 'http://localhost:8085',
          description: 'Local Docker Compose'
        }
      ],
      components: {
        schemas: {
          Recording: {
            type: :object,
            properties: {
              id: { type: :integer },
              user_id: { type: :string },
              model: { type: :string, description: 'Device model; server-assigned from the X-Device-Model header' },
              build: { type: :string, description: "Client's IP, server-assigned from the X-Forwarded-For header" },
              version: { type: :string, description: 'App version; server-assigned from the X-App-Version header' },
              date: { type: :string, format: 'date' },
              slot_id: { type: :integer },
              start_timestamp: { type: :integer, format: 'int64', description: 'Epoch milliseconds' },
              end_timestamp: { type: :integer, format: 'int64', description: 'Epoch milliseconds' },
              amplitudes_json: { type: :string, description: 'JSON-encoded array of amplitude samples' },
              longitude: {
                type: :string, nullable: true,
                description: 'Decimal degrees; a JSON string (Active Record serializes BigDecimal as a string, not a JSON number)'
              },
              latitude: {
                type: :string, nullable: true,
                description: 'Decimal degrees; a JSON string (Active Record serializes BigDecimal as a string, not a JSON number)'
              },
              duration: { type: :integer, nullable: true, description: 'Seconds; computed from timestamps if omitted' },
              percentage: { type: :integer, nullable: true },
              file_path: { type: :string, nullable: true, description: 'Path to the recording\'s stored WAV file, if any' },
              created_at: { type: :string, format: 'date-time' },
              updated_at: { type: :string, format: 'date-time' }
            }
          }
        }
      }
    }
  }

  # Specify the format of the output Swagger file when running 'rswag:specs:swaggerize'.
  # The openapi_specs configuration option has the filename including format in
  # the key, this may want to be changed to avoid putting yaml in json files.
  # Defaults to json. Accepts ':json' and ':yaml'.
  config.openapi_format = :yaml
end
