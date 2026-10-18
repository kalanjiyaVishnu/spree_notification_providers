# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module SpreeNotificationProviders
  # The one place bundled adapters make HTTP calls, so timeouts are uniform
  # and specs can stub a single method.
  module Http
    module_function

    # @param form [Hash] sent as application/x-www-form-urlencoded
    # @param json [Hash] sent as application/json
    def request(method, url, headers: {}, query: nil, form: nil, json: nil)
      uri = URI(url)
      uri.query = URI.encode_www_form(query) if query.present?
      klass = method.to_sym == :get ? Net::HTTP::Get : Net::HTTP::Post
      req = klass.new(uri.request_uri)
      headers.each { |name, value| req[name] = value }
      if form
        req.set_form_data(form)
      elsif json
        req['Content-Type'] = 'application/json'
        req.body = json.to_json
      end

      timeout = SpreeNotificationProviders.configuration.http_timeout_seconds
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: timeout,
                                          read_timeout: timeout, write_timeout: timeout) do |http|
        http.request(req)
      end
    end

    def parse_json(raw)
      parsed = JSON.parse(raw.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end
