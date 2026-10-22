require "rails_helper"

RSpec.describe "Api::V1::Admin::Dashboard", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:company) { create(:company, admin: admin) }

  describe "GET /api/v1/admin/dashboard" do
    it "returns the company and its stats for the admin" do
      get "/api/v1/admin/dashboard", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["company"]["id"]).to eq(company.id)
      expect(body["stats"]).to include("total_clients", "active_contracts", "todays_bookings", "outstanding_payments")
    end

    it "scopes stats to the current company only" do
      create(:client, company: company)
      other_company = create(:company)
      create(:client, company: other_company)

      get "/api/v1/admin/dashboard", headers: auth_headers(admin)

      expect(response.parsed_body["stats"]["total_clients"]).to eq(1)
    end

    it "lets a moderator (reports capability) view the dashboard" do
      moderator = create(:staff_member, company: company, role: :moderator)

      get "/api/v1/admin/dashboard", headers: auth_headers(moderator.user)

      expect(response).to have_http_status(:ok)
    end

    # The image every contract is signed with is the admin's (Settings →
    # Image de marque), and its link opens it to whoever holds it. The
    # dashboard never needs it, and staff with `reports` read the dashboard.
    it "never hands out the contract signature's link" do
      company.signature.attach(io: Rails.root.join("spec/fixtures/files/sample.png").open, filename: "signature.png", content_type: "image/png")
      moderator = create(:staff_member, company: company, role: :moderator)

      [ admin, moderator.user ].each do |user|
        get "/api/v1/admin/dashboard", headers: auth_headers(user)
        expect(response.parsed_body["company"]).not_to have_key("signature_url")
      end
    end

    it "forbids a coach (no reports capability) from viewing the dashboard" do
      coach_staff = create(:staff_member, company: company, role: :coach)

      get "/api/v1/admin/dashboard", headers: auth_headers(coach_staff.user)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
