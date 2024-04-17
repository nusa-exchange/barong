# frozen_string_literal: true

# twilio sms sender
class MockPhoneVerifyService
  class << self
    def send_confirmation(phone_number, code, _channel)
      Rails.logger.info("Sending SMS to #{phone_number}")

      send_sms(number: phone_number,
               content: Barong::App.config.sms_content_template.gsub(/{{code}}/, code))
    end

    def send_sms(number:, content:)
      from_phone = Barong::App.config.twilio_phone_number
      client = Barong::MockSMS.new('', '')
      client.messages.create(from: from_phone, to: '+' + number, body: content)
    end
  end
end
