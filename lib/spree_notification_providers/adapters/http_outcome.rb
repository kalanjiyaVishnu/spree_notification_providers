# frozen_string_literal: true

require 'openssl'
require 'socket'

module SpreeNotificationProviders
  module Adapters
    # Turns an HTTP response or transport error into a Result.
    #
    # The router fails over only on :failed, so anything that might have
    # reached the provider is :unknown. See research R5.
    module HttpOutcome
      # The request never reached the provider.
      DEFINITE_ERRORS = {
        Net::OpenTimeout => 'connect_timeout',
        Errno::ECONNREFUSED => 'connection_refused',
        Errno::EHOSTUNREACH => 'host_unreachable',
        Errno::ENETUNREACH => 'network_unreachable',
        SocketError => 'dns_error',
        OpenSSL::SSL::SSLError => 'tls_error'
      }.freeze

      # The request may have reached the provider.
      AMBIGUOUS_ERRORS = {
        Net::ReadTimeout => 'read_timeout',
        Net::WriteTimeout => 'write_timeout',
        Errno::ECONNRESET => 'connection_reset',
        Errno::EPIPE => 'broken_pipe',
        EOFError => 'connection_closed'
      }.freeze

      module_function

      def from_error(error)
        DEFINITE_ERRORS.each { |klass, code| return Result.failed(code) if error.is_a?(klass) }
        AMBIGUOUS_ERRORS.each { |klass, code| return Result.unknown(code) if error.is_a?(klass) }

        Result.failed("exception:#{error.class.name}")
      end

      # @param accepted [Boolean] the adapter's reading of a 2xx body
      # @param provider_message [String, nil] short provider error text (already scrubbed)
      def from_response(response, body, accepted:, message_id: nil, provider_message: nil)
        code = response.code.to_i
        return Result.delivered(message_id) if code.between?(200, 299) && accepted

        detail = provider_message.presence
        if code.between?(200, 299)
          Result.failed(['rejected', detail].compact.join(': '))
        elsif code.between?(400, 499)
          Result.failed(["http_#{code}", detail].compact.join(': '))
        elsif body.present?
          # A 5xx that explains itself was a rejection.
          Result.failed(["http_#{code}", detail].compact.join(': '))
        else
          Result.unknown("http_#{code}")
        end
      end
    end
  end
end
