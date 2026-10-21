require "rails_helper"

# Module 4: the onboarding flow. openapi: false — the API calls are oracles.
RSpec.describe "Web onboarding", type: :request, openapi: false do
  let(:company) { create(:company) }
  let(:admin) { company.admin }
  let(:base) { "/admin/#{company.id}/onboarding" }

  before { web_sign_in(admin) }

  it "opens on the company step, with the values to check" do
    get base
    expect(response.body).to include("<app-onboarding", "ob-facts", company.name, "onboarding#confirmCompany")
  end

  it "moves on as GET /api/v1/onboarding says, and shows the step's own tool (B-07)" do
    post "#{base}/complete", params: { step: "company" }, as: :json
    expect(response).to have_http_status(:no_content)
    get "/api/v1/onboarding", headers: auth_headers(admin).merge("X-Company-Id" => company.id)
    expect(response.parsed_body.dig("onboarding", "step")).to eq("activities")

    get base
    expect(response.body).to include("obs-current", "<app-activities", 'data-catalogue-embedded-value="true"')

    create(:activity, company: company)
    get base
    expect(response.body).to include("<app-plans")
  end

  it "skips what may be skipped, refusing the rest with the API's message" do
    post "#{base}/skip", params: { step: "staff" }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(company.reload.settings.onboarding[:skipped]).to eq([ "staff" ])

    post "#{base}/skip", params: { step: "company" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("This step cannot be skipped")
  end

  it "leaves the flow" do
    post "#{base}/dismiss", as: :json
    expect(company.reload.setup_dismissed_at).to be_present
  end

  it "is the admin's alone" do
    staff = create(:staff_member, company: company).user
    delete "/deconnexion"
    web_sign_in(staff)
    get base
    expect(response).to be_redirect
    post "#{base}/dismiss", as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "keeps the old /getting-started link" do
    get "/admin/#{company.id}/getting-started"
    expect(response).to redirect_to(base)
  end

  it "embeds the rooms tool for a gym with rooms, reloading only itself" do
    company.update!(settings: { features: { spaces: true }, onboarding: { completed: [ "company" ], skipped: [] } })
    create(:activity, company: company)
    get base
    expect(response.body).to include("<app-spaces", "data-spaces-page-fragment-value")

    get "/admin/#{company.id}/spaces", params: { fragment: 1 }
    expect(response.body).to start_with(%(<div _ngcontent-spaces="" class="fx-stack"))
  end
end
