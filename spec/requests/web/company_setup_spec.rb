require "rails_helper"

# Module 4: opening the first salle (/admin/setup-company). openapi: false —
# POST /api/v1/companies is the oracle.
RSpec.describe "Web company setup", type: :request, openapi: false do
  let(:admin) { create(:user, :admin) }
  let!(:yoga) { create(:activity_template, names: { "fr" => "Yoga", "en" => "Yoga", "ar" => "يوغا" }) }

  it "shows the page to an admin with a confirmed address and no salle" do
    web_sign_in(admin)
    get "/admin/setup-company"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<app-company-setup", "Yoga")
  end

  it "sends everyone else home, as the Angular guards do" do
    get "/admin/setup-company"
    expect(response).to redirect_to("/connexion")

    staffed = create(:company)
    web_sign_in(staffed.admin)
    get "/admin/setup-company"
    expect(response).to redirect_to(%r{/admin/#{staffed.id}/})

    unverified = create(:user, :admin, :unverified)
    delete "/deconnexion"
    web_sign_in(unverified)
    get "/admin/setup-company"
    expect(response).to redirect_to("/confirmation-email")
  end

  it "opens the salle as POST /api/v1/companies does, then points at the guide" do
    attributes = { name: "Salle Web", city: "Sousse", country: "TN", timezone: "Africa/Tunis", currency: "TND" }
    web_sign_in(admin)
    post "/admin/setup-company", params: { company: attributes, activity_template_ids: [ yoga.id ], custom_activities: [ { name: "Cardio danse", emoji: "💃" } ] }, as: :json
    expect(response).to have_http_status(:created)
    company = admin.reload.companies.sole
    expect(response.parsed_body).to eq("next" => "/admin/#{company.id}/getting-started")

    twin = create(:user, :admin)
    post "/api/v1/companies", params: { company: attributes, activity_template_ids: [ yoga.id ], custom_activities: [ { name: "Cardio danse", emoji: "💃" } ] }, headers: auth_headers(twin), as: :json
    other = twin.reload.companies.sole

    shape = ->(c) { [ c.attributes.slice("name", "city", "country", "timezone", "currency"), c.activities.order(:name).pluck(:name, :emoji), c.roles.order(:key).pluck(:key), c.admin.subscription&.plan, c.admin.active_company_id == c.id ] }
    expect(shape.call(company)).to eq(shape.call(other))
  end

  it "answers the API's refusals: a second salle on Starter, an unknown activity" do
    create(:company, admin: admin)
    web_sign_in(admin)
    post "/admin/setup-company", params: { company: { name: "Deux", timezone: "Africa/Tunis", currency: "TND" } }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["error"]).to eq("multi_salle_not_included")

    lonely = create(:user, :admin)
    delete "/deconnexion"
    web_sign_in(lonely)
    post "/admin/setup-company", params: { company: { name: "Trois", timezone: "Africa/Tunis", currency: "TND" }, activity_template_ids: [ SecureRandom.uuid ] }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("Unknown activity in the catalogue.")
    expect(lonely.reload.companies).to be_empty
  end
end
