# frozen_string_literal: true

#
# Class Phone
#
class Phone < ApplicationRecord
  include Encryptable

  TWILIO_CHANNELS = %w[call sms].freeze
  DEFAULT_COUNTRY_CODE_COUNT = 2

  belongs_to :code
  belongs_to :user

  attr_encrypted :number
  validates :number, phone: true

  before_validation :sanitize_number

  before_save :save_number_index

  scope :verified, -> { joins(:code).where("codes.validated_at IS NOT NULL") }

  #FIXME: Clean code below
  class << self
    def sanitize(unsafe_phone)
      unsafe_phone.to_s.gsub(/\D/, '')
    end

    def parse(unsafe_phone)
      Phonelib.parse self.sanitize(unsafe_phone)
    end

    def valid?(unsafe_phone)
      parse(unsafe_phone).valid?
    end

    def international(unsafe_phone)
      parse(unsafe_phone).international(false)
    end

    def find_by_number(number, attrs={})
      attrs.merge!(number_index: SaltedCrc32.generate_hash(number))
      find_by(attrs)
    end

    def find_by_number!(number)
      find_by!(number_index: SaltedCrc32.generate_hash(number))
    end
  end

  private

  def sanitize_number
    self.number = Phone.sanitize(number)
  end

  def save_number_index
    if number.present?
      self.number_index = SaltedCrc32.generate_hash(number)
    end
  end
end

# == Schema Information
#
# Table name: phones
#
#  id               :bigint           not null, primary key
#  user_id          :integer          unsigned, not null
#  code_id          :integer          unsigned, not null
#  code             :string(5)
#  number_encrypted :string(255)      not null
#  number_index     :bigint           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_phones_on_number_index               (number_index)
#  index_phones_on_user_id                    (user_id)
#  index_phones_on_code_id                    (user_id)
#  index_phones_on_user_id_and_code_id        (user_id, code_id)
#
