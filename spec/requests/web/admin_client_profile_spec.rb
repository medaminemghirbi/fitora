require "rails_helper"

# Module 8: a member's file. openapi: false — the API calls are oracles.
RSpec.describe "Web member file", type: :request, openapi: false do
  include ActiveJob::TestHelper

  let(:company) { create(:company, :pro, setup_dismissed_at: Time.current) }
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

  it "sells a subscription as POST /api/v1/contracts does, audited" do
    post "#{base}/contracts", params: { contract_type_id: plan.id, activity_id: activity.id, starts_on: Date.current.iso8601, discount: 20, collect_payment: true, payment_method: "cash" }, as: :json
    expect(response).to have_http_status(:created)
    contract = client.contracts_for(company).sole
    expect([ contract.final_price.to_f, contract.payment_status ]).to eq([ 100.0, "paid" ])
    expect(AuditLog.where(action: "contract.created", auditable_id: contract.id)).to exist

    post "#{base}/contracts", params: { contract_type_id: plan.id, activity_id: SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error"]).to eq("Activity not found")
  end

  it "books a seat, a trial when asked, and lists the day's sessions for the dialog" do
    session = create(:session, company: company, activity: activity, starts_at: 2.days.from_now.change(hour: 9))
    get "#{base}/sessions", params: { activity_id: activity.id, date: session.starts_at.to_date.iso8601 }
    expect(response.body).to include(%(value="#{session.id}"))

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
