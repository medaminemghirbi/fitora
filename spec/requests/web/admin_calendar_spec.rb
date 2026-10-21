require "rails_helper"

# Module 9: the planning. openapi: false — the API calls are oracles.
RSpec.describe "Web calendar", type: :request, openapi: false do
  let(:company) { create(:company, :pro, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:base) { "/admin/#{company.id}/calendar" }
  let(:api) { auth_headers(admin).merge("X-Company-Id" => company.id) }
  let(:activity) { create(:activity, company: company, name: "Yoga", duration: 60, capacity: 12) }
  let(:tunis) { Time.find_zone("Africa/Tunis") }

  before { web_sign_in(admin) }

  it "renders the page around FullCalendar, with the filters' coaches and activities" do
    create(:coach, company: company, first_name: "Amine", last_name: "Ben Salah")
    activity
    get base
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<full-calendar", "Amine Ben Salah", "Yoga")
  end

  it "reads a range as GET /api/v1/sessions?from&to does, with the card's words" do
    session = create(:session, company: company, activity: activity, starts_at: tunis.parse("2026-10-14 09:00"))
    params = { from: "2026-10-12", to: "2026-10-18" }
    get "/api/v1/sessions", params: params, headers: api
    oracle = response.parsed_body["sessions"]

    get "#{base}/events", params: params, as: :json
    sessions = response.parsed_body["sessions"]
    expect(sessions.map { |s| s.except("labels") }).to eq(oracle)
    expect(sessions.first["labels"]).to include("start" => "09:00", "end" => "10:00")
    expect(sessions.first["id"]).to eq(session.id)
  end

  it "creates a session as POST /api/v1/sessions, booking the member named" do
    client = create(:client, company: company)
    starts = 2.days.from_now.change(hour: 18)
    post "#{base}/sessions", params: { session: { activity_id: activity.id, starts_at: starts.iso8601, ends_at: (starts + 1.hour).iso8601, client_id: client.id, trial: true } }, as: :json
    expect(response).to have_http_status(:created)
    session = company.sessions.find_by!(starts_at: starts)
    expect(session.capacity).to eq(12)
    expect(session.bookings.sole.client).to eq(client)
  end

  it "creates a weekly class as POST /api/v1/recurring_schedules, and stops it" do
    post "#{base}/sessions", params: { weekly: true, recurring_schedule: { activity_id: activity.id, start_time: "08:00", starts_on: Date.tomorrow.iso8601, ends_on: 3.weeks.from_now.to_date.iso8601, weekdays: [ 2 ] } }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["generated"]).to be_positive
    schedule = company.recurring_schedules.sole

    patch "#{base}/series/#{schedule.id}", params: { active: false }, as: :json
    expect(response.parsed_body).to include("cancelled_sessions")
    expect(schedule.reload.active).to be(false)
  end

  it "moves and cancels a session, audited as the API audits it" do
    session = create(:session, company: company, activity: activity, starts_at: 2.days.from_now.change(hour: 9))
    later = session.starts_at + 2.hours
    patch "#{base}/sessions/#{session.id}", params: { session: { starts_at: later.iso8601, ends_at: (later + 1.hour).iso8601 } }, as: :json
    expect(session.reload.starts_at).to eq(later)

    post "#{base}/sessions/#{session.id}/cancel", as: :json
    expect(session.reload.status).to eq("cancelled")
    expect(AuditLog.where(action: "session.cancelled", auditable_id: session.id)).to exist
  end

  it "adds a member from the detail, and searches members" do
    session = create(:session, company: company, activity: activity, starts_at: 2.days.from_now)
    client = create(:client, company: company, first_name: "Sarra", last_name: "Lazreg")
    plan = create(:contract_type, company: company)
    plan.contract_type_activities.create!(activity: activity, price: 100)
    Contracts::Actions.sell(client, company: company, by: admin, params: ActionController::Parameters.new(contract_type_id: plan.id, activity_id: activity.id))
    get "#{base}/clients", params: { search: "sarr" }, as: :json
    expect(response.parsed_body["clients"].pluck("id")).to eq([ client.id ])

    post "#{base}/sessions/#{session.id}/bookings", params: { client_id: client.id }, as: :json
    expect(response).to have_http_status(:created)
    expect(session.bookings.sole.client).to eq(client)
  end

  it "is not the coach's: a coach login works in the coach shell" do
    coach_login = create(:staff_member, company: company, role: :coach)
    delete "/deconnexion"
    web_sign_in(coach_login.user)
    get base
    expect(response).to be_redirect
    expect(response.location).not_to include("/admin/")
  end

  it "prints the week (Pro), named as the page names it" do
    get "#{base}/schedule", params: { from: "2026-10-14" }
    expect(response.headers["Content-Disposition"]).to include("planning-2026-10-12.pdf")
  end
end
