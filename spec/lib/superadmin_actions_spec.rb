require "rails_helper"

# Opening a gym's account: the salle and its admin's login, both or neither, the
# credentials by e-mail, and sending them again while they are still the ones
# Fitora generated.
RSpec.describe SuperadminActions do
  let(:superadmin) { create(:user, :superadmin) }
  let(:company_attributes) { { name: "Studio Lumen", city: "La Marsa", timezone: "Africa/Tunis", currency: "TND", locale: "fr" } }
  let(:admin_attributes) { { first_name: "Meriem", last_name: "Trabelsi", email: "Meriem@Lumen.tn", phone: "+216 22 000 000" } }

  def open_account = described_class.create_company(company_attributes, admin_attributes, by: superadmin)

  describe ".create_company" do
    it "opens the salle and its admin, on the first sign-in still to make" do
      company = open_account.company
      admin = company.admin

      expect(company).to have_attributes(name: "Studio Lumen", city: "La Marsa")
      expect(company.roles.pluck(:key)).to include("admin", "moderator", "coach")
      expect(admin).to have_attributes(email: "meriem@lumen.tn", role: "admin", locale: "fr", active_company: company)
      expect(admin).to be_must_change_password
      expect(admin.terms_accepted_at).to be_nil
      expect(admin.email_verified?).to be(false)
      expect(admin.activation_state).to eq(:awaiting_email)
    end

    it "mails the login, a password that works, and the link, once and straight away" do
      expect { open_account }.to change(ActionMailer::Base.deliveries, :count).by(1)

      mail = ActionMailer::Base.deliveries.last
      body = mail.text_part.decoded
      expect(mail.to).to eq([ "meriem@lumen.tn" ])
      expect(mail.subject).to include("Studio Lumen")
      expect(mail.html_part.decoded).to include("meriem@lumen.tn", "Studio Lumen")

      password = body[/Mot de passe provisoire : (\S+)/, 1]
      admin = User.find_by!(email: "meriem@lumen.tn")
      expect(admin.authenticate(password)).to eq(admin)
      expect(admin.credentials_sent_at).to be_present

      token = body[/verify-email\?token=(\S+)/, 1]
      expect(User.find_by_email_verification_token(token)).to eq(admin)
    end

    it "never queues the mail: the password would wait in Redis" do
      expect { open_account }.not_to have_enqueued_mail(AccountMailer, :account_credentials)
    end

    it "leaves a trace in the journal, without the password" do
      company = open_account.company
      log = AuditLog.find_by!(action: "superadmin.company_created", company: company)

      expect(log.user).to eq(superadmin)
      expect(log.metadata).to eq("admin_email" => "meriem@lumen.tn")
    end

    it "opens neither when one of them is refused" do
      company_attributes[:currency] = "XXX"

      expect { open_account }.to raise_error(ActiveRecord::RecordInvalid)
      expect(User.find_by(email: "meriem@lumen.tn")).to be_nil
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "refuses an address that already has a login" do
      create(:user, :admin, email: "meriem@lumen.tn")

      expect { open_account }.to raise_error(ActiveRecord::RecordInvalid, /Email has already been taken/)
      expect(Company.find_by(name: "Studio Lumen")).to be_nil
    end

    it "keeps the account when the mail fails, and says so" do
      allow(AccountMailer).to receive(:account_credentials).and_raise(Net::OpenTimeout)
      allow(Rails.error).to receive(:report)

      opened = open_account

      expect(opened.credentials_sent).to be(false)
      expect(opened.company).to be_persisted
      expect(opened.company.admin.credentials_sent_at).to be_nil
      expect(Rails.error).to have_received(:report).with(an_instance_of(Net::OpenTimeout), hash_including(handled: true))
    end

    it "says so too when the server has no mail set up" do
      allow(ActionMailer::Base).to receive(:perform_deliveries).and_return(false)

      expect(open_account.credentials_sent).to be(false)
    end
  end

  describe ".send_credentials" do
    let(:company) { open_account.company }
    let(:admin) { company.admin }

    before { company && ActionMailer::Base.deliveries.clear }

    it "replaces the generated password, ending the sessions of whoever had the old one" do
      old_digest = admin.password_digest
      old_version = admin.token_version

      expect(described_class.send_credentials(company, by: superadmin)).to be(true)

      admin.reload
      expect(admin.password_digest).not_to eq(old_digest)
      expect(admin.token_version).to eq(old_version + 1)
      expect(admin).to be_must_change_password
      password = ActionMailer::Base.deliveries.last.text_part.decoded[/Mot de passe provisoire : (\S+)/, 1]
      expect(admin.authenticate(password)).to eq(admin)
      expect(AuditLog.where(action: "superadmin.credentials_sent", company: company)).to exist
    end

    it "leaves the link out once the address is confirmed" do
      admin.verify_email!

      described_class.send_credentials(company, by: superadmin)

      expect(ActionMailer::Base.deliveries.last.text_part.decoded).not_to include("verify-email")
    end

    it "never overwrites a password the admin chose" do
      admin.update!(password: "my-own-password")

      expect { described_class.send_credentials(company, by: superadmin) }.to raise_error(ApplicationRecord::Refused)
      expect(admin.reload.authenticate("my-own-password")).to eq(admin)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "suspending an account's access" do
    let(:company) { create(:company) }
    let(:admin) { company.admin }
    let(:staff) { create(:staff_member, company: company, role: :moderator).user }
    let(:elsewhere) { create(:staff_member, company: create(:company), role: :moderator).user }

    it "signs the admin and the whole team out, on every salle, and nobody else" do
      second = create(:company, admin: admin)
      posted = create(:staff_member, company: second, role: :moderator).user
      versions = -> { [ admin, staff, posted, elsewhere ].map { |user| user.reload.token_version } }
      before = versions.call

      described_class.suspend_access(company, by: superadmin)

      expect(versions.call).to eq([ before[0] + 1, before[1] + 1, before[2] + 1, before[3] ])
      expect([ admin, staff, posted ].map { |user| User.find(user.id).access_suspended? }).to all(be(true))
      expect(User.find(elsewhere.id)).not_to be_access_suspended
      expect(AuditLog.where(action: "superadmin.access_suspended", company: company, user: superadmin)).to exist
    end

    it "keeps the first date, and logs nothing, when done twice" do
      staff
      travel_to(2.days.ago) { described_class.suspend_access(company, by: superadmin) }
      first = admin.reload.access_suspended_at
      version = admin.token_version

      described_class.suspend_access(company, by: superadmin)

      expect(admin.reload.access_suspended_at).to eq(first)
      expect(admin.token_version).to eq(version)
      expect(AuditLog.where(action: "superadmin.access_suspended").count).to eq(1)
    end

    it "opens it again, and logs nothing when it was not closed" do
      described_class.restore_access(company, by: superadmin)
      expect(AuditLog.where(action: "superadmin.access_restored")).not_to exist

      described_class.suspend_access(company, by: superadmin)
      described_class.restore_access(company, by: superadmin)

      expect(admin.reload.access_suspended_at).to be_nil
      expect(User.find(admin.id)).not_to be_access_suspended
      expect(AuditLog.where(action: "superadmin.access_restored", company: company)).to exist
    end
  end

  it "records a change of language and currency" do
    company = create(:company)
    expect(described_class.update_settings(company, { currency: "EUR", locale: "en" }, by: superadmin)).to be(true)
    expect(company.reload).to have_attributes(currency: "EUR", locale: "en")
    expect(AuditLog.where(action: "superadmin.settings_updated")).to exist
  end
end
