require "rails_helper"

# Module 5: "Mes salles". openapi: false — the API calls are oracles.
RSpec.describe "Web salles", type: :request, openapi: false do
  let(:company) { create(:company, :pro, setup_dismissed_at: Time.current, city: "La Marsa") }
  let(:admin) { company.admin }
  let!(:second) { create(:company, admin: admin, name: "Annexe", setup_dismissed_at: Time.current) }
  let(:base) { "/admin/#{company.id}/salles" }

  before { web_sign_in(admin) }

  it "shows every salle, the one in the URL marked as here, as the network API lists them" do
    get base
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<app-salles", "La Marsa", "Annexe")
    expect(response.body.scan(/data-salle-id="([0-9a-f-]{36})"/).flatten).to eq([ company.id, second.id ])
    expect(response.body).to match(/sl-card is-active" data-salle-id="#{company.id}"/)

    get "/admin/#{second.id}/salles"
    expect(response.body).to match(/sl-card is-active" data-salle-id="#{second.id}"/)
  end

  it "is locked below paid Pro, without the network" do
    admin.subscription.update!(plan: :starter)
    get base
    expect(response.body).to include("pro-lock")
    expect(response.body).not_to include("sl-grid")
  end

  it "is the admin's page only, and shut while the account is locked" do
    admin.subscription.update!(active: false)
    get base
    expect(response).to redirect_to("/account-locked")
  end

  it "says when nobody can be posted yet" do
    get base
    expect(response.body).to include("Aucun modérateur pour l&#39;instant")
  end

  describe "posting moderators, as PUT /api/v1/companies/:id/moderators" do
    let!(:moderator) { create(:staff_member, company: company, role: :moderator) }

    it "posts them and answers with the redrawn network" do
      put "#{base}/#{second.id}/moderators", params: { user_ids: [ moderator.user_id ] }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("sl-grid", moderator.user.full_name)
      expect(second.staff_members.where(user: moderator.user)).to exist
    end

    it "refuses to leave someone working nowhere, with the API's message" do
      put "#{base}/#{company.id}/moderators", params: { user_ids: [] }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("works at no other salle")
    end

    it "is refused below paid Pro" do
      admin.subscription.update!(plan: :starter)
      put "#{base}/#{second.id}/moderators", params: { user_ids: [ moderator.user_id ] }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("pro_required")
    end
  end

  it "opens another salle as POST /api/v1/companies does, onto its guide" do
    post base, params: { company: { name: "Troisième", city: "Sousse", timezone: "Africa/Tunis", currency: "TND" } }, as: :json
    expect(response).to have_http_status(:created)
    created = admin.companies.find_by!(name: "Troisième")
    expect(response.parsed_body).to eq("next" => "/admin/#{created.id}/onboarding")
    expect(admin.reload.active_company_id).to eq(created.id)
    expect(created.roles.pluck(:key)).to include("moderator", "coach")
  end

  it "refuses another salle below paid Pro with the API's code" do
    admin.subscription.update!(plan: :starter)
    post base, params: { company: { name: "Non", timezone: "Africa/Tunis" } }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["error"]).to eq("multi_salle_not_included")
  end

  it "switches, answering where to go when asked for JSON" do
    post "/admin/#{company.id}/switch/#{second.id}", as: :json
    expect(response.parsed_body).to eq("next" => "/admin/#{second.id}/dashboard")
    expect(admin.reload.active_company_id).to eq(second.id)
  end
end
