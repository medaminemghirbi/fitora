require "rails_helper"

# Impersonation is the one way a Fitora superadmin reaches a gym's data, and it is
# deliberately indistinguishable from the admin's own session — that is what
# makes it useful for support. The accountability has to come from somewhere
# else: every audited action taken during such a session names the superadmin who
# was really at the keyboard. It starts from the console (/superadmin), behind
# its two-factor sign-in; the API has no way in.
RSpec.describe "Security: impersonation", type: :request do
  let(:superadmin) { create(:user, :superadmin) }
  let(:admin) { create(:user, :admin) }
  let!(:company) { create(:company, admin: admin, setup_dismissed_at: Time.current) }

  def hire(email)
    role = company.roles.find_by!(key: "moderator")
    post "/admin/#{company.id}/team/staff",
         params: { staff_member: { first_name: "Hire", last_name: "During", email: email, password: "password123", role_id: role.id } },
         as: :json
  end

  def impersonate!
    web_sign_in(superadmin)
    post "/superadmin/companies/#{company.id}/impersonate", as: :json
    expect(response).to have_http_status(:ok)
  end

  it "records who started it" do
    impersonate!

    log = company.audit_logs.find_by(action: "superadmin.impersonation_started")
    expect(log.metadata["superadmin_id"]).to eq(superadmin.id)
  end

  it "names the superadmin on an action taken during the session, not just at the start" do
    impersonate!
    hire("hire@fitora.test")

    expect(response).to have_http_status(:created)
    log = company.audit_logs.where.not(action: "superadmin.impersonation_started").last
    expect(log.metadata["impersonated_by_id"]).to eq(superadmin.id)
    expect(log.metadata["impersonated_by_email"]).to eq(superadmin.email)
  end

  it "leaves an ordinary admin action unstamped" do
    web_sign_in(admin)
    hire("hire2@fitora.test")

    expect(response).to have_http_status(:created)
    log = company.audit_logs.last
    expect(log.metadata).not_to have_key("impersonated_by_id")
  end

  it "cannot be started by anyone but a platform superadmin" do
    web_sign_in(admin)
    post "/superadmin/companies/#{company.id}/impersonate", as: :json

    expect(company.audit_logs.where(action: "superadmin.impersonation_started")).to be_empty
    get "/admin/#{company.id}/dashboard"
    expect(response.body).not_to include("impersonation-banner")
  end

  it "has no API door, even for a superadmin's own token", openapi: false do
    post "/api/v1/superadmin/companies/#{company.id}/impersonate", headers: auth_headers(superadmin)

    expect(response).to have_http_status(:not_found)
    expect(company.audit_logs.where(action: "superadmin.impersonation_started")).to be_empty
  end
end
