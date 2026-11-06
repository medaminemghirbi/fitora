require "rails_helper"

RSpec.describe "Api::V1 GET /api/v1/bootstrap", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:company) { create(:company, admin: admin) }

  it "hydrates the admin shell in one call" do
    get "/api/v1/bootstrap", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["user"]["id"]).to eq(admin.id)
    expect(body["company"]["id"]).to eq(company.id)
    expect(body["branding"]["name"]).to eq(company.name)
    expect(body["role"]["key"]).to eq("admin")
    expect(body["permissions"]).to match_array(Permission::ALL)
    expect(body["roles"].map { |r| r["key"] }).to match_array(Role::SYSTEM_KEYS)
    expect(body["roles"].first).to include("id", "permissions", "builtin")
    expect(body["permission_catalog"]).to include("contract_types")
    expect(body["onboarding"]).to include(
      "step" => "company", "complete" => false, "dismissed" => false
    )
    expect(body["notifications"]).to eq("unread_count" => 0)
  end

  it "omits the onboarding flow for staff" do
    staff = create(:staff_member, company: company, role: :moderator)

    get "/api/v1/bootstrap", headers: auth_headers(staff.user)

    expect(response.parsed_body["onboarding"]).to be_nil
  end

  it "hides the full company profile from staff but still returns branding" do
    staff = create(:staff_member, company: company, role: :moderator)

    get "/api/v1/bootstrap", headers: auth_headers(staff.user)

    body = response.parsed_body
    expect(body["company"]).to be_nil
    expect(body["branding"]["name"]).to eq(company.name)
    # every member's shell reads the tenant language + currency from branding
    expect(body["branding"]).to include("locale" => company.locale, "currency" => "TND", "currency_symbol" => "DT")
    expect(body["permissions"]).to include("bookings")
  end

  it "gives the admin every feature and every permission — nothing is gated" do
    get "/api/v1/bootstrap", headers: auth_headers(admin)

    body = response.parsed_body
    expect(body["permissions"]).to include(
      "clients", "payments", "sessions", "contracts", "bookings", "coaches"
    )
  end
end
