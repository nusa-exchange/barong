# frozen_string_literal: true
module API::V2
  module Identity
    module Utils
      def session
        request.session
      end

      def codec
        @_codec ||= Barong::JWT.new(key: Barong::App.config.keystore.private_key)
      end

      def open_session(user)
        csrf_token = SecureRandom.hex(10)
        expire_time = Time.now.to_i + Barong::App.config.session_expire_time
        session.merge!(
          "uid": user.uid,
          "user_ip": remote_ip,
          "user_ip_country": Barong::GeoIP.info(ip: remote_ip, key: :country),
          "user_agent": request.env['HTTP_USER_AGENT'],
          "expire_time": expire_time,
          "csrf_token": csrf_token,
          "authenticated_at": Time.now,
          "last_login_at": Time.now,
        )

        # Add current session key info in additional redis list
        Barong::RedisSession.add(user.uid, session, expire_time)

        csrf_token
      end

      def verify_captcha!(response:, endpoint:, error_statuses: [400, 422])
        # by default we protect user_create session_create password_reset email_confirmation endpoints
        return unless BarongConfig.list['captcha_protected_endpoints']&.include?(endpoint)

        case Barong::App.config.captcha
        when 'recaptcha'
          recaptcha(response: response)
        when 'geetest'
          geetest(response: response)
        end
      end

      def recaptcha(response:, error_statuses: [400, 422])
        error!({ errors: ['identity.captcha.required'] }, error_statuses.first) if response.blank?

        captcha_error_message = 'identity.captcha.verification_failed'

        return if CaptchaService::RecaptchaVerifier.new(request: request).response_valid?(skip_remote_ip: true, response: response)

        error!({ errors: [captcha_error_message] }, error_statuses.last)
      rescue StandardError
        error!({ errors: [captcha_error_message] }, error_statuses.last)
      end

      def geetest(response:, error_statuses: [400, 422])
        error!({ errors: ['identity.captcha.required'] }, error_statuses.first) if response.blank?

        geetest_error_message = 'identity.captcha.verification_failed'
        validate_geetest_response(response: response)

        return if CaptchaService::GeetestVerifier.new.validate(response)

        error!({ errors: [geetest_error_message] }, error_statuses.last)
      rescue StandardError
        error!({ errors: [geetest_error_message] }, error_statuses.last)
      end

      def validate_geetest_response(response:)
        unless (response['geetest_challenge'].is_a? String) &&
               (response['geetest_validate'].is_a? String) &&
               (response['geetest_seccode'].is_a? String)
          error!({ errors: ['identity.captcha.mandatory_fields'] }, 400)
        end
      end

      def login_error!(options = {})
        options[:data] = { reason: options[:reason] }.to_json
        options[:topic] = 'session'
        activity_record(options.except(:reason, :error_code, :error_text))
        content = { errors: ['identity.session.' + options[:error_text]] }
        if options[:error_text] != 'invalid_params'
          user = User.find_by(id: options[:user])

          content[:otp] = user.otp
          content[:phone] = !user.phone.nil?
        end
        error!(content, options[:error_code])
      end

      def activity_record(options = {})
        params = {
          category:        'user',
          user_id:         options[:user],
          user_ip:         remote_ip,
          user_ip_country: Barong::GeoIP.info(ip: remote_ip, key: :country),
          user_agent:      request.env['HTTP_USER_AGENT'],
          topic:           options[:topic],
          action:          options[:action],
          result:          options[:result],
          data:            options[:data]
        }
        Activity.create(params)
      end

      def publish_session_create(user)
        EventAPI.notify('system.session.create',
                        record: {
                          user: user.as_json_for_event_api,
                          user_ip: remote_ip,
                          user_agent: request.env['HTTP_USER_AGENT']
                        })
      end

      def management_api_request(method, url, payload)
        uri = URI(url)
        case method
        when "post"
          req = Net::HTTP::Post.new(uri)
        when "put"
          req = Net::HTTP::Put.new(uri)
        end
        req.body = generate_jwt_management(payload)
        req["Content-Type"] = "application/json"

        res = Net::HTTP.start(uri.hostname, uri.port) {|http|
          http.request(req)
        }
      end

      def publish_confirmation_code(user, type, event_name)
        res = management_api_request("post", "http://applogic:3000/api/management/users/verify/get", { type: type, email: user.email })

        if res.code.to_i != 200
          management_api_request("post", "http://applogic:3000/api/management/users/verify", { type: type, email: user.email, event_name: event_name })
        else
          management_api_request("put", "http://applogic:3000/api/management/users/verify", { type: type, email: user.email, reissue: true, event_name: event_name })
        end
      end
    end
  end
end
