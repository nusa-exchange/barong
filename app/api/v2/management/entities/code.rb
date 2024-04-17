# frozen_string_literal: true

module API::V2::Management
  module Entities
    class Code < API::V2::Entities::Base
      expose :id,
             documentation: {
               type: 'Integer',
               desc: 'Code ID'
             }
      
      expose :type,
             documentation: {
              type: 'String',
              desc: 'Code type'
             }

      expose :category,
             documentation: {
              type: 'String',
              desc: 'Code category'
             }

      expose :phone_number,
             documentation: {
              type: 'String',
              desc: 'Code phone number'
             }

      expose :email,
             documentation: {
              type: 'String',
              desc: 'Code email'
             }

      expose :attempt_count,
             documentation: {
              type: 'Integer',
              desc: 'Code attempt count'
             }

      expose :data,
             documentation: {
              type: 'String',
              desc: 'Code data'
             }

      with_options(format_with: :iso_timestamp) do
        expose :validated_at
        expose :expired_at
        expose :created_at
        expose :updated_at
      end
    end
  end
end
