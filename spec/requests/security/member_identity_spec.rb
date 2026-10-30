require "rails_helper"

# A Client is one person across every gym that knows their email. These are
# the ways a second gym used to reach through that shared row into the first
# gym's member — type the email, read the name and phone gym A recorded or
# what it wrote, set a password, log in as them. Now typing the email only
# asks the person (MembershipRequest); every example is a refusal, before
# they accept and after.
RSpec.describe "A member shared between gyms", type: :request do
  include ActiveJob::TestHelper

  let(:gym_a) { create(:company) }
  let(:gym_b) { create(:company) }
  let!(:member) do
    create(:client, company: gym_a, email: "member@example.com", first_name: "Salma", last_name: "Ben Ali",
                    phone: "+216 20 111 111", password: "original-pass")
  end

  before do
    member.membership_for(gym_a).update!(date_of_birth: Date.new(1990, 1, 1), address: "12 Rue A",
                                         emergency_contact_name: "Mother", emergency_contact_phone: "+216 20 222 222")
  end

  def ask!(email: "member@example.com")
    post "/api/v1/clients",
         params: { client: { first_name: "Other", last_name: "Name", phone: "+216 99 999 999", email: email, notes: "Met at the door" } },
         headers: auth_headers(gym_b.admin)
  end

  # The person following the emailed link and saying yes.
  def accept!
    token = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{/adhesion\?token=([\w-]+)}, 1]
    patch "/adhesion", params: { token: token }
    expect(response).to have_http_status(:ok)
  end

  def adopt!
    perform_enqueued_jobs { ask! }
    accept!
    member.id
  end

  describe "before the person has answered" do
    it "shows the second gym only what it sent itself" do
      ask!

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body.keys).to eq([ "membership_request" ])
      expect(body["membership_request"]).to include("first_name" => "Other", "last_name" => "Name", "phone" => "+216 99 999 999")
      expect(body.to_json).not_to include("Salma", "Ben Ali", "+216 20 111 111", member.id)
    end

    it "adds no one: no membership, nothing in its list or export, no file to open" do
      create(:subscription, :pro, company: gym_b)
      ask!

      expect(member.memberships.pluck(:company_id)).to eq([ gym_a.id ])
      get "/api/v1/clients", headers: auth_headers(gym_b.admin)
      expect(response.parsed_body["clients"]).to be_empty
      get "/api/v1/clients/#{member.id}", headers: auth_headers(gym_b.admin)
      expect(response).to have_http_status(:not_found)
      get "/api/v1/data_exchange/clients/export", headers: auth_headers(gym_b.admin)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Salma", "member@example.com")
    end

    it "sells nothing either, whatever the wizard sent" do
      plan = create(:contract_type, company: gym_b)
      activity = create(:activity, company: gym_b)

      expect {
        post "/api/v1/clients",
             params: { client: { first_name: "Other", last_name: "Name", phone: "1", email: "member@example.com" },
                       subscription: { contract_type_id: plan.id, activity_id: activity.id, collect_payment: true, payment_method: "cash" } },
             headers: auth_headers(gym_b.admin)
      }.not_to change(Contract, :count)
      expect(response).to have_http_status(:accepted)
    end

    it "emails the person, at the address the gym typed, and changes nothing about them" do
      perform_enqueued_jobs { ask! }

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ "member@example.com" ])
      expect(mail.subject).to include(gym_b.name)
      expect(member.reload.first_name).to eq("Salma")
      expect(member.phone).to eq("+216 20 111 111")
    end

    it "asks once per gym, and sends the link again at most once a day" do
      perform_enqueued_jobs { ask! }
      expect { perform_enqueued_jobs { ask! } }.not_to change(ActionMailer::Base.deliveries, :count)
      expect(MembershipRequest.where(company: gym_b, client: member).count).to eq(1)

      travel MembershipRequest::RESEND_AFTER + 1.minute do
        expect { perform_enqueued_jobs { ask! } }.to change(ActionMailer::Base.deliveries, :count).by(1)
      end
    end

    it "lets a gym send only so many a day" do
      stub_const("MembershipRequest::DAILY_LIMIT", 1)
      other = create(:client, company: gym_a, email: "other@example.com")
      ask!
      ask!(email: other.email)

      expect(response).to have_http_status(:unprocessable_content)
      expect(other.membership_requests).to be_empty
    end

    it "asks a person who left every gym but kept their own login, too" do
      member.membership_for(gym_a).destroy!
      ask!

      expect(response).to have_http_status(:accepted)
      expect(member.reload.memberships).to be_empty
    end

    it "harvests nothing through a CSV import: the row is refused, nobody is mailed" do
      create(:subscription, :pro, company: gym_b)
      csv = Rack::Test::UploadedFile.new(StringIO.new("first_name,last_name,email,phone\nX,Y,member@example.com,1\nNew,Person,new@example.com,2\n"),
                                         "text/csv", original_filename: "members.csv")
      perform_enqueued_jobs do
        post "/api/v1/data_exchange/clients/import", params: { file: csv }, headers: auth_headers(gym_b.admin)
      end

      expect(gym_b.clients.map(&:email)).to eq([ "new@example.com" ])
      expect(MembershipRequest.count).to eq(0)
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).not_to include("member@example.com")
      expect(gym_b.data_imports.last.row_errors).to eq([ { "row" => 2, "message" => DataExchange::Clients::ALREADY_ON_FITORA } ])
    end
  end

  describe "the link" do
    it "asks the question on opening and answers it only from the button" do
      perform_enqueued_jobs { ask! }
      token = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{/adhesion\?token=([\w-]+)}, 1]

      get "/adhesion", params: { token: token }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(gym_b.name)
      expect(member.reload.memberships.count).to eq(1)

      patch "/adhesion", params: { token: token }
      expect(member.membership_for(gym_b)).to be_present
      expect(member.membership_for(gym_b).notes).to eq("Met at the door")
      expect(AuditLog.where(company: gym_b, action: "client.joined", auditable_id: member.id)).to exist
    end

    it "is spent once used, and dead past its week" do
      perform_enqueued_jobs { ask! }
      token = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{/adhesion\?token=([\w-]+)}, 1]
      patch "/adhesion", params: { token: token }

      patch "/adhesion", params: { token: token }
      expect(response).to have_http_status(:not_found)

      other = create(:client, company: gym_a, email: "late@example.com")
      perform_enqueued_jobs { ask!(email: other.email) }
      late = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{/adhesion\?token=([\w-]+)}, 1]
      travel MembershipRequest::EXPIRY + 1.minute do
        patch "/adhesion", params: { token: late }
      end
      expect(response).to have_http_status(:not_found)
      expect(other.reload.membership_for(gym_b)).to be_nil
    end

    it "shows nothing for a made-up token" do
      get "/adhesion", params: { token: "x" * 43 }

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(gym_b.name)
    end
  end

  describe "once the person has accepted" do
    it "is the existing person, whose identity stays as it was" do
      id = adopt!

      expect(id).to eq(member.id)
      expect(member.reload.first_name).to eq("Salma")
      expect(member.phone).to eq("+216 20 111 111")
    end

    it "shows the second gym none of what the first gym wrote" do
      id = adopt!
      get "/api/v1/clients/#{id}", headers: auth_headers(gym_b.admin)

      client = response.parsed_body["client"]
      expect(client.values_at("date_of_birth", "address", "emergency_contact_name", "emergency_contact_phone")).to all(be_nil)
    end

    it "keeps each gym's copy apart when the second gym writes its own" do
      id = adopt!
      patch "/api/v1/clients/#{id}", params: { client: { address: "7 Rue B" } }, headers: auth_headers(gym_b.admin)

      expect(response).to have_http_status(:ok)
      expect(member.membership_for(gym_a).reload.address).to eq("12 Rue A")
      expect(member.membership_for(gym_b).reload.address).to eq("7 Rue B")
    end

    it "never takes a password from staff" do
      id = adopt!
      patch "/api/v1/clients/#{id}", params: { client: { password: "attacker-pass" } }, headers: auth_headers(gym_b.admin)

      expect(member.reload.authenticate("attacker-pass")).to be(false)
      expect(member.authenticate("original-pass")).to be_truthy
    end

    it "refuses to change the email, name or phone of someone who is not only this gym's" do
      id = adopt!
      patch "/api/v1/clients/#{id}", params: { client: { email: "attacker@example.com", first_name: "Changed" } },
                                     headers: auth_headers(gym_b.admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("identity_locked")
      expect(member.reload.email).to eq("member@example.com")
      expect(member.first_name).to eq("Salma")
    end

    it "fills in, from what the gym typed, only what the person had left blank" do
      member.update_columns(phone: nil) # rubocop:disable Rails/SkipsModelValidations
      adopt!

      expect(member.reload.phone).to eq("+216 99 999 999")
      expect(member.first_name).to eq("Salma")
    end

    it "lets the gym add them again as its own member, selling a plan this time" do
      adopt!
      plan = create(:contract_type, company: gym_b)
      activity = create(:activity, company: gym_b)
      create(:contract_type_activity, contract_type: plan, activity: activity, price: 120)

      post "/api/v1/clients",
           params: { client: { first_name: "Salma", last_name: "Ben Ali", phone: "1", email: "member@example.com" },
                     subscription: { contract_type_id: plan.id, activity_id: activity.id } },
           headers: auth_headers(gym_b.admin)

      expect(response).to have_http_status(:created)
      expect(member.contracts_for(gym_b).count).to eq(1)
    end
  end

  it "does not let the first gym change it either once the person signs in themselves" do
    patch "/api/v1/clients/#{member.id}", params: { client: { email: "new@example.com" } }, headers: auth_headers(gym_a.admin)

    expect(response).to have_http_status(:unprocessable_content)
    expect(member.reload.email).to eq("member@example.com")
  end

  it "leaves a person only this gym knows fully editable" do
    walk_in = create(:client, company: gym_a, first_name: "Typo")
    patch "/api/v1/clients/#{walk_in.id}", params: { client: { first_name: "Fixed", email: "walkin@example.com" } },
                                           headers: auth_headers(gym_a.admin)

    expect(response).to have_http_status(:ok)
    expect(walk_in.reload.first_name).to eq("Fixed")
    expect(walk_in.email).to eq("walkin@example.com")
  end

  it "forgets the requests when the person is erased" do
    ask!
    member.anonymise!

    expect(MembershipRequest.count).to eq(0)
  end
end
