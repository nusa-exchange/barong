# frozen_string_literal: true

require 'ostruct'

class EventMailer
  Error = Class.new(StandardError)

  class VerificationError < Error; end

  def initialize(events, exchanges, keychain)
    @exchanges = exchanges
    @keychain = keychain
    @events = events

    Kernel.at_exit { unlisten }
  end

  def call
    listen
  end

  private

  def listen
    begin
      @consumer = ::Stream.consumer
      @exchanges.each do |_, exchange|
        ::Stream.create_topic(exchange[:name])
        @consumer.subscribe(exchange[:name])
      end

      @consumer.each_message(automatically_mark_as_processed: false) do |message|
        handle_message(message.topic, message.key, message.value)

        @consumer.mark_message_as_processed(message)
      end
    rescue => e
      Rails.logger.info { e }
    end
  end

  def unlisten
    if @consumer
      Rails.logger.info { 'No longer listening for events.' }

      @consumer.stop
    else
      @consumer = nil
    end
  end

  def algorithm_verification_options(signer)
    { algorithms: @keychain[signer][:algorithm] }
  end

  def jwt_public_key(signer)
    OpenSSL::PKey.read(Base64.urlsafe_decode64(@keychain[signer][:value]))
  end

  def handle_message(topic, key, payload)
    Rails.logger.info { "Start handling a message" }
    Rails.logger.info { "Payload: #{payload}" }

    exchange_name = @exchanges.select { |_, ex| ex[:name] == topic }.keys.first
    Rails.logger.info { exchange_name }
    exchange      = @exchanges.select { |_, ex| ex[:name] == topic }[exchange_name]
    Rails.logger.info { exchange }
    exchange_id   = exchange[:name]
    signer        = exchange[:signer]

    result = verify_jwt(payload, signer.to_sym)

    raise VerificationError, "Failed to verify signature from #{signer}." \
      unless result[:verified].include?(signer.to_sym)

    config = @events.select do |event|
      karr = key.split('.')
      karr.shift(1)
      event[:key] == karr.join('.')
    end.first

    event = result[:payload].fetch(:event)
    obj   = JSON.parse(event.to_json, object_class: OpenStruct)

    user  = User.includes(:profiles).find_by(uid: obj.record.user.uid)
    language = user.language.downcase.to_sym
    Rails.logger.info { "User #{user.email} has '#{language}' email language" }
    template_config = config[:templates].transform_keys(&:downcase)

    unless template_config.keys.include?(language)
      Rails.logger.error { "Language #{language} is not supported. Skipping." }
      return
    end

    if config[:expression].present? && skip_event(event, config[:expression])
      Rails.logger.info { "Event #{obj.name} skipped" }
      return
    end

    params = {
      logo: Barong::App.config.smtp_logo_link,
      subject: template_config[language][:subject],
      template_name: template_config[language][:template_path],
      record: obj.record,
      changes: obj.changes,
      user: user
    }

    Postmaster.process_payload(params).deliver_now

  rescue StandardError => e
    Rails.logger.error { e.inspect }

    unlisten if db_connection_error?(e)
  end

  def verify_jwt(payload, signer)
    options = algorithm_verification_options(signer)
    JWT::Multisig.verify_jwt JSON.parse(payload), { signer => jwt_public_key(signer) },
                             options.compact
  end

  def skip_event(event, expression)
    # valid operators: and / or / not
    operator = expression.keys.first.downcase
    # { field_name: field_value }
    values = expression[operator]

    # return array of boolean [false, true]
    res = values.keys.map do |field_name|
      safe_dig(event, field_name.to_s.split('.')) == values[field_name]
    end

    # all? works as AND operator, any? works as OR operator
    return false if (operator == :and && res.all?) || (operator == :or && res.any?) ||
                    (operator == :not && !res.all?)

    return true if operator == :not && res.all?

    true
  end

  def db_connection_error?(exception)
    exception.is_a?(Mysql2::Error::ConnectionError) || exception.cause.is_a?(Mysql2::Error)
  end

  def safe_dig(hash, keypath, default = nil)
    stringified_hash = JSON.parse(hash.to_json)
    stringified_keypath = keypath.map(&:to_s)

    stringified_keypath.reduce(stringified_hash) do |accessible, key|
      return default unless accessible.is_a? Hash
      return default unless accessible.key? key

      accessible[key]
    end
  end

  class << self
    def call(*args)
      new(*args).call
    end
  end
end
