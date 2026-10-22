require "rails_helper"

# Module 2: rooms and bookings. openapi: false — the API calls are oracles.
RSpec.describe "Web rooms and bookings", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current, settings: { features: { spaces: true } }) }
  let(:admin) { company.admin }

  before { web_sign_in(admin) }

  describe "rooms" do
    it "lists the rooms, with what each is reserved for" do
      yoga = create(:activity, company: company, name: "Yoga")
      space = company.spaces.create!(name: "Studio A", capacity: 12)
      space.activity_ids = [ yoga.id ]
      get "/admin/#{company.id}/spaces"
      expect(response.body).to include("<app-spaces", "Studio A", "Yoga")
    end

    it "is only for a gym with rooms turned on" do
      company.update!(settings: { features: { spaces: false } })
      get "/admin/#{company.id}/spaces"
      expect(response).to be_redirect
    end

    it "saves a room, with its restrictions, and refuses a nameless one" do
      yoga = create(:activity, company: company)
      post "/admin/#{company.id}/spaces", params: { space: { name: "Cabine", capacity: 1, activity_ids: [ yoga.id ] } }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(company.spaces.find_by!(name: "Cabine").activity_ids).to eq([ yoga.id ])

      post "/admin/#{company.id}/spaces", params: { space: { name: "" } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("Name")
    end

    it "deletes an unused room; only deactivates one with sessions ahead" do
      free = company.spaces.create!(name: "Free")
      busy = company.spaces.create!(name: "Busy")
      create(:session, company: company, activity: create(:activity, company: company), space: busy)

      delete "/admin/#{company.id}/spaces/#{free.id}", as: :json
      delete "/admin/#{company.id}/spaces/#{busy.id}", as: :json
      expect(Space.exists?(free.id)).to be(false)
      expect(busy.reload.active).to be(false)
    end
  end

  describe "bookings" do
    let(:activity) { create(:activity, company: company, name: "Yoga") }

    before do
      %w[confirmed completed cancelled confirmed].each_with_index do |status, i|
        session = create(:session, company: company, activity: activity, starts_at: (i + 1).days.ago.change(hour: 9))
        create(:booking, session: session, client: create(:client, company: company, first_name: "Member#{i}"), status: status)
      end
    end

    [ {}, { status: "confirmed" }, { q: "member1" }, { date: 2.days.ago.to_date.iso8601 }, { status: "completed", q: "yoga" } ].each do |filters|
      it "rows and counts match GET /api/v1/bookings for #{filters.inspect}" do
        get "/api/v1/bookings", params: filters, headers: auth_headers(admin).merge("X-Company-Id" => company.id)
        api = response.parsed_body
        get "/admin/#{company.id}/bookings", params: filters

        rows = response.body.scan(/data-booking-id="([0-9a-f-]{36})"/).flatten
        expect(rows).to eq(api["bookings"].pluck("id"))
        expect(response.body).to include(%(<span class="lst-head-count" id="bk-count">#{api['meta']['total']}</span>))
      end
    end

    it "cancels a booking, as the policy allows" do
      booking = Booking.find_by!(status: :confirmed)
      post "/admin/#{company.id}/bookings/#{booking.id}/cancel"
      expect(booking.reload.status).to eq("cancelled")
      expect(AuditLog.where(action: "booking.cancelled", auditable_id: booking.id)).to exist
    end

    it "answers a refused cancellation with the API's 422 and its message, which the page toasts" do
      booking = Booking.find_by!(status: :confirmed)
      allow_any_instance_of(Booking).to receive(:cancel!).and_raise(ApplicationRecord::Refused, "Too late to cancel.")
      post "/admin/#{company.id}/bookings/#{booking.id}/cancel", as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Too late to cancel.")
    end

    # No SMS in this version: no "remind the member" in the row's menu, and
    # no endpoint behind it.
    it "offers no SMS reminder" do
      booking = Booking.find_by!(status: :confirmed)
      get "/admin/#{company.id}/bookings"
      expect(response.body).not_to include("bookings-list#remind")

      post "/admin/#{company.id}/bookings/#{booking.id}/remind", as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "answers a filter change with its regions" do
      get "/admin/#{company.id}/bookings", params: { status: "completed" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      %w[bk-count bk-tabs bk-pills bk-card].each { |t| expect(response.body).to include(%(target="#{t}")) }
    end
  end
end
