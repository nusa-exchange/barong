# frozen_string_literal: true

module API::V2
  module Resource
    class Phones < Grape::API
      rescue_from(Twilio::REST::RestError) do |error|
        Rails.logger.error "Twilio Client Error: #{error.message}"
        error!({ errors: [twilio_dictionary_error(error.code)] }, 422)
      end

      helpers do
        def validate_phone!(phone_number)
          phone_number = Phone.international(phone_number)

          error!({ errors: ['resource.phone.invalid_num'] }, 400) \
            unless Phone.valid?(phone_number)

          error!({ errors: ['resource.phone.number_exist'] }, 400) \
            if Phone.verified.find_by_number(phone_number)
        end
      end

      desc 'Phone related routes'
      resource :phones do
        desc 'Returns list of user\'s phones',
          failure: [
            { code: 401, message: 'Invalid bearer token' },
          ],
          success: Entities::Phone
        get do
          present current_user.phone, with: Entities::Phone
        end

        desc 'Add/update phone',
          failure: [
            { code: 400, message: 'Required params are empty' },
            { code: 401, message: 'Invalid bearer token' },
            { code: 404, message: 'Record is not found' },
            { code: 422, message: 'Validation errors' }
          ],
          success: { code: 200, message: 'New phone was added' }
        params do
          optional :phone_number,
                   type: String,
                   desc: 'Phone number with country code'
        end
        post do
          declared_params = declared(params)

          # do resend code
          if declared_params[:phone_number].blank?
            phone = Phone.find_by(user: current_user)
            if phone.nil?
              error!({ errors: ['resource.phone.missing_phone'] }, 422)
            end

            code = ::Code.pending.find_or_create_by(user: current_user, code_type: 'phone', category: 'phone_verification')
            code.generate_code!

            phone.code_id = code.id
            phone.save!

            present 200
          else 
            validate_phone!(declared_params[:phone_number])

            phone_number = Phone.international(declared_params[:phone_number])

            code = ::Code.pending.find_or_create_by(user: current_user, code_type: 'phone', category: 'phone_verification')
            code.phone_number = phone_number
            code.generate_code!

            unless Phone.find_by(user: current_user).nil?
              error!({ errors: ['resource.phone.exists'] }, 400) if Phone.find_by_number(phone_number)

              phone = Phone.find_by(user: current_user)

              phone.code_id = code.id
              phone.code = code
              phone = current_user.phone
              phone.number = phone_number
              phone.save!
            else
              phone = Phone.create(user: current_user, code: code, number: phone_number)
              phone.save!
            end

            code_error!(phone.errors.details, 422) if phone.errors.any?

            present 200
          end
        end

        desc 'Verify a phone',
          failure: [
            { code: 400, message: 'Required params are empty' },
            { code: 401, message: 'Invalid bearer token' },
            { code: 404, message: 'Record is not found' }
          ],
          success: API::V2::Entities::UserWithFullInfo
        params do
          requires :verification_code,
                   type: String,
                   allow_blank: false,
                   desc: 'Verification code from sms'
        end
        post '/verify' do
          declared_params = declared(params)

          error!({ errors: ['resource.phone.doesnt_exist'] }, 422) if Phone.find_by(user: current_user).nil?
          error!({ errors: ['resource.phone.code_invalid'] }, 422) unless current_user.phone.code.verify_code!(declared_params[:verification_code])

          current_user.labels.create(key: 'phone', value: 'verified', scope: 'private')

          present current_user, with: API::V2::Entities::UserWithFullInfo
        end
      end
    end
  end
end
