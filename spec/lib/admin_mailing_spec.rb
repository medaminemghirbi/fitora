require "rails_helper"

# The console's mailing: the variables each admin gets, who can receive one, and
# one job per recipient, whose mail is theirs alone.
RSpec.describe AdminMailing do
  let(:superadmin) { create(:user, :superadmin) }
  let(:admin) { create(:user, :admin, first_name: "Meriem", last_name: "Ben Ammar", email: "meriem@lumen.tn") }
  let!(:company) { create(:company, admin: admin, name: "Studio Lumen", city: "La Marsa") }
  let(:content) { { subject: "Bonjour {{prenom}}", body: "Votre salle {{salle}} à {{ville}}." } }

  describe ".values_for" do
    it "fills every variable the composer offers" do
      expect(described_class.values_for(admin).keys).to match_array(described_class::VARIABLES)
    end

    it "names every salle the admin runs, oldest first, and leaves out a blank city" do
      create(:company, admin: admin, name: "Lumen Lac", city: "")

      values = described_class.values_for(admin.reload)

      expect(values).to include("prenom" => "Meriem", "nom" => "Ben Ammar", "salle" => "Studio Lumen, Lumen Lac", "ville" => "La Marsa", "email" => "meriem@lumen.tn")
      expect(values["lien_connexion"]).to end_with("/connexion")
    end
  end

  describe ".fill" do
    it "replaces what it knows, with or without spaces" do
      expect(described_class.fill("{{prenom}} et {{ prenom }}", { "prenom" => "Sami" })).to eq("Sami et Sami")
    end

    it "does not read a value as a pattern, nor fill it again" do
      expect(described_class.fill("{{prenom}}", { "prenom" => "\\0 {{nom}}", "nom" => "X" })).to eq("\\0 {{nom}}")
    end
  end

  describe ".start" do
    it "keeps its own copy of the text, one recipient per account, and one job each" do
      other = create(:company, name: "Zen Club").admin

      mailing = nil
      expect { mailing = described_class.start(content, [ admin.id, other.id ], by: superadmin) }
        .to have_enqueued_job(DeliverMailingJob).exactly(2).times

      expect(mailing).to be_persisted
      expect(mailing).to have_attributes(subject: "Bonjour {{prenom}}", sent_by: superadmin)
      expect(mailing.recipients.map(&:email)).to contain_exactly("meriem@lumen.tn", other.email)
      expect(mailing.recipients.map(&:status).uniq).to eq([ "pending" ])
    end

    it "sends to active admins only, whatever ids the form sent" do
      staff = create(:staff_member, company: company, role: :moderator).user
      gone = create(:user, :admin, active: false)

      mailing = described_class.start(content, [ admin.id, staff.id, superadmin.id, gone.id, "not-a-uuid", "" ], by: superadmin)

      expect(mailing.recipients.map(&:user)).to eq([ admin ])
    end

    it "counts an account ticked twice once" do
      expect(described_class.start(content, [ admin.id, admin.id ], by: superadmin).recipients.size).to eq(1)
    end

    it "sends a suspended account's admin what they are sent" do
      SuperadminActions.suspend_access(company, by: superadmin)

      expect(described_class.start(content, [ admin.id ], by: superadmin)).to be_persisted
    end

    it "sends nothing without a recipient, a subject, a text or with a variable nobody can fill" do
      [
        [ content, [] ],
        [ content.merge(subject: " "), [ admin.id ] ],
        [ content.merge(body: ""), [ admin.id ] ],
        [ content.merge(body: "Bonjour {{prénom}}"), [ admin.id ] ],
        [ content.merge(subject: "{{mot_de_passe}}"), [ admin.id ] ]
      ].each do |attributes, ids|
        expect { expect(described_class.start(attributes, ids, by: superadmin)).not_to be_persisted }
          .not_to have_enqueued_job(DeliverMailingJob)
      end
      expect(Mailing.count).to eq(0)
    end
  end

  it "goes with the account: its recipients leave, what was sent stays" do
    mailing = described_class.start(content, [ admin.id, create(:company).admin.id ], by: superadmin)
    company.destroy!

    admin.reload.destroy!

    expect(mailing.recipients.reload.size).to eq(1)
  end

  it "survives the superadmin who sent it" do
    mailing = described_class.start(content, [ admin.id ], by: superadmin)

    superadmin.destroy!

    expect(mailing.reload.sent_by).to be_nil
  end
end

RSpec.describe DeliverMailingJob do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin, first_name: "Meriem", email: "meriem@lumen.tn") }
  let!(:company) { create(:company, admin: admin, name: "Studio <Lumen>") }
  let(:mailing) { create(:mailing, subject: "Bonjour\n{{prenom}}", body: "Salle : {{salle}}\n\nVoir http://fitora.test/page?a=1&b=2. <b>gras</b>") }
  let(:recipient) { create(:mailing_recipient, mailing: mailing, user: admin) }
  let(:delivered) { ActionMailer::Base.deliveries.last }

  it "sends the admin their own version, and says it left" do
    freeze_time do
      described_class.perform_now(recipient.id)

      expect(recipient.reload).to have_attributes(status: "sent", sent_at: Time.current, failure: nil)
    end
    expect(delivered.to).to eq([ "meriem@lumen.tn" ])
    expect(delivered.subject).to eq("Bonjour Meriem")
    expect(delivered.text_part.decoded).to include("Salle : Studio <Lumen>")
  end

  it "escapes what it was given and links only web addresses, in the HTML" do
    described_class.perform_now(recipient.id)

    html = delivered.html_part.decoded
    expect(html).to include("Studio &lt;Lumen&gt;", "&lt;b&gt;gras&lt;/b&gt;", %(<a href="http://fitora.test/page?a=1&amp;b=2" ))
    expect(html).not_to include("<b>gras</b>", "<Lumen>")
  end

  it "answers to Fitora rather than to a mailbox nobody reads" do
    PlatformSetting.current.update!(email: "bonjour@fitora.tn")

    described_class.perform_now(recipient.id)

    expect(delivered.reply_to).to eq([ "bonjour@fitora.tn" ])
  end

  it "sends once, however many times it runs" do
    2.times { described_class.perform_now(recipient.id) }

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "has nothing to do for a recipient who has gone" do
    expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
  end

  it "tries a failing mail server again, then marks the recipient failed by the kind of error only" do
    allow(AccountMailer).to receive(:admin_message).and_raise(Net::SMTPFatalError.new("550 refused for meriem@lumen.tn"))
    allow(Rails.error).to receive(:report)

    expect { described_class.perform_now(recipient.id) }.to have_enqueued_job(described_class)
    expect(recipient.reload).to be_pending

    perform_enqueued_jobs { described_class.perform_later(recipient.id) }

    expect(AccountMailer).to have_received(:admin_message).exactly(4).times
    expect(recipient.reload).to have_attributes(status: "failed", failure: "Net::SMTPFatalError", sent_at: nil)
    expect(Rails.error).to have_received(:report)
  end
end
