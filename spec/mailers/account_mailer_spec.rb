require "rails_helper"

# What every e-mail carries, whichever one it is.
RSpec.describe AccountMailer do
  let(:admin) { create(:user, :admin, first_name: "Meriem") }
  let(:mail) { described_class.password_reset(admin, "a-token").message }

  describe "the logo at its foot" do
    it "travels in the mail as a PNG, so a client blocking remote images still shows it" do
      logo = mail.attachments["fitora.png"]

      expect(logo).to be_inline
      expect(logo.mime_type).to eq("image/png")
      expect(logo.decoded.bytes.first(4)).to eq([ 0x89, 0x50, 0x4E, 0x47 ])
      expect(mail.mime_type).to eq("multipart/related")
    end

    it "is drawn by the HTML, after the message, and named for whoever cannot see it" do
      html = mail.html_part.decoded

      expect(html).to include(%(src="#{mail.attachments["fitora.png"].url}"), 'alt="Fitora"')
      expect(html.index("cid:")).to be > html.index("Réinitialisez")
    end

    it "leaves the text version as it was" do
      expect(mail.text_part.decoded).to include("a-token")
      expect(mail.text_part.decoded).not_to include("cid:")
    end

    it "is on every account e-mail" do
      client = create(:client, company: create(:company), email: "m@example.test")

      [
        described_class.email_verification(admin, "t"),
        described_class.account_credentials(admin, create(:company, admin: admin), "generated", "t"),
        described_class.member_invitation(client, admin.companies.first, "t")
      ].each do |delivery|
        expect(delivery.message.attachments["fitora.png"]).to be_inline
      end
    end
  end
end
