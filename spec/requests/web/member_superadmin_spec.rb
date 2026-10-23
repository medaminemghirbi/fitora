require "rails_helper"

# Module 10: a member's own app, and the superadmin's console (their Angular
# URLs, MIGRATION_AUDIT §8.1). openapi: false — the API calls are oracles.
RSpec.describe "Web member and superadmin shells", type: :request, openapi: false do
  let(:company) { create(:company, :pro, setup_dismissed_at: Time.current) }
  let(:activity) { create(:activity, company: company, name: "Yoga") }

  def member_of(*companies, email: "salma@example.com")
    client = create(:client, company: companies.first, first_name: "Salma", last_name: "Bouazizi", email: email)
    companies.drop(1).each { |c| client.memberships.create!(company: c, joined_at: Date.current, active: true) }
    client.update!(password: "password123")
    client
  end

  def pay_pro(company)
    subscription = Subscription.find_by!(admin_id: company.admin_id)
    subscription.issue_invoice!(issued_by: create(:user, :superadmin)) unless subscription.pro_features?
  end

  describe "a member's app" do
    before { pay_pro(company) }

    let!(:member) { member_of(company) }

    it "is where a member lands, and its schedule is their gym's upcoming sessions" do
      create(:session, activity: activity, company: company, starts_at: 1.day.from_now)
      web_sign_in(member)
      expect(response).to redirect_to("/member/home")

      get "/member/home"
      expect(response.body).to include("<app-member-shell _nghost-member-shell", "<app-member-schedule", "mb-slot", "Yoga")
    end

    it "shows the gym picked when the person trains at several, remembered in a cookie" do
      other = create(:company, :pro, name: "Annexe")
      pay_pro(other)
      member.memberships.create!(company: other, joined_at: Date.current, active: true)
      create(:session, activity: create(:activity, company: other, name: "Boxe"), company: other, starts_at: 1.day.from_now)
      web_sign_in(member)

      post "/member/gym", params: { id: other.id }, headers: { "HTTP_REFERER" => "/member/home" }
      get "/member/home"
      expect(response.body).to include("Boxe", "member-brand--switch")
      expect(cookies[:fitora_member_gym]).to eq(other.id)
    end

    it "books a seat, and the schedule redraws its row" do
      create(:contract, client: member, company: company, contract_type: create(:contract_type, company: company, activity: activity), activity: activity)
      session = create(:session, activity: activity, company: company, starts_at: 1.day.from_now)
      web_sign_in(member)
      post "/member/bookings", params: { session_id: session.id }.to_json, headers: { "Content-Type" => "application/json", "Accept" => "text/html" }
      expect(response).to have_http_status(:created)
      expect(response.body).to include("mb-slot is-booked")
      expect(member.bookings.where(session: session)).to exist
    end

    it "lists bookings upcoming or past, and gives one back" do
      booking = create(:booking, client: member, session: create(:session, activity: activity, company: company, starts_at: 1.day.from_now))
      web_sign_in(member)
      get "/member/bookings"
      expect(response.body).to include("member-bookings#cancel")
      get "/member/bookings", params: { when: "past", fragment: 1 }
      expect(response.body).to include("fx-state")

      post "/member/bookings/#{booking.id}/cancel", as: :json
      expect(response).to have_http_status(:ok)
      expect(booking.reload.status).to eq("cancelled")
    end

    it "shows their file, saves their details, and leaves Fitora only with the password" do
      web_sign_in(member)
      get "/member/profile"
      expect(response.body).to include("Salma Bouazizi", "mb-card--danger", "/member/password")

      patch "/member/profile", params: { client: { first_name: "Sal", last_name: "B", phone: "+216 22 000 000" } }, as: :json
      expect(response.parsed_body.dig("client", "full_name")).to eq("Sal B")

      delete "/member/account", params: { password: "nope" }, as: :json
      expect(response.parsed_body["error"]).to eq("password_invalid")

      delete "/member/account", params: { password: "password123" }, as: :json
      expect(response.parsed_body["next"]).to eq("/connexion")
      get "/member/home"
      expect(response).to redirect_to("/connexion")
    end

    it "is a member's only" do
      web_sign_in(company.admin)
      get "/member/home"
      expect(response).to redirect_to("/admin/#{company.id}/dashboard")
    end
  end

  describe "the superadmin's console" do
    let(:superadmin) { create(:user, :superadmin, password: "password123") }

    before { web_sign_in(superadmin) }

    it "lands on the overview, PlatformMetrics' four numbers, in the console's frame" do
      expect(response).to redirect_to("/superadmin/overview")
      get "/superadmin/overview"
      expect(response.body).to include("sa-shell", "sa-nav-item is-active", "fx-kpi")
    end

    it "lists the gyms, searched and narrowed to the closed ones" do
      company
      closed = create(:company, name: "Zen Club")
      create(:subscription, company: closed).update!(active: false)

      get "/superadmin/companies", params: { search: "zen" }
      expect(response.body).to include("<mark class=\"fx-hl\">Zen</mark>")
      expect(response.body).not_to include(company.name)
      get "/superadmin/companies", params: { access: "closed" }
      expect(response.body).to include("Zen Club")
      expect(response.body).not_to include(company.name)
    end

    it "opens a gym's account on one page: its figures, the money beside the gym, its access apart" do
      get "/superadmin/companies/#{company.id}"
      expect(response.body).to include("ac-summary", "sa-record-main", "ac-ledger", "sa-record-aside", "sa-ministats", %(id="ac-currency"), "sa-danger")
      expect(response.body).not_to include("nav-tabs")
    end

    it "moves the plan and the access as the API does, with its audit trail and a toast" do
      patch "/superadmin/companies/#{company.id}/subscription", params: { plan: "starter" }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(flash[:success]).to be_present
      expect(AuditLog.where(action: "subscription.plan_changed")).to exist

      patch "/superadmin/companies/#{company.id}/subscription", params: { active: false }, as: :json
      expect(company.admin.subscription.reload.active).to be(false)
      expect(AuditLog.where(action: "subscription.access_suspended")).to exist
    end

    it "a new plan's bill: in the invoices, tagged to pay, the ledger untouched; the payment settles it" do
      subscription = company.admin.subscription
      subscription.update!(plan: :starter)
      ledger = ->(html) { html[/<div[^>]*class="ac-ledger"[^>]*>.*?<\/div>\s*<p/m] }
      get "/superadmin/companies/#{company.id}"
      before = ledger.call(response.body)
      expect(before).to include("ac-ledger")

      patch "/superadmin/companies/#{company.id}/subscription", params: { plan: "pro" }, as: :json
      bill = subscription.reload.due_invoice
      get "/superadmin/companies/#{company.id}"
      expect(response.body).to include(bill.number, Web::Translations.translate("subscription.invoice_due", locale: :fr))
      expect(ledger.call(response.body)).to eq(before)

      post "/superadmin/companies/#{company.id}/invoices", as: :json
      expect(bill.reload).to be_paid
      expect(subscription.reload.due_invoice).to be_nil
    end

    it "records a payment, and refuses one without a plan in the API's words" do
      post "/superadmin/companies/#{company.id}/invoices", as: :json
      expect(response).to have_http_status(:created)
      invoice = company.admin.subscription.invoices.where(trial: false).last
      delete "/superadmin/companies/#{company.id}/invoices/#{invoice.id}", as: :json
      expect(response).to have_http_status(:no_content)

      company.admin.subscription.update!(plan: nil)
      post "/superadmin/companies/#{company.id}/invoices", as: :json
      expect(response.parsed_body["error"]).to eq("Choose a plan before recording a payment.")
    end

    it "steps inside the gym's admin account, and its sign-out comes back to the console" do
      post "/superadmin/companies/#{company.id}/impersonate", as: :json
      expect(response.parsed_body["next"]).to eq("/admin/#{company.id}/dashboard")
      expect(AuditLog.where(action: "superadmin.impersonation_started")).to exist

      get "/admin/#{company.id}/dashboard"
      expect(response.body).to include("impersonation-banner", company.name)

      delete "/deconnexion"
      expect(response).to redirect_to("/superadmin/overview")
      get "/superadmin/overview"
      expect(response).to have_http_status(:ok)
    end

    it "saves the plans' prices" do
      patch "/superadmin/pricing", params: { currency: "TND", plans: { starter: 5000 }, annual_discount_percent: 10 }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(SubscriptionPrice.for("TND", plan: "starter").monthly_cents).to eq(5000)
    end

    it "resolves a ticket, and opens its attachments through the session (B-14)" do
      ticket = SupportRequest.open(company: company, user: company.admin, subject: "Aide", message: "Merci",
                                   attachments: [ Rack::Test::UploadedFile.new(StringIO.new("pdf"), "application/pdf", original_filename: "a.pdf") ])
      get "/superadmin/support"
      expect(response.body).to include("Aide", %(data-href="/superadmin/support/#{ticket.id}"))
      get "/superadmin/support/#{ticket.id}"
      expect(response.body).to include("Merci", "/superadmin/support/#{ticket.id}/attachments/", "/superadmin/support/#{ticket.id}/resolve")

      get "/superadmin/support/#{ticket.id}/attachments/#{ticket.attachments.first.id}"
      follow_redirects!
      expect(response.body).to eq("pdf")
      patch "/superadmin/support/#{ticket.id}/resolve"
      expect(response).to redirect_to("/superadmin/support/#{ticket.id}")
      expect(flash[:success]).to be_present
      expect(ticket.reload.status).to eq("resolved")
      follow_redirect!
      expect(response.body).not_to include("/superadmin/support/#{ticket.id}/resolve")
    end

    it "publishes release notes, which tell every admin" do
      company
      post "/superadmin/updates", params: { app_update: { version: "9.9.9", title: "Nouveau" } }
      expect(response).to have_http_status(:created)
      expect(Notification.where(recipient: company.admin, kind: "system_update")).to exist
    end

    it "is the superadmin's only" do
      delete "/deconnexion"
      web_sign_in(company.admin)
      get "/superadmin/overview"
      expect(response).to redirect_to("/admin/#{company.id}/dashboard")
    end
  end
end
