require "rails_helper"

# Module 2: Nouveautés and the notifications (inbox, detail, bell).
# openapi: false — the contract is the API's (spec/rails_helper.rb).
RSpec.describe "Web updates and notifications", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }

  def notify(kind: "employee_birthday", read: false, age: 1.hour, data: { name: "Ines" })
    n = Notification.create!(recipient: admin, company: company, kind: kind, data: data, url: "/admin/team",
                             dedup_key: SecureRandom.hex(4), read_at: read ? Time.current : nil)
    n.update_columns(created_at: age.ago) # rubocop:disable Rails/SkipsModelValidations
    n
  end

  it "Nouveautés lists the releases, newest first" do
    superadmin = create(:user, :superadmin)
    AppUpdate.create!(version: "1.0", title: "Old", created_by: superadmin, published_at: 5.days.ago)
    AppUpdate.create!(version: "1.1", title: "New", created_by: superadmin, published_at: 1.day.ago)
    web_sign_in(admin)
    get "/admin/#{company.id}/updates"

    expect(response.body).to include("<app-admin-updates>", "<app-update-timeline")
    expect(response.body.index("v1.1")).to be < response.body.index("v1.0")
  end

  it "is the admin's alone" do
    role = create(:role, company: company, permissions: %w[clients])
    web_sign_in(create(:staff_member, company: company, assigned_role: role).user)
    get "/admin/#{company.id}/notifications"
    expect(response).to be_redirect
  end

  it "the inbox: pages of ten, the unread count, each kind's words" do
    11.times { |i| notify(read: i.odd?, age: (i + 1).hours) }
    web_sign_in(admin)
    get "/admin/#{company.id}/notifications"

    expect(response.body.scan(/class="notif-item(?: is-unread)?"/).size).to eq(10)
    expect(response.body).to include(%(<span _ngcontent-notifications-inbox="" class="lst-head-count">6</span>), "notif-inbox-more")
    expect(response.body).to include(ERB::Util.html_escape(Web::Translations.translate("notifications.employee_birthday.body", { name: "Ines" }, locale: :fr)))

    get "/admin/#{company.id}/notifications", params: { page: 2, fragment: "inbox" }
    expect(response.body.scan(/class="notif-item(?: is-unread)?"/).size).to eq(1)
  end

  it "marks one read, and all of them" do
    a = notify
    notify
    web_sign_in(admin)
    patch "/admin/#{company.id}/notifications/#{a.id}/read"
    expect(response.parsed_body).to eq("unread_count" => 1)

    post "/admin/#{company.id}/notifications/read_all"
    expect(admin.notifications.unread.count).to eq(0)
  end

  it "opening one reads it, and offers its way on" do
    n = notify(kind: "contract_expiring", data: { client_name: "Sana", contract_type: "Yoga", expires_at: "2026-10-20T10:00:00+01:00" })
    web_sign_in(admin)
    get "/admin/#{company.id}/notifications/#{n.id}"

    expect(n.reload.read?).to be(true)
    expect(response.body).to include("Sana", 'href="/admin/team"', ERB::Util.html_escape(Web::Translations.translate("notifications.open_contract", locale: :fr)))
  end

  it "never another account's notification" do
    other = create(:company).admin
    n = Notification.create!(recipient: other, kind: "employee_birthday", data: {}, url: "/x", dedup_key: "x")
    web_sign_in(admin)
    get "/admin/#{company.id}/notifications/#{n.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "the bell's panel rows" do
    notify
    web_sign_in(admin)
    get "/admin/#{company.id}/notifications", params: { fragment: "panel" }
    expect(response.body).to include('class="notif-row is-unread"', "notif-row-dot")
  end

  it "time ago, as TimeAgoPipe words it" do
    I18n.with_locale(:fr) do
      expect(Web::NotificationText.time_ago(30.seconds.ago)).to eq("à l'instant")
      expect(Web::NotificationText.time_ago(3.minutes.ago)).to eq("il y a 3 min")
      expect(Web::NotificationText.time_ago(5.hours.ago)).to eq("il y a 5 h")
      expect(Web::NotificationText.time_ago(2.days.ago)).to eq("il y a 2 j")
    end
  end
end
