module Web
  # ConfirmEmailComponent's mailboxFor: the webmail behind an address, when it
  # is one of the big ones — a button straight to the inbox beats "go and find
  # your mail".
  module Mailbox
    BOXES = [
      [ /\A(gmail|googlemail)\.com\z/, "Gmail", "https://mail.google.com/mail/u/0/#search/from%3Afitora.io" ],
      [ /\A(outlook|hotmail|live|msn)\.[a-z.]+\z/, "Outlook", "https://outlook.live.com/mail/0/" ],
      [ /\A(yahoo|ymail)\.[a-z.]+\z/, "Yahoo Mail", "https://mail.yahoo.com/" ],
      [ /\A(icloud|me|mac)\.com\z/, "iCloud Mail", "https://www.icloud.com/mail" ],
      [ /\A(proton\.me|protonmail\.com|pm\.me)\z/, "Proton Mail", "https://mail.proton.me/" ]
    ].freeze

    # { name:, url: } or nil.
    def self.for(email)
      domain = email.to_s.split("@", 2)[1].to_s.downcase
      match = BOXES.find { |pattern, _, _| pattern.match?(domain) }
      match && { name: match[1], url: match[2] }
    end
  end
end
