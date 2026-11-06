require "rails_helper"

RSpec.describe "Api::V1::Auth", type: :request do
  describe "POST /api/v1/auth/login" do
    it "returns a token for valid credentials" do
      create(:user, email: "login@example.com", password: "password123")

      post "/api/v1/auth/login", params: { email: "login@example.com", password: "password123" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["token"]).to be_present
    end

    it "rejects invalid credentials" do
      create(:user, email: "login2@example.com", password: "password123")

      post "/api/v1/auth/login", params: { email: "login2@example.com", password: "wrong" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a client with no login configured, even with a correct-looking email" do
      create(:client, email: "no-login@example.com")

      post "/api/v1/auth/login", params: { email: "no-login@example.com", password: "whatever123" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/auth/login on a suspended account" do
    let(:company) { create(:company) }

    before { SuperadminActions.suspend_access(company, by: create(:user, :superadmin)) }

    it "refuses the right password, in its own words" do
      post "/api/v1/auth/login", params: { email: company.admin.email, password: "password123" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("access_suspended")
    end

    it "says nothing to the wrong one" do
      post "/api/v1/auth/login", params: { email: company.admin.email, password: "wrong-password" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/auth/me" do
    it "requires authentication" do
      get "/api/v1/auth/me"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current user when authenticated" do
      user = create(:user)

      get "/api/v1/auth/me", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["user"]["id"]).to eq(user.id)
    end
  end
end
