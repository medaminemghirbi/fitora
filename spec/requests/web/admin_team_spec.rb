require "rails_helper"

# Module 5: the team page. openapi: false — the API calls are oracles.
RSpec.describe "Web team", type: :request, openapi: false do
  include ActiveJob::TestHelper

  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:base) { "/admin/#{company.id}/team" }
  let(:api) { auth_headers(admin).merge("X-Company-Id" => company.id) }

  def card_keys(html = response.body)
    html.scan(/class="fx-person-card" data-key="([^"]+)"/).flatten.uniq
  end

  describe "the page" do
    let!(:coach_with_login) { create(:staff_member, company: company, role: :coach).coach }
    let!(:moderator) { create(:staff_member, company: company, role: :moderator) }

    before { web_sign_in(admin) }

    it "lists each coach once and each back-office login, in name order (B-08)" do
      get base
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<app-team")
      expect(card_keys).to contain_exactly("coach:#{coach_with_login.id}", "staff:#{moderator.id}")
      # The coach's own login is the coach's card, not a second one.
      expect(card_keys).not_to include("staff:#{coach_with_login.staff_member.id}")
    end

    it "shows what a role lets someone do, and the moderator's seat as taken" do
      get base
      expect(response.body).to include("Encaissement · Membres · Planning · Réservations · Pointage")
      expect(response.body).to include("team-seat-notice").or include("déjà attribué")
    end

    it "answers ?fragment=1 with the parts load() redraws" do
      get base, params: { fragment: 1 }
      expect(response.body).to include('data-team-part="cards"', 'data-team-part="members"', 'data-team-part="drawer"')
      expect(response.body).not_to include("<html")
    end

    it "opens the drawer on ?action=new, on the back-office form when asked" do
      get base, params: { action: "new", type: "backoffice" }
      expect(response.body).to include('data-team-page-open-value="backoffice"')
    end

    it "sends the old coach and staff lists to the team page, query kept" do
      get "/admin/#{company.id}/coaches?action=new"
      expect(response).to redirect_to("/admin/#{company.id}/team?action=new")
      get "/admin/staff"
      expect(response).to redirect_to("/admin/#{company.id}/team")
    end
  end

  describe "who may open it" do
    it "a login without the coaches capability goes home" do
      staff = create(:staff_member, company: company, role: :coach)
      staff.assigned_role.update!(permissions: %w[clients])
      desk = create(:staff_member, company: company, role: :moderator)
      desk.assigned_role.update!(permissions: %w[clients])
      web_sign_in(desk.user)
      get base
      expect(response).to be_redirect
      expect(response.location).not_to include("/team")
    end

    it "a moderator sees the coaches only: logins are the admin's" do
      coach = create(:coach, company: company)
      moderator = create(:staff_member, company: company, role: :moderator)
      web_sign_in(moderator.user)
      get base
      expect(card_keys).to eq([ "coach:#{coach.id}" ])
      expect(response.body).not_to include("team-kind-block")

      post "#{base}/staff", params: { staff_member: { first_name: "X", last_name: "Y", email: "x@y.tn", password: "password123", role_id: company.roles.find_by!(key: "moderator").id } }, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the writes, as /api/v1 makes them" do
    before { web_sign_in(admin) }

    it "creates a coach, then their mobile login, audited as the API does" do
      post "#{base}/coaches", params: { coach: { first_name: "Rania", last_name: "Hamdi", email: "rania@gym.tn", birthdate: "1990-04-02" } }, as: :json
      expect(response).to have_http_status(:created)
      coach = company.coaches.find_by!(first_name: "Rania")
      expect(coach.birthdate).to eq(Date.new(1990, 4, 2))

      post "#{base}/coaches/#{coach.id}/login", params: { email: "rania@gym.tn", password: "password123" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(coach.reload.staff_member.role_key).to eq("coach")
      expect(AuditLog.where(action: "coach.login_set", auditable_id: coach.id)).to exist

      post "#{base}/coaches", params: { coach: { first_name: "" } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      post "/api/v1/coaches", params: { coach: { first_name: "" } }, headers: api, as: :json
      expect(response.parsed_body["error"]).to be_present
    end

    it "creates a back-office login like POST /api/v1/staff: user, seat, audit, confirmation mail" do
      role = company.roles.create!(name: "Réception", permissions: %w[clients])
      expect {
        post "#{base}/staff", params: { staff_member: { first_name: "Hela", last_name: "Ch", email: "hela@gym.tn", password: "password123", role_id: role.id, birthdate: "1988-11-02" } }, as: :json
      }.to have_enqueued_mail(AccountMailer, :email_verification)
      expect(response).to have_http_status(:created)
      web = StaffMember.joins(:user).find_by!(users: { email: "hela@gym.tn" })

      post "/api/v1/staff", params: { staff_member: { first_name: "Hela", last_name: "Ch", email: "hela2@gym.tn", password: "password123", role_id: role.id, birthdate: "1988-11-02" } }, headers: api, as: :json
      oracle = StaffMember.joins(:user).find_by!(users: { email: "hela2@gym.tn" })

      shape = ->(s) { [ s.role_key, s.birthdate, s.active, s.user.role, s.user.locale, AuditLog.where(action: "staff.created", auditable_id: s.id).count ] }
      expect(shape.call(web)).to eq(shape.call(oracle))
    end

    it "refuses a back-office login with the API's message" do
      post "#{base}/staff", params: { staff_member: { first_name: "A", last_name: "B", email: admin.email, password: "password123", role_id: company.roles.find_by!(key: "moderator").id } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/Email/)
    end

    it "changes a role and records the change; deactivates a login" do
      staff = create(:staff_member, company: company, role: :moderator)
      accueil = company.roles.create!(name: "Accueil", permissions: %w[clients])
      patch "#{base}/staff/#{staff.id}", params: { staff_member: { role_id: accueil.id, active: true, birthdate: "" } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(staff.reload.role_key).to eq(accueil.key)
      expect(AuditLog.where(action: "staff.role_changed", auditable_id: staff.id)).to exist

      patch "#{base}/staff/#{staff.id}", params: { staff_member: { active: false } }, as: :json
      expect(staff.reload.active).to be(false)
    end

    it "edits and deactivates a coach (soft)" do
      coach = create(:coach, company: company, email: "c@gym.tn")
      patch "#{base}/coaches/#{coach.id}", params: { coach: { first_name: "Neo", bio: "Yoga" } }, as: :json
      expect(coach.reload.slice(:first_name, :bio)).to eq("first_name" => "Neo", "bio" => "Yoga")
      delete "#{base}/coaches/#{coach.id}", as: :json
      expect(coach.reload.active).to be(false)
    end

    it "gives the admin a coach's whole address, and a moderator a masked one" do
      coach = create(:coach, company: company, email: "coach.whole@gym.tn")
      get "#{base}/coaches/#{coach.id}", as: :json
      expect(response.parsed_body.dig("coach", "email")).to eq("coach.whole@gym.tn")

      moderator = create(:staff_member, company: company, role: :moderator)
      delete "/deconnexion"
      web_sign_in(moderator.user)
      get "#{base}/coaches/#{coach.id}", as: :json
      expect(response.parsed_body.dig("coach", "email")).to include("****")
    end

    it "lets only the admin reset a login that is not on the coach role" do
      coach = create(:coach, company: company)
      linked = create(:staff_member, company: company, role: :moderator)
      linked.update!(coach: coach)
      moderator = create(:staff_member, company: company, role: :moderator)
      delete "/deconnexion"
      web_sign_in(moderator.user)
      post "#{base}/coaches/#{coach.id}/login", params: { email: "x@gym.tn", password: "password123" }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("Only the admin can change this login.")
    end

    it "never reaches another salle's team" do
      other = create(:company)
      foreign = create(:coach, company: other)
      patch "#{base}/coaches/#{foreign.id}", params: { coach: { first_name: "Hijack" } }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.first_name).not_to eq("Hijack")
    end
  end
end
