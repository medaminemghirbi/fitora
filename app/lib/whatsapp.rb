# A wa.me link: WhatsApp opens (the app, or WhatsApp Web) on a chat with the
# member, the message already typed and waiting to be sent. Nothing goes
# through Fitora — no API, no account, no cost — so the desk can remind a
# member from its own phone the way it already does by hand.
module Whatsapp
  # The gyms' countries and their neighbours. A number written with its
  # country code (+33…, 0033…) works from anywhere; one written the local
  # way is read as the gym's country's.
  DIAL_CODES = {
    "TN" => "216", "DZ" => "213", "MA" => "212", "LY" => "218", "EG" => "20", "MR" => "222",
    "FR" => "33", "BE" => "32", "CH" => "41", "LU" => "352", "IT" => "39", "DE" => "49", "ES" => "34", "GB" => "44",
    "CA" => "1", "US" => "1", "SA" => "966", "AE" => "971", "QA" => "974", "KW" => "965",
    "SN" => "221", "CI" => "225", "CM" => "237"
  }.freeze

  # The number in international form, digits only — or nil when there is
  # nothing to call.
  def self.number(phone, country: "TN")
    raw = phone.to_s.strip
    digits = raw.gsub(/\D/, "")
    return nil if digits.length < 6

    return digits if raw.start_with?("+")
    return digits.delete_prefix("00") if digits.start_with?("00")

    code = DIAL_CODES[country.to_s.upcase]
    return digits if code.nil? || (digits.start_with?(code) && digits.length > 10)

    # The trunk 0 (06 12 34 56 78 in France) is not dialled from abroad.
    "#{code}#{digits.delete_prefix('0')}"
  end

  def self.link(phone, text, country: "TN")
    number = number(phone, country: country)
    return nil if number.nil?

    "https://wa.me/#{number}?text=#{ERB::Util.url_encode(text.to_s)}"
  end
end
