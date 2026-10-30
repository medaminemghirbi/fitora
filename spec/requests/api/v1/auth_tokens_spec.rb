require "rails_helper"

# A token can be ended now, not only waited out (TokenVersioned).
RSpec.describe "Ending sessions", type: :request do
  let(:admin) { create(:user, :admin, password: "old-password-1") }
  let!(:company) { create(:company, admin: admin) }

  def bearer(token) = { "Authorization" => "Bearer #{token}" }

  it "ends every existing session when the password changes" do
    old = JwtService.for_user(admin)
    admin.update!(password: "new-password-1")

    get "/api/v1/auth/me", headers: bearer(old)
    expect(response).to have_http_status(:unauthorized)
  end

  it "ends them when the account is deactivated and reactivated" do
    old = JwtService.for_user(admin)
    admin.update!(active: false)
    admin.update!(active: true)

    get "/api/v1/auth/me", headers: bearer(old)
    expect(response).to have_http_status(:unauthorized)
  end

  it "still accepts a token issued before versions were checked, until the version moves" do
    legacy = JWT.encode({ user_id: admin.id, exp: 1.day.from_now.to_i }, JwtService.secret, "HS256")

    get "/api/v1/auth/me", headers: bearer(legacy)
    expect(response).to have_http_status(:ok)
  end

  it "signs out of every device on request" do
    token = JwtService.for_user(admin)
    post "/api/v1/auth/logout", params: { all_devices: true }, headers: bearer(token)

    get "/api/v1/auth/me", headers: bearer(token)
    expect(response).to have_http_status(:unauthorized)
  end

  it "ends this token on a plain logout, a copy of it included, and leaves other devices alone" do
    token = JwtService.for_user(admin)
    other_device = JwtService.for_user(admin)
    post "/api/v1/auth/logout", headers: bearer(token)

    get "/api/v1/auth/me", headers: bearer(token)
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/auth/me", headers: bearer(other_device)
    expect(response).to have_http_status(:ok)
  end

  it "keeps the logout only until the token would have expired anyway" do
    token = JwtService.for_user(admin)
    post "/api/v1/auth/logout", headers: bearer(token)

    ttl = Sidekiq.redis { |redis| redis.call("TTL", RevokedSessions.key(JwtService.decode(token)[:jti])) }
    expect(ttl).to be_within(5).of(JwtService::EXPIRATION.to_i)
  end

  it "keeps accepting tokens while the list of signed-out ones cannot be read" do
    token = JwtService.for_user(admin)
    allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError)

    get "/api/v1/auth/me", headers: bearer(token)
    expect(response).to have_http_status(:ok)
  end

  it "does the same for a member" do
    member = create(:client, company: company, password: "member-pass-1")
    old = JwtService.for_client(member)
    member.update!(password: "member-pass-2")

    get "/api/v1/auth/me", headers: bearer(old)
    expect(response).to have_http_status(:unauthorized)
  end

  describe "PATCH /api/v1/auth/password" do
    it "changes it, ends the other sessions, and keeps this one signed in" do
      other_device = JwtService.for_user(admin)
      patch "/api/v1/auth/password", params: { current_password: "old-password-1", password: "new-password-1" },
                                     headers: bearer(JwtService.for_user(admin))

      expect(response).to have_http_status(:ok)
      get "/api/v1/auth/me", headers: bearer(response.parsed_body["token"])
      expect(response).to have_http_status(:ok)
      get "/api/v1/auth/me", headers: bearer(other_device)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses without the current password" do
      patch "/api/v1/auth/password", params: { current_password: "wrong", password: "new-password-1" },
                                     headers: bearer(JwtService.for_user(admin))

      expect(response.parsed_body["error"]).to eq("current_password_invalid")
      expect(admin.reload.authenticate("old-password-1")).to be_truthy
    end

    it "is refused to a superadmin impersonating the account" do
      superadmin = create(:user, :superadmin)
      patch "/api/v1/auth/password", params: { current_password: "old-password-1", password: "new-password-1" },
                                     headers: bearer(JwtService.for_user(admin, impersonator: superadmin))

      expect(response).to have_http_status(:forbidden)
    end

    it "works for a member too" do
      member = create(:client, company: company, password: "member-pass-1")
      patch "/api/v1/auth/password", params: { current_password: "member-pass-1", password: "member-pass-2" },
                                     headers: bearer(JwtService.for_client(member))

      expect(response).to have_http_status(:ok)
      expect(member.reload.authenticate("member-pass-2")).to be_truthy
    end
  end

  describe "impersonation" do
    let(:superadmin) { create(:user, :superadmin) }

    it "lasts an hour, not a week" do
      token = JwtService.for_user(admin, impersonator: superadmin)

      travel 61.minutes do
        get "/api/v1/auth/me", headers: bearer(token)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "ends when the impersonator is no longer a superadmin" do
      token = JwtService.for_user(admin, impersonator: superadmin)
      superadmin.update!(role: :admin)

      get "/api/v1/auth/me", headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
