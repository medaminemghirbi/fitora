require "rails_helper"

RSpec.describe "Api::V1::Branding", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:company) { create(:company, admin: admin, name: "Power Gym", primary_color: "#ff5500") }

  describe "GET /api/v1/branding" do
    it "returns the company's name, primary color, and logo for the admin" do
      get "/api/v1/branding", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body["branding"]
      expect(body["name"]).to eq("Power Gym")
      expect(body["primary_color"]).to eq("#ff5500")
    end

    it "is readable by any staff role, including a coach with no other capabilities" do
      coach_staff = create(:staff_member, company: company, role: :coach)

      get "/api/v1/branding", headers: auth_headers(coach_staff.user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["branding"]["name"]).to eq("Power Gym")
    end

    it "never leaks another company's branding" do
      other_company = create(:company, name: "Titan Fitness")
      other_staff = create(:staff_member, company: other_company, role: :moderator)

      get "/api/v1/branding", headers: auth_headers(other_staff.user)

      expect(response.parsed_body["branding"]["name"]).to eq("Titan Fitness")
      expect(response.parsed_body["branding"]["name"]).not_to eq("Power Gym")
    end

    it "requires authentication" do
      get "/api/v1/branding"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
