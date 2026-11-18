require "rails_helper"

# "Dernière venue" on the member list: the column that says who is drifting.
RSpec.describe "Api::V1::Clients last visit", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:company) { create(:company, admin: admin) }
  let(:activity) { create(:activity, company: company) }

  def attended!(client, at)
    session = create(:session, company: company, activity: activity, starts_at: at, ends_at: at + 1.hour)
    create(:booking, client: client, session: session, status: :confirmed)
  end

  it "sends when each member last came" do
    member = create(:client, company: company)
    attended!(member, 3.days.ago)

    get "/api/v1/clients", headers: auth_headers(admin)

    row = response.parsed_body["clients"].find { |c| c["id"] == member.id }
    expect(Time.zone.parse(row["last_visit_at"])).to be_within(1.minute).of(3.days.ago)
  end

  it "sends the most recent one, not the first" do
    member = create(:client, company: company)
    attended!(member, 30.days.ago)
    attended!(member, 2.days.ago)

    get "/api/v1/clients", headers: auth_headers(admin)

    row = response.parsed_body["clients"].first
    expect(Time.zone.parse(row["last_visit_at"])).to be_within(1.minute).of(2.days.ago)
  end

  it "sends null for someone who has never come" do
    create(:client, company: company)

    get "/api/v1/clients", headers: auth_headers(admin)

    expect(response.parsed_body["clients"].first["last_visit_at"]).to be_nil
  end

  it "ignores a cancelled booking — they did not come" do
    member = create(:client, company: company)
    session = create(:session, company: company, activity: activity,
                               starts_at: 2.days.ago, ends_at: 2.days.ago + 1.hour)
    create(:booking, client: member, session: session, status: :cancelled)

    get "/api/v1/clients", headers: auth_headers(admin)

    expect(response.parsed_body["clients"].first["last_visit_at"]).to be_nil
  end

  it "ignores a session still to come — booked is not came" do
    member = create(:client, company: company)
    attended!(member, 4.days.ago)
    attended!(member, 3.days.from_now)

    get "/api/v1/clients", headers: auth_headers(admin)

    row = response.parsed_body["clients"].first
    expect(Time.zone.parse(row["last_visit_at"])).to be_within(1.minute).of(4.days.ago)
  end

  it "never counts a visit to another gym" do
    other_company = create(:company)
    person = create(:client, company: company)
    create(:membership, client: person, company: other_company)
    elsewhere = create(:session, company: other_company,
                                 activity: create(:activity, company: other_company),
                                 starts_at: 1.day.ago, ends_at: 1.day.ago + 1.hour)
    create(:booking, client: person, session: elsewhere, status: :confirmed)

    get "/api/v1/clients", headers: auth_headers(admin)

    expect(response.parsed_body["clients"].first["last_visit_at"]).to be_nil
  end

  it "asks once for the whole page, not once per member" do
    5.times { attended!(create(:client, company: company), 1.day.ago) }

    queries = 0
    counter = ->(_n, _s, _f, _i, payload) { queries += 1 if payload[:sql].include?('MAX("sessions"."starts_at")') }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get "/api/v1/clients", headers: auth_headers(admin)
    end

    expect(response).to have_http_status(:ok)
    expect(queries).to eq(1)
  end
end
