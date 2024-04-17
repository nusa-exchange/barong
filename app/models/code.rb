# frozen_string_literal: true

#
# Class Phone
#
class Code < ApplicationRecord
  include Encryptable

  TYPES = %w[phone email]
  CATEGORIES = %w[phone_verification reset_password change_password otp withdrawal login register]

  belongs_to :user
  has_one :phone

  validates :code_type, inclusion: { in: TYPES }
  validates :category, inclusion: { in: CATEGORIES }

  attr_encrypted :email
  validates :email, email: true, if: :is_email?

  attr_encrypted :phone_number
  validates :phone_number, phone: true, if: :is_phone?

  before_validation :sanitize_phone_number

  before_save :save_phone_number_index
  before_save :save_email_index

  scope :verified, -> { where.not(validated_at: nil) }
  scope :pending, -> { where("validated_at IS NULL AND expired_at > ?", Time.now) }

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

    def find_by_phone_number(phone_number, attrs={})
      attrs.merge!(number_index: SaltedCrc32.generate_hash(phone_number))
      find_by(attrs)
    end

    def find_by_phone_number!(phone_number)
      find_by!(phone_number_index: SaltedCrc32.generate_hash(phone_number))
    end

    def find_by_email(email, attrs={})
      attrs.merge!(email_index: SaltedCrc32.generate_hash(email))
      find_by(attrs)
    end

    def find_by_email!(email)
      find_by!(email_index: SaltedCrc32.generate_hash(email))
    end
  end

  def is_email?
    code_type == 'email'
  end

  def is_phone?
    code_type == 'phone'
  end

  def generate_code!
    self.expired_at = Time.now + 15.minutes
    self.attempt_count = 0
    self.code = rand.to_s[2..7]

    if code_type == 'phone' && self.phone_number.nil?
      self.phone_number = user.phone.nunber
    elsif code_type == 'email' && self.email.nil?
      self.email = user.email if code_type == 'email'
    end

    send_code
    save!
  end

  def validated?
    return !validated_at.nil?
  end

  def expired?
    return true if validated?

    return expired_at <= Time.now
  end

  def out_attempt?
    return attempt_count >= 5
  end

  def check_code!
    return false if out_attempt?
    return false if expired?
    return false if validated?

    if self.code == verification_code
      return true
    end

    self.attempt_count += 1

    save!

    return false
  end

  def verify_code!(verification_code, allow_save = true)
    return false if out_attempt?
    return false if expired?
    return false if validated?

    self.attempt_count += 1
    if self.code == verification_code
      self.validated_at = Time.now
    end

    save! if (allow_save)

    return !self.validated_at.nil?
  end

  private

  def sanitize_phone_number
    self.phone_number = Phone.sanitize(phone_number)
  end

  def save_phone_number_index
    if phone_number.present?
      self.phone_number_index = SaltedCrc32.generate_hash(phone_number)
    end
  end

  def save_email_index
    if email.present?
      self.email_index = SaltedCrc32.generate_hash(email)
    end
  end

  def send_code
    if code_type == 'phone'
      Barong::App.config.twilio_provider.send_confirmation(
        phone_number,
        self.code.to_s,
        'sms'
      )
    else
      data_json = nil

      unless data.nil?
        data_json = JSON.parse(data)
      end

      EventAPI.notify(
        "system.#{category}.confirmation.code", # system.phone_verification.confirmation.code
        record: {
          user: user.as_json_for_event_api,
          domain: Barong::App.config.domain,
          code: self.code.to_s,
          data: data_json
        }
      )
    end
  end
end

# == Schema Information
#
# Table name: codes
#
#  id                     :bigint           not null, primary key
#  user_id                :integer          unsigned
#  code                   :string(6)        not null
#  code_type              :string(10)       not null
#  category               :string(20)       not null
#  email_encrypted        :string(255)      not null
#  email_index            :bigint           not null
#  phone_number_encrypted :string(255)      not null
#  phone_number_index     :bigint           not null
#  attempt_count          :integer          default(0), not null
#  validated_at           :datetime
#  expired_at             :datetime         not null
#  data                   :text(65535)
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_phones_on_user_id                   (user_id)
#  index_phones_on_email_index               (email_index)
#  index_phones_on_phone_number_index        (phone_number_index)
#
