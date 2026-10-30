require "rails_helper"

# Lists that used to load everything there was: the most recent ones now,
# newest first. The ceilings are stubbed small here.
RSpec.describe "List ceilings", type: :request, openapi: false do
  let(:company) { create(:company, :pro, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }

  it "lists a gym's most recent support tickets, on the API and the page" do
    stub_const("SupportTicket::LIST_LIMIT", 2)
    oldest, middle, newest = Array.new(3) { |i| create(:support_ticket, company: company, created_by: admin, created_at: (3 - i).days.ago) }

    get "/api/v1/support_tickets", headers: auth_headers(admin)
    expect(response.parsed_body["support_tickets"].pluck("id")).to eq([ newest.id, middle.id ])

    web_sign_in(admin)
    get "/admin/#{company.id}/support"
    expect(response.body.scan('class="ticket-item"').size).to eq(2)
    expect(response.body).not_to include(oldest.subject)
  end

  it "lists the most recent release notes" do
    stub_const("AppUpdate::LIST_LIMIT", 2)
    _oldest, middle, newest = Array.new(3) { |i| create(:app_update, published_at: (3 - i).days.ago) }

    get "/api/v1/app_updates", headers: auth_headers(admin)
    expect(response.parsed_body["app_updates"].pluck("id")).to eq([ newest.id, middle.id ])
  end

  it "lists a member's most recent bookings, past and upcoming" do
    stub_const("MemberApp::BOOKINGS_LIMIT", 2)
    member = create(:client, company: company)
    activity = create(:activity, company: company)
    past = [ 3, 2, 1 ].map { |d| create(:booking, client: member, session: create(:session, activity: activity, starts_at: d.days.ago)) }
    upcoming = [ 1, 2, 3 ].map { |d| create(:booking, client: member, session: create(:session, activity: activity, starts_at: d.days.from_now)) }

    expect(MemberApp.bookings(member, [ company.id ], upcoming: false).pluck(:id)).to eq([ past[2].id, past[1].id ])
    expect(MemberApp.bookings(member, [ company.id ], upcoming: true).pluck(:id)).to eq([ upcoming[0].id, upcoming[1].id ])
  end
end
