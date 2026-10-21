require "rails_helper"

# Module 7: the dashboard. openapi: false — the API calls are oracles.
RSpec.describe "Web dashboard", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:base) { "/admin/#{company.id}" }
  let(:activity) { create(:activity, company: company, name: "Yoga") }

  before { web_sign_in(admin) }

  it "shows what GET /api/v1/admin/dashboard says: the figures, the day, what needs attention" do
    session = create(:session, company: company, activity: activity, starts_at: 1.hour.from_now)
    create(:booking, session: session, client: create(:client, company: company), status: :confirmed)
    get "/api/v1/admin/dashboard", headers: auth_headers(admin).merge("X-Company-Id" => company.id)
    stats = response.parsed_body["stats"]

    get "#{base}/dashboard"
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("<app-dashboard", "Yoga", %(<span _ngcontent-dashboard="" class="dash-kpi-value">#{stats['todays_bookings']}</span>))
    expect(body).to include(%(data-session-id="#{session.id}"))
  end

  it "is for whoever may read the reports" do
    staff = create(:staff_member, company: company, role: :moderator)
    staff.assigned_role.update!(permissions: %w[clients])
    delete "/deconnexion"
    web_sign_in(staff.user)
    get "#{base}/dashboard"
    expect(response).to be_redirect
    expect(response.location).not_to include("/dashboard")
  end

  it "answers the body alone for load()" do
    get "#{base}/dashboard", params: { fragment: 1 }
    expect(response.body).to include("dash-kpis")
    expect(response.body).not_to include("dash-head")
  end

  it "exports the report as /api/v1/admin/reports/export, under the page's file name, audited" do
    get "#{base}/dashboard/report", params: { period_type: "month", period: "2026-10" }
    expect(response.headers["Content-Disposition"]).to include("fitora-rapport-2026-10.xlsx")
    expect(AuditLog.where(action: "report.exported")).to exist
    get "#{base}/dashboard/report", params: { period_type: "month", period: "nope" }
    expect(response).to have_http_status(:unprocessable_content)
  end

  describe "the check-in panel, as /api/v1/attendance" do
    let(:session) { create(:session, company: company, activity: activity, starts_at: 10.minutes.ago) }
    let!(:booking) { create(:booking, session: session, client: create(:client, company: company, first_name: "Sarra"), status: :confirmed) }

    it "lists who the session expects and marks one" do
      get "#{base}/attendance/#{session.id}"
      expect(response.body).to include("Sarra", %(data-booking-id="#{booking.id}"))

      post "#{base}/attendance", params: { booking_id: booking.id, status: "present" }, as: :json
      expect(response.parsed_body.dig("attendance", "attendance", "status")).to eq("present")
      expect(booking.reload.attendance_record.marked_by).to eq(admin)
    end

    it "never reaches another salle's booking" do
      other = create(:company)
      foreign = create(:booking, session: create(:session, company: other, activity: create(:activity, company: other)), client: create(:client, company: other))
      post "#{base}/attendance", params: { booking_id: foreign.id, status: "present" }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
