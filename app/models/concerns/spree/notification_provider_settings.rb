# frozen_string_literal: true

module Spree
  # Input storage shared by provider configs and channel entries: plain
  # values in the `settings` jsonb column, secret values as a JSON object in
  # the encrypted `secret_settings` text column.
  module NotificationProviderSettings
    extend ActiveSupport::Concern

    included do
      encrypts :secret_settings
      attr_reader :input_errors

      after_initialize { @input_errors = {} }
    end

    def plain_values
      (settings || {}).to_h.stringify_keys
    end

    def secret_values
      parsed = JSON.parse(secret_settings.presence || '{}')
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def raw_value(input)
      (input.secret? ? secret_values : plain_values)[input.key].presence
    end

    def write_raw(input, value)
      if input.secret?
        values = secret_values
        value.present? ? values[input.key] = value.to_s : values.delete(input.key)
        self.secret_settings = values.to_json
      else
        values = plain_values
        value.present? ? values[input.key] = value.to_s : values.delete(input.key)
        self.settings = values
      end
    end

    # Applies a form submit. A blank secret keeps the stored value; a secret
    # listed in `clear` is removed. Plain inputs not present in `values` are
    # left alone.
    def assign_inputs(inputs, values: {}, secrets: {}, clear: [])
      values = values.to_h.stringify_keys
      secrets = secrets.to_h.stringify_keys
      clear = Array(clear).map(&:to_s)

      inputs.each do |input|
        if input.secret?
          if clear.include?(input.key)
            write_raw(input, nil)
          elsif secrets[input.key].to_s.strip.present?
            write_raw(input, secrets[input.key].to_s.strip)
          end
        elsif values.key?(input.key)
          write_raw(input, values[input.key].to_s.strip)
        end
      end
    end

    def secret_set?(input)
      raw_value(input).present?
    end

    private

    def validate_inputs(inputs)
      inputs.each do |input|
        message = input.validate(raw_value(input))
        next unless message

        input_errors[input.key] = message
        errors.add(:base, "#{input.label} #{message}")
      end
    end
  end
end
