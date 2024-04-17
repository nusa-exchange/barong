# frozen_string_literal: true

# twilio process verification
class TwilioVerifyService
  class << self
    def send_confirmation(phone_number, code, channel)
      Rails.logger.info("Sending code to #{phone_number} via #{channel}")

      send_code(number: phone_number, channel: channel)
    end

    def send_code(number:, channel:)
      verify_client.services(@service_sid)
                   .verifications
                   .create(to: '+' + number, channel: channel)
    end
  end
end
