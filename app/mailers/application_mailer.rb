class ApplicationMailer < ActionMailer::Base
  # Was the Rails placeholder ("from@example.com") — never actually
  # configured, because AccountMailer is the first mailer in this app that
  # sends anything for real.
  default from: ENV.fetch("MAIL_FROM", "Fitora <no-reply@fitora.io>")
  layout "mailer"

  # The logo at the foot of every e-mail (layouts/mailer). It travels in the mail
  # rather than being loaded from the site, so a client blocking remote images
  # still shows it; a PNG, because few clients draw an SVG.
  LOGO = Rails.root.join("public/apple-touch-icon.png").binread.freeze

  before_action { attachments.inline["fitora.png"] = { mime_type: "image/png", content: LOGO } }
end
