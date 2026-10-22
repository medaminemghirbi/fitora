require "rails_helper"

RSpec.describe "Api::V1 GET /api/v1/me/permissions", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:company) { create(:company, admin: admin) }

  it "gives the admin every permission" do
    get "/api/v1/me/permissions", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["role"]["key"]).to eq("admin")
    expect(body["permissions"]).to match_array(Permission::ALL)
  end

  # A member's login has no staff role to resolve: refused, not a 500.
  it "refuses a member's login" do
    member = create(:client, company: company)

    get "/api/v1/me/permissions", headers: auth_headers(member)

    expect(response).to have_http_status(:forbidden)
  end

  it "returns a staff login's resolved role permissions" do
    staff = create(:staff_member, company: company, role: :moderator)

    get "/api/v1/me/permissions", headers: auth_headers(staff.user)

    body = response.parsed_body
    expect(body["role"]["key"]).to eq("moderator")
    expect(body["permissions"]).to include("bookings", "payments", "sessions")
    expect(body["permissions"]).not_to include("contract_types")
  end

  it "reflects a re-permissioned built-in role" do
    staff = create(:staff_member, company: company, role: :coach)
    company.roles.find_by(key: "coach").update!(permissions: %w[checkin bookings clients])

    get "/api/v1/me/permissions", headers: auth_headers(staff.user)

    expect(response.parsed_body["permissions"]).to match_array(%w[clients bookings checkin])
  end

  it "gives a platform superadmin no company permissions" do
    superadmin = create(:user, :superadmin)

    get "/api/v1/me/permissions", headers: auth_headers(superadmin)

    expect(response.parsed_body).to eq("role" => nil, "permissions" => [])
  end

  it "401s without a token" do
    get "/api/v1/me/permissions"
    expect(response).to have_http_status(:unauthorized)
  end
end
