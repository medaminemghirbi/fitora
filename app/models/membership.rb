# A person's link to one gym. The person (Client) is global — one row per
# human, identified by their email — and belongs to as many gyms as they like;
# everything the gym owns about them (when they joined, whether they are still
# active there, the gym's private notes, and the personal details it wrote
# down — date of birth, gender, address, emergency contact) lives here, not on
# the person. A second gym that records the same email starts with a blank
# copy: it never reads what the first gym wrote.
class Membership < ApplicationRecord
  # The face the desk checks against the person at the door. This gym's
  # own, like everything else here: another gym never sees it.
  include HasPhoto

  belongs_to :client
  belongs_to :company

  # The member's card at this gym: the number its QR code carries, and what
  # the desk types when the card is left at home. Eight digits, drawn at
  # random so a member cannot guess their neighbour's.
  CARD_CODE_DIGITS = 8
  CARD_CODE_FORMAT = /\A\d{#{CARD_CODE_DIGITS}}\z/

  before_validation { self.joined_at ||= Time.current }
  before_validation :assign_card_code, on: :create

  validates :client_id, uniqueness: { scope: :company_id }
  validates :card_code, uniqueness: { scope: :company_id }, format: { with: CARD_CODE_FORMAT }, allow_nil: true

  # What a gym may write about the person it trains, all on its own copy.
  # health_notes are the contraindications a coach has to know before an EMS
  # or reformer session (pacemaker, pregnancy, a back injury);
  # waiver_signed_on is when the member signed the studio's health
  # declaration. Both are wiped with the rest on Client#anonymise!.
  PROFILE_FIELDS = %w[
    date_of_birth gender address emergency_contact_name emergency_contact_phone health_notes waiver_signed_on
  ].freeze

  scope :active, -> { where(active: true) }

  # The membership a scanned or typed card belongs to, in this gym only.
  # Whatever a scanner adds around the number (spaces, a prefix) is dropped.
  def self.find_by_card(code)
    digits = code.to_s.gsub(/\D/, "")
    return nil unless digits.match?(CARD_CODE_FORMAT)

    find_by(card_code: digits)
  end

  # A number no other member of this gym holds.
  def self.free_card_code(company_id)
    loop do
      code = SecureRandom.random_number(10**CARD_CODE_DIGITS).to_s.rjust(CARD_CODE_DIGITS, "0")
      return code unless where(company_id: company_id, card_code: code).exists?
    end
  end

  private

  def assign_card_code
    self.card_code ||= self.class.free_card_code(company_id) if company_id
  end
end
