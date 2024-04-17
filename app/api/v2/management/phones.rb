# frozen_string_literal: true

module API::V2
  module Management
    class Phones < Grape::API
      helpers do
        def validate_phone!(phone_number)
          error!('management.phone.invalid_num', 400) unless Phone.valid?(phone_number)
          error!('management.phone.number_exist', 400) if Phone.verified.find_by_number(phone_number)
        end
      end

      desc 'Phones related routes'
      resource :phones do

        desc 'Get user phone numbers' do
          @settings[:scope] = :read_phones
          success API::V2::Management::Entities::Phone
        end
        params do
          requires :uid, type: String, desc: 'User uid', allow_blank: false
        end
        post '/get' do
          user = User.find_by(uid: params[:uid])
          error!('user.doesnt_exist', 422) unless user

          present user.phone, with: API::V2::Management::Entities::Phone
        end
        
        desc 'Send message to user phone numbers' do
          @settings[:scope] = :send_phones
        end
        params do
          requires :uid, type: String, desc: 'User uid', allow_blank: false
          requires :content, type: String, desc: 'Message content', allow_blank: false
        end
        post '/send' do
          user = User.find_by(uid: params[:uid])
          error!('user.doesnt_exist', 422) unless user
          error!('management.phone.doesnt_exists', 422) unless user.phone
          
          TwilioSmsSendService.send_sms(number: user.phone.number, content: params[:content])

          present 200
        end

        desc 'Create phone number for user' do
          @settings[:scope] = :write_phones
          success API::V2::Management::Entities::Phone
        end
        params do
          requires :uid, type: String, desc: 'User uid', allow_blank: false
          requires :number, type: String, desc: 'User phone number', allow_blank: false
        end
        post do
          user = User.find_by(uid: params[:uid])
          error!('user.doesnt_exist', 422) unless user

          phone_number = Phone.international(params[:number])
          validate_phone!(phone_number)

          error!('management.phone.exists', 400) if user.phone

          phone = user.phone.create(number: params[:number], validated_at: Time.now)
          error!(phone.errors.full_messages, 422) if phone.errors.any?

          present phone, with: API::V2::Management::Entities::Phone
        end

        desc 'Delete phone number for user' do
          @settings[:scope] = :write_phones
          success API::V2::Management::Entities::Phone
        end
        params do
          requires :uid, type: String, desc: 'User uid', allow_blank: false
          requires :number, type: String, desc: 'User phone number', allow_blank: false
        end
        post '/delete' do
          user = User.find_by(uid: params[:uid])
          error!('user.doesnt_exist', 422) unless user

          phone_number = Phone.international(params[:number])
          phone = user.phone if phone_number.present?
          error!('management.phone.doesnt_exists', 422) unless phone

          present phone.destroy, with: API::V2::Management::Entities::Phone
        end
      end
    end
  end
end
