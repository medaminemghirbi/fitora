require "rails_helper"

# The door: a card scanned, a verdict, a visit. openapi: false — no API here.
RSpec.describe "Web entries (the door)", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:base) { "/admin/#{company.id}/entries" }
  let(:client) { create(:client, company: company, first_name: "Salma", last_name: "Ben Ali", phone: "20 338 183") }
  let(:membership) { client.membership_for(company) }
  let(:plan) { create(:contract_type, company: company, name: "Mensuel") }

  before { web_sign_in(admin) }

  it "shows the scan and the day, and is in the shell's menu" do
    get base
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="entries"', "ent-scan", "ent-stats", %(href="#{base}"))
  end

  it "goes straight to the verdict for a scanned card, green for a paid subscription" do
    create(:contract, client: client, contract_type: plan, payment_status: :paid)
    get "#{base}/lookup", params: { q: " #{membership.card_code}\n" }

    expect(response.body).to include("ent-verdict is-green", "Salma Ben Ali", "Mensuel", "entries#admit")
  end

  it "lists who a typed name matches, and says when a number is nobody's card" do
    client
    get "#{base}/lookup", params: { q: "salma" }
    expect(response.body).to include("ent-match", %(data-client-id="#{client.id}"))

    get "#{base}/lookup", params: { q: "12345678" }
    expect(response.body).to include("ent-idle is-empty", "12345678")
  end

  it "never finds another gym's member" do
    stranger = create(:client, company: create(:company))
    get "#{base}/lookup", params: { q: stranger.membership_for(stranger.companies.first).card_code }
    expect(response.body).not_to include(stranger.full_name)

    get "#{base}/check/#{stranger.id}"
    expect(response).to have_http_status(:not_found)
    post base, params: { client_id: stranger.id }, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "shows red with the reason and a WhatsApp reminder, refuses — and lets in when forced" do
    create(:contract, client: client, contract_type: plan, starts_at: 40.days.ago, expires_at: 3.days.ago, payment_status: :paid)
    get "#{base}/check/#{client.id}"
    expect(response.body).to include("ent-verdict is-red", "https://wa.me/21620338183?text=", "entries#admit", 'data-force="true"')

    post base, params: { client_id: client.id }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq(Web::Translations.translate("entries.errors.expired", {}, locale: :fr))

    post base, params: { client_id: client.id, force: true }, as: :json
    expect(response).to have_http_status(:created)
    expect(Visit.sole).to have_attributes(forced: true, reason: "expired", checked_in_by: admin)

    get base, params: { fragment: "day" }
    expect(response.body).to include("ent-row is-forced", "Salma Ben Ali")
  end

  it "undoes a visit made by mistake, but not an old one" do
    create(:contract, client: client, contract_type: plan, payment_status: :paid)
    post base, params: { client_id: client.id }, as: :json
    visit = Visit.sole

    delete "#{base}/#{visit.id}", as: :json
    expect(response).to have_http_status(:no_content)
    expect(Visit.count).to eq(0)

    old = Visit.create!(company: company, client: client, checked_in_at: 2.hours.ago)
    delete "#{base}/#{old.id}", as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows an earlier day's visits, without the scan" do
    Visit.create!(company: company, client: client, checked_in_at: 2.days.ago.change(hour: 9))
    get base, params: { date: 2.days.ago.to_date.iso8601 }

    expect(response.body).to include("Salma Ben Ali")
    expect(response.body).not_to include("ent-scan")
  end

  it "opens with the member asked for (from their file)" do
    get base, params: { member: client.id }
    expect(response.body).to include(%(data-entries-member-value="#{client.id}"))
  end

  describe "a login without check-in" do
    let(:staff) { create(:staff_member, company: company, role: :moderator) }

    before do
      staff.assigned_role.update!(permissions: staff.assigned_role.permissions - %w[checkin])
      delete "/deconnexion"
      web_sign_in(staff.user)
    end

    it "is refused the page and every action" do
      get base
      expect(response).to have_http_status(:redirect)
      post base, params: { client_id: client.id }, as: :json
      expect(response).to have_http_status(:forbidden)
      get "#{base}/lookup", params: { q: "salma" }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
