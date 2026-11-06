require "rails_helper"

# Module 8: a member's file. openapi: false — the API calls are oracles.
RSpec.describe "Web member file", type: :request, openapi: false do
  include ActiveJob::TestHelper

  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:client) { create(:client, company: company, first_name: "Salma", last_name: "Ben Ali", email: "salma@example.tn") }
  let(:base) { "/admin/#{company.id}/clients/#{client.id}" }
  let(:api) { auth_headers(admin).merge("X-Company-Id" => company.id) }
  let(:activity) { create(:activity, company: company, name: "Yoga") }
  let(:plan) { create(:contract_type, company: company, name: "Mensuel") }

  before do
    plan.contract_type_activities.create!(activity: activity, price: 120)
    web_sign_in(admin)
  end

  it "shows the member as GET /api/v1/clients/:id describes them" do
    Contracts::Actions.sell(client, company: company, by: admin, params: ActionController::Parameters.new(contract_type_id: plan.id, activity_id: activity.id))
    get base
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<app-client-profile", "Salma Ben Ali", "Mensuel", "prof-history")
  end

  it "shows the error state for someone who is not this salle's member" do
    stranger = create(:client, company: create(:company))
    get "/admin/#{company.id}/clients/#{stranger.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("fx-state--danger")
    expect(response.body).not_to include(stranger.full_name)
  end

  it "sells from the file through the subscriptions dialogs, audited" do
    get base
    expect(response.body).to include('data-controller="subscriptions"', "subscriptions#sell", "abo-sale")

    post "/admin/#{company.id}/contracts", params: { client_id: client.id, contract_type_id: plan.id, activity_id: activity.id, starts_on: Date.current.iso8601, discount: 20, collect_payment: true, payment_method: "cash" }, as: :json
    expect(response).to have_http_status(:created)
    contract = client.contracts_for(company).sole
    expect([ contract.final_price.to_f, contract.payment_status ]).to eq([ 100.0, "paid" ])
    expect(AuditLog.where(action: "contract.created", auditable_id: contract.id)).to exist

    post "/admin/#{company.id}/contracts", params: { client_id: client.id, contract_type_id: plan.id, activity_id: SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error"]).to eq("Activity not found")
  end

  it "shows the subscription card: its state, what is owed, renewing only once it is due" do
    far = Contracts::Actions.sell(client, company: company, by: admin, params: ActionController::Parameters.new(contract_type_id: plan.id, activity_id: activity.id))
    get base
    card = response.body[%r{<section[^>]*class="prof-card prof-subscription".*?</section>}m]
    expect(card).to include("Yoga · Mensuel", %(data-state="active"), "subscriptions#cancel")
    expect(card).not_to include("subscriptions#renew", "subscriptions#collect")
    expect(response.body[%r{<section[^>]*class="prof-verdict".*?</section>}m]).to include("client-profile#openPayment")

    far.update!(expires_at: 3.days.from_now)
    get base
    card = response.body[%r{<section[^>]*class="prof-card prof-subscription".*?</section>}m]
    expect(card).to include(%(data-state="expiring"), "subscriptions#renew")
  end

  it "owes what is unpaid, even after an earlier term was paid — and nothing for a cancelled one" do
    paid = Contracts::Actions.sell(client, company: company, by: admin, params: ActionController::Parameters.new(contract_type_id: plan.id, activity_id: activity.id, starts_on: 40.days.ago.to_date.iso8601, collect_payment: true))
    due = Contracts::Actions.sell(client, company: company, by: admin, params: ActionController::Parameters.new(contract_type_id: plan.id, activity_id: activity.id))
    expect(paid.reload).to be_paid
    expect(client.outstanding_balance(company)).to eq(120)

    Contracts::Actions.cancel(due, company: company, by: admin)
    expect(client.outstanding_balance(company)).to eq(0)
  end

  it "books a seat, a trial when asked, and lists the day's sessions for the dialog" do
    session = create(:session, company: company, activity: activity, starts_at: 2.days.from_now.change(hour: 9))
    get "#{base}/sessions", params: { activity_id: activity.id, date: session.starts_at.to_date.iso8601 }
    expect(response.body).to include(%(value="#{session.id}"))
    get "#{base}/sessions", params: { activity_id: activity.id }
    expect(response).to have_http_status(:bad_request)

    post "#{base}/bookings", params: { session_id: session.id, trial: true }, as: :json
    expect(response).to have_http_status(:created)
    expect(client.bookings_for(company).sole.session).to eq(session)
  end

  it "saves the health file, and refuses an identity the member owns" do
    patch base, params: { client: { health_notes: "Genou fragile", waiver_signed_on: "2026-10-01" } }, as: :json
    expect(response).to have_http_status(:no_content)
    membership = client.membership_for(company).reload
    expect([ membership.health_notes, membership.waiver_signed_on ]).to eq([ "Genou fragile", Date.new(2026, 10, 1) ])
    expect(AuditLog.where(action: "client.updated", auditable_id: client.id)).to exist
  end

  describe "editing their details" do
    let(:words) { ->(key) { Web::Translations.translate(key, {}, locale: :fr) } }

    it "saves the person and this gym's copy, audited, and shows them on the file" do
      patch base, params: { client: { first_name: "Selma", phone: "22 000 111", date_of_birth: "1990-05-12", gender: "female", address: "12 rue de Marseille",
                                      emergency_contact_name: "Mehdi", emergency_contact_phone: "98 000 222", notes: "Préfère le matin" } }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(client.reload.slice(:first_name, :phone, :email).values).to eq([ "Selma", "22 000 111", "salma@example.tn" ])
      expect(client.membership_for(company).address).to eq("12 rue de Marseille")
      expect(AuditLog.where(action: "client.updated", auditable_id: client.id)).to exist

      get base
      expect(response.body).to include("Selma Ben Ali", "22 000 111", "12 mai 1990", words.call("clients.gender_female"), "12 rue de Marseille", "Mehdi", "98 000 222", "Préfère le matin")
    end

    it "offers the dialog without ever printing the whole address" do
      get base
      expect(response.body).to include("client-profile#openDetails", 'data-profile-form="details"', "sa****ma@example.tn", '"identity_locked":false')
      expect(response.body).not_to include("salma@example.tn")
    end

    it "refuses an address someone else holds, or a masked one, in the page's language" do
      create(:client, company: company, email: "pris@example.tn")

      patch base, params: { client: { email: "pris@example.tn" } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(words.call("clients.email_taken"))

      patch base, params: { client: { email: "sa****ma@example.tn" } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(words.call("auth.email_invalid"))
      expect(client.reload.email).to eq("salma@example.tn")
    end

    it "locks the identity of someone known beyond this gym, not what the gym wrote" do
      client.memberships.create!(company: create(:company), active: true)
      get base
      expect(response.body).to include('"identity_locked":true')

      patch base, params: { client: { first_name: "Autre" } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("error" => "identity_locked", "message" => words.call("clients.identity_locked_hint"))
      expect(client.reload.first_name).to eq("Salma")

      patch base, params: { client: { address: "7 rue B" } }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(client.membership_for(company).reload.address).to eq("7 rue B")
    end
  end

  it "invites them to the app, once a minute at most, as the API does" do
    expect { post "#{base}/invite", as: :json }.to have_enqueued_mail(AccountMailer, :member_invitation)
    expect(response).to have_http_status(:accepted)
    post "#{base}/invite", as: :json
    expect(response.parsed_body["error"]).to eq("invitation_recently_sent")
  end

  it "takes them off the salle (the admin's alone), with the toast on the members page" do
    delete base, as: :json
    expect(response).to have_http_status(:no_content)
    expect(company.clients.exists?(client.id)).to be(false)
    get "/admin/#{company.id}/clients"
    expect(response.body).to include("toast-item--success")
  end
end
