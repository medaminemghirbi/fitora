require "rails_helper"

# Module 10: the front desk and a coach's day (MIGRATION_AUDIT §8, salle in
# the URL). openapi: false — the API calls are oracles.
RSpec.describe "Web desk and coach shells", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:activity) { create(:activity, company: company, name: "Yoga") }
  let(:desk) { create(:staff_member, company: company, role: :moderator) }

  describe "the desk" do
    let(:base) { "/desk/#{company.id}" }

    it "is where a front-desk login lands, salle in the URL (B-01)" do
      web_sign_in(desk.user)
      expect(response).to redirect_to("#{base}/dashboard")
    end

    it "keeps old desk links working (§8.3)" do
      web_sign_in(desk.user)
      get "/desk"
      expect(response).to redirect_to("#{base}/dashboard")
      get "/desk/checkin?session=x"
      expect(response).to redirect_to("#{base}/checkin?session=x")
    end

    it "shows what is on now, what is still to come and the day's two counts" do
      travel_to Time.zone.parse("2026-10-14 10:00") do
        create(:session, activity: activity, company: company, starts_at: 30.minutes.ago, ends_at: 30.minutes.from_now)
        create(:session, activity: activity, company: company, starts_at: 4.hours.from_now)
        web_sign_in(desk.user)
        get "#{base}/dashboard"
      end

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<app-desk-shell _nghost-desk-shell", "<app-desk-dashboard _nghost-desk-dashboard", "desk-now", "desk-list-row")
      expect(response.body).to include("#{base}/checkin?session=")
      expect(response.body).to include(%(href="/admin/#{company.id}/clients"))
    end

    it "shows the API's refusal as its error state for a desk without reports" do
      desk.assigned_role.update!(permissions: %w[checkin bookings clients])
      web_sign_in(desk.user)
      get "#{base}/dashboard"
      expect(response.body).to include("fx-state--danger", "You are not allowed to perform this action")
    end

    it "lists today's sessions to check in, and picks the one asked for or the only one" do
      travel_to Time.zone.parse("2026-10-14 10:00") do
        first = create(:session, activity: activity, company: company, starts_at: 2.hours.from_now)
        create(:session, activity: activity, company: company, starts_at: 1.day.from_now)
        web_sign_in(desk.user)

        get "#{base}/checkin"
        expect(response.body).not_to include("desk-session-picker")
        expect(response.body).to include(%(data-checkin-panel-session-value="#{first.id}"))

        create(:session, activity: activity, company: company, starts_at: 5.hours.from_now)
        get "#{base}/checkin"
        expect(response.body.scan("desk-session-option").size).to eq(2)
        get "#{base}/checkin?session=#{first.id}"
        expect(response.body).to include(%(data-checkin-panel-session-value="#{first.id}"))
      end
    end

    it "answers the check-in panel under its own path, as /api/v1/attendance does" do
      session = create(:session, activity: activity, company: company, starts_at: 1.hour.from_now)
      booking = create(:booking, session: session, client: create(:client, company: company, first_name: "Rym"))
      web_sign_in(desk.user)

      get "#{base}/attendance/#{session.id}"
      expect(response.body).to include("ckin-row", "Rym")
      post "#{base}/attendance", params: { booking_id: booking.id, status: "present" }, as: :json
      expect(response.parsed_body.dig("attendance", "attendance", "status")).to eq("present")
    end

    it "searches members from the top bar, as GET /api/v1/clients?search= (six at most)" do
      7.times { |i| create(:client, company: company, first_name: "Salma#{i}") }
      web_sign_in(desk.user)
      get "#{base}/clients", params: { search: "salma", term: "salma" }
      expect(response.body.scan("desk-result\"").size).to eq(6)

      get "#{base}/clients", params: { search: "nobody", term: "nobody" }
      expect(response.body).to include("desk-results-empty", "nobody")
    end

    it "refuses the search to a desk without clients, as the API does" do
      desk.assigned_role.update!(permissions: %w[checkin bookings reports])
      web_sign_in(desk.user)
      get "#{base}/clients", params: { search: "salma" }
      expect(response).to have_http_status(:forbidden)
    end

    it "is not the admin's, nor a coach's, nor a desk without bookings" do
      web_sign_in(company.admin)
      get "#{base}/dashboard"
      expect(response).to redirect_to("/admin/#{company.id}/dashboard")

      coach = create(:staff_member, company: company, role: :coach)
      delete "/deconnexion"
      web_sign_in(coach.user)
      get "#{base}/dashboard"
      expect(response).to redirect_to("/coach/#{company.id}/today")
    end

    it "sends a locked gym's desk to /account-locked" do
      create(:subscription, company: company).update!(active: false)
      web_sign_in(desk.user)
      get "#{base}/dashboard"
      expect(response).to redirect_to("/account-locked")
    end

    it "refuses another gym's salle in the URL, showing nothing of it (§8.2)" do
      other = create(:company)
      web_sign_in(desk.user)
      get "/desk/#{other.id}/dashboard"
      expect(response).to redirect_to("#{base}/dashboard")
    end

    it "switches salle only on paid Pro, as POST /api/v1/companies/:id/switch" do
      second = create(:company, admin: company.admin)
      second.staff_members.create!(user: desk.user, assigned_role: second.roles.find_by!(key: "moderator"))
      web_sign_in(desk.user)

      post "#{base}/switch/#{second.id}", as: :json
      expect(response).to have_http_status(:forbidden)

      subscription = create(:subscription, company: company)
      subscription.update!(plan: "pro")
      subscription.issue_invoice!(issued_by: create(:user, :superadmin))
      post "#{base}/switch/#{second.id}", as: :json
      expect(response.parsed_body["next"]).to eq("/desk/#{second.id}/dashboard")
      expect(desk.user.reload.active_company_id).to eq(second.id)
    end
  end

  describe "a coach's day" do
    let(:coach) { create(:staff_member, company: company, role: :coach) }
    let(:base) { "/coach/#{company.id}" }

    it "is where a coach lands, salle in the URL" do
      web_sign_in(coach.user)
      expect(response).to redirect_to("#{base}/today")
      get "/coach"
      expect(response).to redirect_to("#{base}/today")
    end

    it "lists the coach's own sessions of the day asked for, and only theirs" do
      day = Date.current + 1
      create(:session, activity: activity, company: company, coach: coach.coach, starts_at: day.in_time_zone.change(hour: 9))
      create(:session, activity: create(:activity, company: company, name: "Boxe"), company: company, starts_at: day.in_time_zone.change(hour: 10))
      web_sign_in(coach.user)

      get "#{base}/today", params: { date: day.iso8601 }
      expect(response.body.scan("schedule-row").size).to eq(1)
      expect(response.body).to include("Yoga")
      expect(response.body).not_to include("Boxe")

      get "#{base}/today", params: { date: day.iso8601, fragment: 1 }
      expect(response.body).not_to include("content-header")
      expect(response.body).to include("schedule-row")
    end

    it "draws a session's roster with a button per status, and a row once marked" do
      session = create(:session, activity: activity, company: company, coach: coach.coach, starts_at: 1.hour.from_now)
      booking = create(:booking, session: session, client: create(:client, company: company, first_name: "Rym", phone: "+216 20 111 222"))
      web_sign_in(coach.user)

      get "#{base}/attendance/#{session.id}", headers: { "Accept" => "text/html" }
      expect(response.body).to include("Rym", "+216 20 111 222", "coach-today#mark")
      expect(response.body.scan("data-coach-today-status-param").size).to eq(4)

      post "#{base}/attendance", params: { booking_id: booking.id, status: "late" }.to_json,
                                 headers: { "Content-Type" => "application/json", "Accept" => "text/html" }
      expect(response.body).to include("<tr", "status-badge", "btn btn-sm btn-primary")
    end

    it "lists the people the coach trains, searched, with what to know before a session" do
      session = create(:session, activity: activity, company: company, coach: coach.coach, starts_at: 1.day.from_now)
      rym = create(:client, company: company, first_name: "Rym")
      company.memberships.find_by!(client: rym).update!(health_notes: "Pacemaker")
      create(:booking, session: session, client: rym)
      create(:client, company: company, first_name: "Stranger")
      web_sign_in(coach.user)

      get "#{base}/members"
      expect(response.body).to include("Rym", "Pacemaker")
      expect(response.body).not_to include("Stranger")
      get "#{base}/members", params: { q: "zz", fragment: 1 }
      expect(response.body).to include("fx-state", "zz")
    end

    it "is a coach's only" do
      web_sign_in(desk.user)
      get "#{base}/today"
      expect(response).to redirect_to("/desk/#{company.id}/dashboard")
    end
  end
end
