require "rails_helper"

# Module 6: settings. openapi: false — the API calls are oracles.
RSpec.describe "Web settings", type: :request, openapi: false do
  let(:company) { create(:company, :pro, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:base) { "/admin/#{company.id}/settings" }
  let(:api) { auth_headers(admin).merge("X-Company-Id" => company.id) }

  before { web_sign_in(admin) }

  describe "the shell" do
    it "opens on the first section, and on it for an unknown one" do
      get base
      expect(response).to redirect_to("#{base}/company")
      get "#{base}/nowhere"
      expect(response).to redirect_to("#{base}/company")
      get "/admin/#{company.id}/data-exchange"
      expect(response).to redirect_to("#{base}/data-exchange")
    end

    it "renders every section" do
      %w[company branding contracts planning booking roles data-exchange mobile-app appearance account].each do |section|
        get "#{base}/#{section}"
        expect(response).to have_http_status(:ok), section
        expect(response.body).to include("<app-settings-shell", "settings-tab")
      end
    end

    it "locks the Pro tools below paid Pro" do
      admin.subscription.update!(plan: :starter)
      %w[branding roles data-exchange mobile-app].each do |section|
        get "#{base}/#{section}"
        expect(response.body).to include("pro-lock"), section
      end
    end

    it "lets a login that manages the catalogue in, to its own two sections only" do
      staff = create(:staff_member, company: company, role: :moderator)
      staff.assigned_role.update!(permissions: %w[contract_types])
      delete "/deconnexion"
      web_sign_in(staff.user)
      get "#{base}/company"
      expect(response).to redirect_to("#{base}/appearance")

      staff.assigned_role.update!(permissions: %w[clients])
      get "#{base}/appearance"
      expect(response).to be_redirect
      expect(response.location).not_to include("/settings")
    end
  end

  describe "saving the salle, as PATCH /api/v1/company" do
    it "saves the profile, the hours and the booking rules alike" do
      patch "#{base}/company", params: { company: { name: "Lumen Marsa", city: "La Marsa", country: "TN", business_hours_start: "07:00", working_days: [ 1, 2, 3 ], settings: { booking: { cancellation_hours: 6 }, features: { waitlist: true } } } }, as: :json
      expect(response).to have_http_status(:ok)
      company.reload
      expect([ company.name, company.city, company.business_hours_start, company.working_days, company.settings.booking[:cancellation_hours], company.feature?(:waitlist) ])
        .to eq([ "Lumen Marsa", "La Marsa", "07:00", [ 1, 2, 3 ], 6, true ])
      expect(response.parsed_body.dig("company", "settings", "booking", "cancellation_hours")).to eq(6)
    end

    it "drops the branding below Pro, as the API does" do
      admin.subscription.update!(plan: :starter)
      patch "#{base}/company", params: { company: { primary_color: "#ff0000", signatory_name: "Meriem" } }, as: :json
      expect(company.reload.brand_color).to be_nil
      expect(company.signatory_name).to eq("Meriem")
    end

    it "takes a signature file and removes it on request" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/files/sample.png"), "image/png")
      patch "#{base}/company", params: { company: { signature: file } }
      expect(company.reload.signature).to be_attached
      patch "#{base}/company", params: { company: { remove_signature: "true" } }
      expect(company.reload.signature).not_to be_attached
    end

    it "refuses a staff login, and answers the API's validation message" do
      patch "#{base}/company", params: { company: { name: "" } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Name can't be blank")
    end
  end

  describe "my account" do
    it "changes the password, keeping this session and ending the others" do
      patch "#{base}/password", params: { current_password: "wrong", password: "new-password-1" }, as: :json
      expect(response.parsed_body["error"]).to eq("current_password_invalid")

      patch "#{base}/password", params: { current_password: "password123", password: "new-password-1" }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(admin.reload.authenticate("new-password-1")).to be_truthy
      get "#{base}/account"
      expect(response).to have_http_status(:ok)
    end

    it "signs out everywhere, this session too" do
      post "#{base}/sign-out-everywhere", as: :json
      expect(response.parsed_body).to eq("next" => "/connexion")
      get "#{base}/account"
      expect(response).to redirect_to("/connexion")
    end
  end

  describe "roles, as /api/v1/roles" do
    it "creates, renames, re-permissions and deletes a custom role" do
      post "#{base}/roles", params: { role: { name: "Comptable", permissions: [] } }, as: :json
      expect(response).to have_http_status(:created)
      role = company.roles.find_by!(name: "Comptable")
      patch "#{base}/roles/#{role.id}", params: { role: { permissions: %w[payments revenue] } }, as: :json
      expect(role.reload.permissions).to eq(%w[payments revenue])
      delete "#{base}/roles/#{role.id}", as: :json
      expect(Role.exists?(role.id)).to be(false)
    end

    it "keeps the admin role and the built-ins as the API does" do
      admin_role = company.roles.find_by!(key: "admin")
      patch "#{base}/roles/#{admin_role.id}", params: { role: { permissions: [] } }, as: :json
      expect(response.parsed_body["error"]).to eq("The Admin role cannot be edited.")
      delete "#{base}/roles/#{company.roles.find_by!(key: "moderator").id}", as: :json
      expect(response.parsed_body["error"]).to eq("A built-in role cannot be deleted.")
    end

    it "is Pro's" do
      admin.subscription.update!(plan: :starter)
      post "#{base}/roles", params: { role: { name: "X" } }, as: :json
      expect(response.parsed_body["error"]).to eq("pro_required")
    end

    it "answers the matrix alone for load()" do
      get "#{base}/roles", params: { fragment: 1 }
      expect(response.body).to include("rm-table")
      expect(response.body).not_to include("settings-tab")
    end
  end

  # The writes the API keeps for the admin (require_admin! on /company,
  # /roles and /mobile_app). A staff login is refused whatever its role
  # grants, and nothing changes: one that could edit roles could grant itself
  # every permission.
  describe "what only the admin may change" do
    { "no permission" => [], "every permission" => Permission::ALL }.each do |label, permissions|
      it "is refused to a staff login with #{label}" do
        own_role = create(:role, company: company, permissions: permissions)
        staff = create(:staff_member, company: company, assigned_role: own_role)
        other_role = create(:role, company: company, name: "Comptable")
        code = company.reload.app_code
        delete "/deconnexion"
        web_sign_in(staff.user)

        patch "#{base}/company", params: { company: { name: "Renamed" } }, as: :json
        expect(response).to have_http_status(:forbidden)
        post "#{base}/roles", params: { role: { name: "Escalate", permissions: Permission::ALL } }, as: :json
        expect(response).to have_http_status(:forbidden)
        patch "#{base}/roles/#{own_role.id}", params: { role: { permissions: Permission::ALL } }, as: :json
        expect(response).to have_http_status(:forbidden)
        delete "#{base}/roles/#{other_role.id}", as: :json
        expect(response).to have_http_status(:forbidden)
        post "#{base}/mobile-app/regenerate", params: { audience: "member" }, as: :json
        expect(response).to have_http_status(:forbidden)

        expect(company.reload.name).not_to eq("Renamed")
        expect(company.app_code).to eq(code)
        expect(company.roles.where(name: "Escalate")).to be_empty
        expect(own_role.reload.permissions).to eq(permissions)
        expect(Role.exists?(other_role.id)).to be(true)
      end
    end
  end

  describe "the mobile app's keys, as /api/v1/mobile_app" do
    it "shows the keys and replaces one, audited" do
      get "#{base}/mobile-app"
      before = company.reload.app_code
      expect(response.body).to include(before.upcase, "<svg")
      post "#{base}/mobile-app/regenerate", params: { audience: "member" }, as: :json
      expect(response.parsed_body["member_code"]).not_to eq(before)
      expect(AuditLog.where(action: "mobile_app.key_regenerated")).to exist
    end
  end

  describe "import / export, as /api/v1/data_exchange" do
    it "names the files as the page does and follows an import to its end" do
      get "#{base}/data-exchange/clients/template"
      expect(response.headers["Content-Disposition"]).to include("fitora-clients-modele.csv")
      get "#{base}/data-exchange/clients/export"
      expect(response.headers["Content-Disposition"]).to include("fitora-clients-export.csv")

      csv = Rack::Test::UploadedFile.new(StringIO.new("name,emoji\nZumba,💃\n"), "text/csv", original_filename: "a.csv")
      post "#{base}/data-exchange/activities/import", params: { file: csv }
      expect(response).to have_http_status(:accepted)
      id = response.parsed_body["id"]
      get "#{base}/data-exchange/imports/#{id}", as: :json
      expect(response.parsed_body).to include("id" => id, "entity" => "activities")
    end

    it "keeps the export for the admin" do
      staff = create(:staff_member, company: company, role: :moderator)
      staff.assigned_role.update!(permissions: %w[clients])
      delete "/deconnexion"
      web_sign_in(staff.user)
      get "#{base}/data-exchange/clients/export"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
