require "rails_helper"

# The superadmin console's tables (Web::DataTable): searched, filtered,
# sorted and paged from the URL, the frame alone when the table asks for
# itself, and nothing but what each model allowlists for the console ever
# reaching the database.
RSpec.describe "The superadmin console's tables", type: :request, openapi: false do
  let(:superadmin) { create(:user, :superadmin, password: "password123") }

  before { web_sign_in(superadmin) }

  # The gyms' names as the table lists them, in order.
  def listed_names(html = response.body)
    html.scan(%r{class="sa-lead-title" href="/superadmin/companies/[0-9a-f-]{36}" data-turbo-frame="_top">(.*?)</a>}m).flatten
        .map { |name| name.gsub(%r{</?mark[^>]*>}, "") }
  end

  describe "the frame" do
    it "lists the resources down the side, marks the page's own and counts the open tickets" do
      create(:support_ticket)
      get "/superadmin/invoices"
      expect(response.body).to include('href="/superadmin/invoices" class="sa-nav-item is-active" aria-current="page"')
      expect(response.body).to include('<span class="sa-nav-badge">1</span>')
      expect(response.body).to include('href="/superadmin/companies"', 'href="/superadmin/support"', 'href="/superadmin/updates"', 'href="/superadmin/pricing"')
    end

    it "answers a table's own request with the table alone" do
      create(:company, name: "Alpha")
      get "/superadmin/companies", params: { search: "alp" }, headers: { "Turbo-Frame" => "sa-table" }
      expect(response.body).to include('<turbo-frame id="sa-table"', %(<mark class="fx-hl">Alp</mark>ha))
      expect(response.body).not_to include("sa-shell", "sa-side")
    end
  end

  describe "the gyms" do
    it "sorts by a column either way, and pages what is left" do
      %w[Charlie Alpha Bravo].each { |name| create(:company, name: name) }

      get "/superadmin/companies", params: { sort: "name", dir: "asc" }
      expect(listed_names).to eq(%w[Alpha Bravo Charlie])
      expect(response.body).to include('aria-sort="ascending"', "/superadmin/companies?dir=desc&amp;sort=name")

      get "/superadmin/companies", params: { sort: "name", dir: "desc" }
      expect(listed_names).to eq(%w[Charlie Bravo Alpha])
    end

    it "pages 25 at a time, keeps the search and the sort in the pages' links, and a page past the last is the last" do
      27.times { |i| create(:company, name: format("Gym %02d", i)) }

      get "/superadmin/companies", params: { search: "gym", sort: "name", dir: "asc" }
      expect(listed_names.size).to eq(25)
      expect(response.body).to include("1–25", "27", "/superadmin/companies?dir=asc&amp;page=2&amp;search=gym&amp;sort=name")

      get "/superadmin/companies", params: { search: "gym", sort: "name", dir: "asc", page: 9 }
      expect(listed_names).to eq([ "Gym 25", "Gym 26" ])

      get "/superadmin/companies", params: { limit: 50 }
      expect(listed_names.size).to eq(27)
    end

    it "filters on the account's plan, and shows the way back while anything narrows" do
      starter = create(:company, name: "Starter Gym")
      create(:subscription, company: starter, plan: :starter)
      pro = create(:company, name: "Pro Gym")
      create(:subscription, company: pro, plan: :pro)

      get "/superadmin/companies", params: { plan: "pro" }
      expect(listed_names).to eq([ "Pro Gym" ])
      expect(response.body).to match(/class="sa-clear"[^>]*data-data-table-target="clear">/)

      get "/superadmin/companies"
      expect(response.body).to match(/class="sa-clear"[^>]*data-data-table-target="clear" hidden>/)
    end

    it "takes an unknown column, direction, filter or page size for the default" do
      create(:company, name: "Alpha")
      get "/superadmin/companies", params: { sort: "password_digest", dir: "sideways", access: "everything", limit: -5, page: "x" }
      expect(response).to have_http_status(:ok)
      expect(listed_names).to eq([ "Alpha" ])
    end

    it "says so when nothing matches, with the way back" do
      create(:company, name: "Alpha")
      get "/superadmin/companies", params: { search: "zzz" }
      expect(response.body).to include(Web::Translations.translate("superadmin.console.no_match", locale: :fr), 'href="/superadmin/companies" class="btn btn-sm btn-outline-secondary"')
    end
  end

  describe "the invoices" do
    let(:company) { create(:company, name: "Zen Club") }

    it "lists every account's, once each even when the account runs several salles, and filters on what was paid" do
      create(:company, admin: company.admin, name: "Zen Club II")
      paid = create(:invoice, company: company, number: "FIT-2026-0101")
      due = create(:invoice, :due, company: company, number: "FIT-2026-0102")

      get "/superadmin/invoices", params: { search: "zen" }
      expect(response.body.scan("FIT-2026-0101").size).to eq(1)
      expect(response.body).to include(due.number, %(data-href="/superadmin/companies/#{company.id}"))

      get "/superadmin/invoices", params: { status: "due" }
      expect(response.body).to include(due.number)
      expect(response.body).not_to include(paid.number)
    end

    it "sorts by amount" do
      create(:invoice, company: company, number: "FIT-2026-0201", amount_cents: 500)
      create(:invoice, company: company, number: "FIT-2026-0202", amount_cents: 90_000)

      get "/superadmin/invoices", params: { sort: "amount", dir: "desc" }
      expect(response.body.index("FIT-2026-0202")).to be < response.body.index("FIT-2026-0201")
    end
  end

  describe "the support tickets" do
    it "lists the open ones unless asked for the rest, and filters on what they are about" do
      open = create(:support_ticket, subject: "Encore ouvert")
      resolved = create(:support_ticket, subject: "Déjà réglé", status: :resolved)
      upgrade = create(:support_ticket, subject: "Passer Pro", kind: :upgrade, contact_phone: "+216 22 123 456")

      get "/superadmin/support"
      expect(response.body).to include(open.subject, upgrade.subject)
      expect(response.body).not_to include(resolved.subject)

      get "/superadmin/support", params: { status: "all" }
      expect(response.body).to include(open.subject, resolved.subject)

      get "/superadmin/support", params: { kind: "upgrade" }
      expect(response.body).to include(upgrade.subject)
      expect(response.body).not_to include(open.subject)
    end

    it "searches the gym's name and the message" do
      create(:support_ticket, company: create(:company, name: "Atlas Fitness"), subject: "Badge")
      create(:support_ticket, subject: "Autre", message: "Le planning ne charge pas")

      get "/superadmin/support", params: { search: "atlas" }
      expect(response.body).to include("Badge")
      expect(response.body).not_to include("Autre")

      get "/superadmin/support", params: { search: "planning" }
      expect(response.body).to include("Autre")
    end

    it "sends a ticket that is not there back to the list" do
      get "/superadmin/support/00000000-0000-4000-8000-000000000000"
      expect(response).to redirect_to("/superadmin/support")
    end
  end

  describe "the release notes" do
    it "lists them newest first, searched, and opens one on its own page" do
      old = create(:app_update, version: "1.0.0", title: "Première", published_at: 2.days.ago)
      create(:app_update, version: "2.0.0", title: "Seconde", published_at: 1.day.ago)

      get "/superadmin/updates"
      expect(response.body.index("Seconde")).to be < response.body.index("Première")
      expect(response.body).to include("update-create")

      get "/superadmin/updates", params: { search: "prem" }
      expect(response.body).not_to include("Seconde")

      get "/superadmin/updates/#{old.id}"
      expect(response.body).to include("Première", "update-entry-card")
      expect(response.body).not_to include("update-entry-badge")
    end
  end

  describe "the prices" do
    let(:every_rate) { ExchangeRate::SNAPSHOT.merge("TND" => 3.5) }

    it "shows every currency's price with its rate, and that the rates are the built-in ones until a refresh" do
      PlatformSetting.current.update!(price_currency: "EUR")
      SubscriptionPrice.base("starter").update!(monthly_cents: 6_000)
      create(:company, currency: "TND")

      get "/superadmin/pricing"
      body = response.body
      expect(body).to include("1 EUR = 3,3634 TND", "202 DT", "/superadmin/pricing/rates",
                              ERB::Util.html_escape(Web::Translations.translate("superadmin.pricing_rates_snapshot", locale: :fr)))
      expect(body).to match(/data-superadmin-pricing-switching-value="false"/)
    end

    it "shows another currency's prices converted, ready to become the one they are set in" do
      SubscriptionPrice.base("starter").update!(monthly_cents: 17_000)

      get "/superadmin/pricing", params: { currency: "EUR" }
      expect(response.body).to include(%(value="51"), Web::Translations.translate("superadmin.pricing_switch_hint", { from: "TND", to: "EUR" }, locale: :fr))
      expect(response.body).to match(/data-superadmin-pricing-switching-value="true"/)

      patch "/superadmin/pricing", params: { currency: "EUR", plans: { starter: 5_100, pro: 7_400 } }, as: :json
      expect(PlatformSetting.current.price_currency).to eq("EUR")
      expect(SubscriptionPrice.for("TND", plan: "starter").monthly_cents).to eq(17_200)
    end

    it "refreshes the rates on demand, and says so when the source fails" do
      answer = Net::HTTPOK.new("1.1", "200", "OK")
      allow(answer).to receive(:body).and_return({ result: "success", rates: every_rate }.to_json)
      allow(Net::HTTP).to receive(:start).and_return(answer)

      post "/superadmin/pricing/rates"
      expect(response).to redirect_to("/superadmin/pricing")
      expect(flash[:success]).to be_present
      expect(ExchangeRate.find_by!(currency: "TND").per_eur.to_f).to eq(3.5)

      allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout)
      post "/superadmin/pricing/rates"
      expect(flash[:error]).to be_present
      expect(ExchangeRate.find_by!(currency: "TND").per_eur.to_f).to eq(3.5)
    end
  end

  describe "what Ransack may read" do
    it "is nothing outside the console" do
      expect { Company.ransack!(name_cont: "a") }.to raise_error(Ransack::InvalidSearchError)
      expect(User.ransackable_attributes).to be_empty
    end

    it "is never a secret, even in the console" do
      expect { User.ransack!({ password_digest_start: "$2a" }, auth_object: :superadmin) }.to raise_error(Ransack::InvalidSearchError)
      expect { Company.ransack!({ admin_reset_password_token_digest_present: true }, auth_object: :superadmin) }.to raise_error(Ransack::InvalidSearchError)
      expect(User.ransackable_attributes(:superadmin)).to contain_exactly("first_name", "last_name", "email")
    end
  end

  it "is the superadmin's only" do
    company = create(:company, setup_dismissed_at: Time.current)
    delete "/deconnexion"
    web_sign_in(company.admin)
    %w[/superadmin/invoices /superadmin/support /superadmin/updates].each do |path|
      get path
      expect(response).to redirect_to("/admin/#{company.id}/dashboard")
    end
  end
end
