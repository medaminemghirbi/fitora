require "rails_helper"

# The first sign-in of an account a superadmin opened: the address confirmed,
# the generated password replaced, the terms accepted, and only then the app.
RSpec.describe "Web first sign-in", type: :request, openapi: false do
  let(:admin) { create(:user, :admin, :first_sign_in, password: "generated-pass") }
  let!(:company) { create(:company, admin: admin, setup_dismissed_at: Time.current) }
  let(:fields) { { password: "my-own-password", password_confirmation: "my-own-password", accept_terms: "1" } }

  before { web_sign_in(admin, password: "generated-pass") }

  it "sends the admin to the form on sign-in, and keeps them there whatever they open" do
    expect(response).to redirect_to("/premiere-connexion")

    %W[/admin/#{company.id}/dashboard /admin/#{company.id}/clients /admin/#{company.id}/settings/company].each do |path|
      get path
      expect(response).to redirect_to("/premiere-connexion"), path
    end

    get "/premiere-connexion"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="password"', 'name="accept_terms"', 'href="/cgu"')
  end

  it "takes the new password and the terms, stays signed in, and opens the app" do
    freeze_time do
      patch "/premiere-connexion", params: fields
      expect(response).to redirect_to("/admin/#{company.id}/dashboard")

      admin.reload
      expect(admin).not_to be_must_change_password
      expect(admin.terms_accepted_at).to eq(Time.current)
      expect(admin.authenticate("my-own-password")).to eq(admin)
      expect(admin.authenticate("generated-pass")).to be(false)
    end

    get "/admin/#{company.id}/dashboard"
    expect(response).to have_http_status(:ok)
    get "/premiere-connexion"
    expect(response).to redirect_to("/admin/#{company.id}/dashboard")
  end

  it "refuses a short password, two that differ, and the generated one kept" do
    [
      { password: "short", password_confirmation: "short" },
      { password: "my-own-password", password_confirmation: "another-one" },
      { password: "generated-pass", password_confirmation: "generated-pass" }
    ].each do |attempt|
      patch "/premiere-connexion", params: attempt.merge(accept_terms: "1")
      expect(response).to have_http_status(:unprocessable_content), attempt.to_s
      expect(response.body).to include("alert-danger")
      expect(admin.reload).to be_must_change_password
    end
  end

  it "refuses without the terms, and says why" do
    patch "/premiere-connexion", params: fields.except(:accept_terms)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("first-terms-error")
    expect(admin.reload.terms_accepted_at).to be_nil
    expect(admin).to be_must_change_password
  end

  it "asks only for the terms once the password has been chosen elsewhere" do
    admin.update!(password: "chosen-in-a-reset")
    web_sign_in(admin, password: "chosen-in-a-reset")
    expect(response).to redirect_to("/premiere-connexion")

    get "/premiere-connexion"
    expect(response.body).to include('name="accept_terms"')
    expect(response.body).not_to include('name="password"')

    patch "/premiere-connexion", params: { accept_terms: "1" }
    expect(response).to redirect_to("/admin/#{company.id}/dashboard")
    expect(admin.reload.authenticate("chosen-in-a-reset")).to eq(admin)
  end

  it "comes after the address: unconfirmed, the inbox screen first" do
    admin.update!(email_verified_at: nil)
    delete "/deconnexion"
    web_sign_in(admin, password: "generated-pass")
    expect(response).to redirect_to("/confirmation-email")

    get "/premiere-connexion"
    expect(response).to redirect_to("/confirmation-email")

    admin.verify_email!
    get "/confirmation-email/status"
    expect(response.parsed_body["continue_url"]).to eq("/premiere-connexion")
  end

  it "is nobody else's: not signed in, an admin who has finished, a superadmin helping" do
    delete "/deconnexion"
    get "/premiere-connexion"
    expect(response).to redirect_to("/connexion")
    patch "/premiere-connexion", params: fields
    expect(response).to redirect_to("/connexion")
    expect(admin.reload).to be_must_change_password

    web_sign_in(create(:user, :superadmin, password: "password123"))
    post "/superadmin/companies/#{company.id}/impersonate", as: :json
    get "/admin/#{company.id}/dashboard"
    expect(response).to have_http_status(:ok)
    patch "/premiere-connexion", params: fields
    expect(response).to redirect_to("/admin/#{company.id}/dashboard")
    expect(admin.reload).to be_must_change_password
  end

  it "leaves an API token refused until it is done, with the way through in its words" do
    get "/api/v1/company", headers: auth_headers(admin)
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["error"]).to eq("first_sign_in_required")

    get "/api/v1/bootstrap", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
  end

  it "does not stop staff, whose logins are the admin's to hand out" do
    staff = create(:staff_member, company: company, role: :moderator).user
    staff.update!(terms_accepted_at: nil)

    expect(staff).not_to be_first_sign_in_pending
  end

  it "takes a password reset as a password chosen" do
    raw = admin.generate_password_reset_token!

    AccountRecovery.reset_password(raw, "chosen-in-a-reset")

    expect(admin.reload).not_to be_must_change_password
    expect(admin.terms_accepted_at).to be_nil
    expect(admin).to be_first_sign_in_pending
  end
end
