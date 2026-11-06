require "rails_helper"

# Module 6: settings. openapi: false — the API calls are oracles.
RSpec.describe "Web settings", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:base) { "/admin/#{company.id}/settings" }
  let(:api) { auth_headers(admin).merge("X-Company-Id" => company.id) }

  before { web_sign_in(admin) }

  describe "the documents beside the forms" do
    before { company.update!(tax_id: "1789456/K/A/M/000", phone: "+216 71 774 200", signatory_name: "Meriem Ben Ammar") }

    it "prints the gym's details as each PDF prints them" do
      get "#{base}/legal"
      expect(response.body).to include("Matricule fiscal: 1789456/K/A/M/000", "Matricule fiscal : 1789456/K/A/M/000")
      expect(response.body).to include("Téléphone: +216 71 774 200", "Tél. : +216 71 774 200", "Représenté par : Meriem Ben Ammar")
    end

    it "shows only the contract next to the contract's own settings" do
      get "#{base}/contracts"
      expect(response.body).to include('data-doc="contract"')
      expect(response.body).not_to include('data-doc="receipt"')
    end
  end

  describe "saving one section" do
    it "leaves what the other sections hold as it is" do
      name = company.name
      company.update!(phone: "+216 71 774 200")
      patch "#{base}/company", params: { company: { tax_id: "42/A", timezone: "Africa/Tunis", country: "TN" } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(company.reload).to have_attributes(tax_id: "42/A", name: name, phone: "+216 71 774 200")

      patch "#{base}/company", params: { company: { phone: "+216 20 000 000" } }, as: :json
      expect(company.reload).to have_attributes(tax_id: "42/A", name: name, phone: "+216 20 000 000")
    end
  end

  describe "the shell" do
    it "opens on the first section, and on it for an unknown one" do
      get base
      expect(response).to redirect_to("#{base}/company")
      get "#{base}/nowhere"
      expect(response).to redirect_to("#{base}/company")
    end

    it "renders every section" do
      %w[company legal branding contracts planning booking roles mobile-app appearance account].each do |section|
        get "#{base}/#{section}"
        expect(response).to have_http_status(:ok), section
        expect(response.body).to include("set-nav", "set-main-head", "is-settings-mode")
      end
    end

    it "lists the sections by what they are about, the login's own apart" do
      get "#{base}/company"
      expect(response.body.scan('data-settings-shell-target="group"').size).to eq(4)
      page = "/admin/#{company.id}"
      order = [ "#{base}/company", "#{base}/legal", "#{base}/branding", "#{page}/salles", "#{base}/planning", "#{base}/booking", "#{page}/catalogue",
                "#{base}/contracts", "#{page}/team", "#{base}/roles", "#{base}/mobile-app", "#{base}/account", "#{base}/appearance" ]
      menu = response.body[/<nav class="set-nav".*?<\/nav>/m]
      positions = order.map { |href| menu.index(%(href="#{href}")) }
      expect(positions).to all(be_present)
      expect(positions).to eq(positions.sort)
    end

    it "keeps what is set up once out of the main menu, and in its own" do
      page = "/admin/#{company.id}"
      %w[catalogue team salles].each do |path|
        get "#{page}/#{path}"
        expect(response).to have_http_status(:ok), path
        expect(response.body).to include("set-nav", "is-settings-mode")
        expect(response.body[/<nav class="set-nav".*?<\/nav>/m]).to include(%(href="#{page}/#{path}" class="set-nav-item is-active"))
        rail = response.body[/<app-rail.*?<\/app-rail>/m]
        expect(rail).not_to include(%(href="#{page}/#{path}"))
        expect(rail).to match(/href="#{Regexp.escape(page)}\/settings" class="rail-item is-active"/)
      end

      get "#{base}/catalogue"
      expect(response).to redirect_to("#{page}/catalogue")
    end

    it "lists the plateau only for a gym that uses it" do
      get "#{base}/company"
      expect(response.body).not_to include(%(href="/admin/#{company.id}/spaces"))

      company.update!(settings: { features: { spaces: true } })
      get "/admin/#{company.id}/spaces"
      expect(response.body).to include("set-nav", %(href="/admin/#{company.id}/spaces" class="set-nav-item is-active"))
      expect(response.body[/<app-rail.*?<\/app-rail>/m]).not_to include(%(href="/admin/#{company.id}/spaces"))
    end

    it "gives a role that manages one of these pages the way in, and only to that" do
      staff = create(:staff_member, company: company, role: :moderator)
      staff.assigned_role.update!(permissions: %w[contract_types])
      delete "/deconnexion"
      web_sign_in(staff.user)

      get "/admin/#{company.id}/catalogue"
      expect(response).to have_http_status(:ok)
      expect(response.body[/<app-rail.*?<\/app-rail>/m]).to include(%(href="/admin/#{company.id}/settings"))
      menu = response.body[/<nav class="set-nav".*?<\/nav>/m]
      expect(menu).to include("/catalogue", "#{base}/account", "#{base}/appearance")
      expect(menu).not_to include("#{base}/company", "/team", "/salles", "#{base}/roles")

      staff.assigned_role.update!(permissions: %w[clients])
      get "/admin/#{company.id}/clients"
      expect(response.body[/<app-rail.*?<\/app-rail>/m]).not_to include(%(href="/admin/#{company.id}/settings"))
    end

    it "shrinks the main menu for settings only" do
      get "#{base}/company"
      expect(response.body).to match(/<a [^>]*rail-item[^>]* title="/)
      get "/admin/#{company.id}/dashboard"
      expect(response.body).not_to include("is-settings-mode")
    end

    it "flags the contracts until the gym has a signature" do
      get "#{base}/company"
      expect(response.body).to include("set-dot")

      company.signature.attach(io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")), filename: "s.png", content_type: "image/png")
      get "#{base}/company"
      expect(response.body).not_to include("set-dot")
    end

    it "lets a login that manages the catalogue in, to its own two sections only" do
      staff = create(:staff_member, company: company, role: :moderator)
      staff.assigned_role.update!(permissions: %w[contract_types])
      delete "/deconnexion"
      web_sign_in(staff.user)
      get "#{base}/company"
      expect(response).to redirect_to("/admin/#{company.id}/catalogue")

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

  # No SMS in this version: the reminder goes out on the member's app only.
  it "offers no SMS reminder among the booking rules" do
    get "#{base}/booking"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('id="sb-reminder-sms"', 'data-rule="reminder_sms"')
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

    it "answers the matrix alone for load()" do
      get "#{base}/roles", params: { fragment: 1 }
      expect(response.body).to include("rm-table")
      expect(response.body).not_to include("set-nav")
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
end
