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
      get "/superadmin/identity"
      expect(response.body).to include('href="/superadmin/identity" class="sa-nav-item is-active" aria-current="page"')
      expect(response.body).to include('<span class="sa-nav-badge">1</span>')
      expect(response.body).to include('href="/superadmin/companies"', 'href="/superadmin/support"', 'href="/superadmin/updates"', 'href="/superadmin/identity"')
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

    it "filters on the account's activation, and shows the way back while anything narrows" do
      create(:company, name: "Active Gym")
      create(:company, name: "Waiting Gym", admin: create(:user, :admin, :first_sign_in))

      get "/superadmin/companies", params: { activation: "pending" }
      expect(listed_names).to eq([ "Waiting Gym" ])
      expect(response.body).to match(/class="sa-clear"[^>]*data-data-table-target="clear">/)

      get "/superadmin/companies"
      expect(response.body).to match(/class="sa-clear"[^>]*data-data-table-target="clear" hidden>/)
    end

    it "takes an unknown column, direction, filter or page size for the default" do
      create(:company, name: "Alpha")
      get "/superadmin/companies", params: { sort: "password_digest", dir: "sideways", activation: "everything", limit: -5, page: "x" }
      expect(response).to have_http_status(:ok)
      expect(listed_names).to eq([ "Alpha" ])
    end

    it "shows where each gym is and how to reach its admin: the e-mail, whole, and a phone" do
      admin = create(:user, :admin, email: "meriem@studiolumen.tn", phone: nil)
      create(:company, admin: admin, name: "Studio Lumen", city: "La Marsa", country: "TN",
                       address: "12 rue Habib Thameur", phone: "+216 71 774 200")

      get "/superadmin/companies"
      expect(response.body).to include('href="mailto:meriem@studiolumen.tn"', 'href="tel:+21671774200"', "+216 71 774 200",
                                       "La Marsa, TN", "12 rue Habib Thameur")
      expect(response.body).not_to include(EmailMask::STARS)
    end

    it "says so when nothing matches, with the way back" do
      create(:company, name: "Alpha")
      get "/superadmin/companies", params: { search: "zzz" }
      expect(response.body).to include(Web::Translations.translate("superadmin.console.no_match", locale: :fr), 'href="/superadmin/companies" class="btn btn-sm btn-outline-secondary"')
    end
  end

  describe "opening a gym's account" do
    let(:fields) do
      { company: { name: "Studio Lumen", city: "La Marsa", timezone: "Africa/Tunis", currency: "TND", locale: "fr" },
        admin: { first_name: "Meriem", last_name: "Trabelsi", email: "meriem@lumen.tn", phone: "" } }
    end

    it "is offered from the gyms and the overview, and asks for the salle and its admin" do
      %w[/superadmin/companies /superadmin/overview].each do |page|
        get page
        expect(response.body).to include('href="/superadmin/companies/new"'), page
      end

      get "/superadmin/companies/new"
      expect(response.body).to include('name="company[name]"', 'name="company[timezone]"', 'name="company[currency]"', 'name="company[locale]"',
                                       'name="admin[first_name]"', 'name="admin[email]"')
      expect(response.body).not_to include("password")
    end

    it "opens the account, says the credentials left, and lands on its page" do
      expect { post "/superadmin/companies", params: fields }
        .to change(Company, :count).by(1).and change(ActionMailer::Base.deliveries, :count).by(1)

      company = Company.find_by!(name: "Studio Lumen")
      expect(response).to redirect_to("/superadmin/companies/#{company.id}")
      expect(flash[:success]).to include("meriem@lumen.tn")
    end

    it "keeps what was typed and says what is missing, all at once" do
      post "/superadmin/companies", params: { company: fields[:company].merge(name: ""), admin: fields[:admin].merge(last_name: "", email: "nope") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("company-name-error", "admin-last_name-error", "admin-email-error", 'value="La Marsa"', 'value="Meriem"')
      expect(Company.count).to eq(0)
    end

    it "says when the address already has a login" do
      create(:user, :admin, email: "meriem@lumen.tn")

      expect { post "/superadmin/companies", params: fields }.not_to change(Company, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(Web::Translations.translate("clients.email_taken", locale: :fr))
    end

    it "warns when the mail could not leave, and the page offers it again" do
      allow(ActionMailer::Base).to receive(:perform_deliveries).and_return(false)

      post "/superadmin/companies", params: fields
      expect(flash[:warning]).to include("meriem@lumen.tn")

      follow_redirect!
      expect(response.body).to include("superadmin-company#sendCredentials", Web::Translations.translate("superadmin.activation.never_sent", locale: :fr))
    end
  end

  describe "a gym's account" do
    let(:admin) { create(:user, :admin, :first_sign_in, :unverified) }
    let(:company) { create(:company, admin: admin) }

    it "shows how far the activation has come, and offers the credentials again until the admin chooses a password" do
      get "/superadmin/companies/#{company.id}"
      expect(response.body).to include("sa-steps", "superadmin-company#sendCredentials", Web::Translations.translate("superadmin.activation.awaiting_email", locale: :fr))

      post "/superadmin/companies/#{company.id}/credentials", as: :json
      expect(response).to have_http_status(:no_content)
      expect(flash[:success]).to include(admin.email)
      expect(admin.reload.credentials_sent_at).to be_present

      admin.update!(password: "my-own-password", email_verified_at: Time.current, terms_accepted_at: Time.current)
      get "/superadmin/companies/#{company.id}"
      expect(response.body).to include(Web::Translations.translate("superadmin.activation.active", locale: :fr))
      expect(response.body).not_to include("superadmin-company#sendCredentials")
    end

    it "refuses to send credentials over a password the admin chose" do
      admin.update!(password: "my-own-password")

      post "/superadmin/companies/#{company.id}/credentials", as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(admin.reload.authenticate("my-own-password")).to eq(admin)
    end

    it "says when the mail could not leave" do
      allow(ActionMailer::Base).to receive(:perform_deliveries).and_return(false)

      post "/superadmin/companies/#{company.id}/credentials", as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["error"]).to eq(Web::Translations.translate("superadmin.credentials.not_sent", locale: :fr))
    end

    it "has nothing left of what the gym paid" do
      get "/superadmin/companies/#{company.id}"
      expect(response.body).not_to include("ac-ledger", "ac-summary", "/invoices", "/subscription", "sa-danger")
    end
  end

  describe "suspending an account's access" do
    let(:company) { create(:company, name: "Zen Club") }
    let(:admin) { company.admin }

    it "is offered on every row and on the gym's page, then says it is suspended and offers to restore it" do
      company
      get "/superadmin/companies"
      expect(response.body).to include("/superadmin/companies/#{company.id}/suspend", "superadmin-action#run")
      get "/superadmin/companies/#{company.id}"
      expect(response.body).to include("/superadmin/companies/#{company.id}/suspend")

      post "/superadmin/companies/#{company.id}/suspend", as: :json
      expect(response).to have_http_status(:no_content)
      expect(flash[:success]).to include("Zen Club")
      expect(admin.reload.access_suspended_at).to be_present

      words = Web::Translations.translate("superadmin.activation.suspended", locale: :fr)
      get "/superadmin/companies"
      expect(response.body).to include(words, "/superadmin/companies/#{company.id}/restore")
      get "/superadmin/companies/#{company.id}"
      expect(response.body).to include(words, "sa-notice--danger", "/superadmin/companies/#{company.id}/restore")
      expect(response.body).not_to include("/superadmin/companies/#{company.id}/suspend")

      post "/superadmin/companies/#{company.id}/restore", as: :json
      expect(response).to have_http_status(:no_content)
      expect(admin.reload.access_suspended_at).to be_nil
    end

    it "filters on it, and stops offering the credentials meanwhile" do
      waiting = create(:company, name: "Waiting Gym", admin: create(:user, :admin, :first_sign_in))
      create(:company, name: "Open Gym")
      SuperadminActions.suspend_access(waiting, by: superadmin)

      get "/superadmin/companies", params: { activation: "suspended" }
      expect(listed_names).to eq([ "Waiting Gym" ])

      get "/superadmin/companies", params: { activation: "pending" }
      expect(listed_names).to be_empty

      get "/superadmin/companies/#{waiting.id}"
      expect(response.body).not_to include("superadmin-company#sendCredentials")
    end

    it "is the superadmin's only" do
      company.update!(setup_dismissed_at: Time.current)
      delete "/deconnexion"
      web_sign_in(admin)

      post "/superadmin/companies/#{company.id}/suspend", as: :json

      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
      expect(admin.reload.access_suspended_at).to be_nil
    end
  end

  describe "the support tickets" do
    it "lists the open ones unless asked for the rest" do
      open = create(:support_ticket, subject: "Encore ouvert")
      resolved = create(:support_ticket, subject: "Déjà réglé", status: :resolved)

      get "/superadmin/support"
      expect(response.body).to include(open.subject)
      expect(response.body).not_to include(resolved.subject)

      get "/superadmin/support", params: { status: "all" }
      expect(response.body).to include(open.subject, resolved.subject)
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

  describe "Fitora's identity" do
    it "says what the legal pages still lack, and saves it as typed" do
      get "/superadmin/identity"
      expect(response.body).to include("sa-notice", 'name="identity[tax_id]"')

      patch "/superadmin/identity", params: { identity: { legal_name: " Fitora SARL ", tax_id: "1234567/A/M/000", city: "1053 Tunis", email: "contact@fitora.tn" } }
      expect(response).to redirect_to("/superadmin/identity")
      expect(PlatformSetting.current.reload.slice(:legal_name, :tax_id)).to eq("legal_name" => "Fitora SARL", "tax_id" => "1234567/A/M/000")

      follow_redirect!
      expect(response.body).not_to include("sa-notice")
    end

    it "refuses an address that is no address, and changes nothing" do
      patch "/superadmin/identity", params: { identity: { legal_name: "Fitora", email: "nope" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("sa-notice--danger")
      expect(PlatformSetting.current.reload.legal_name).to be_nil
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
      expect(User.ransackable_attributes(:superadmin)).to contain_exactly("first_name", "last_name", "email", "must_change_password", "access_suspended_at")
    end
  end

  it "is the superadmin's only" do
    company = create(:company, setup_dismissed_at: Time.current)
    delete "/deconnexion"
    web_sign_in(company.admin)
    %w[/superadmin/companies/new /superadmin/identity /superadmin/support /superadmin/updates].each do |path|
      get path
      expect(response).to redirect_to("/admin/#{company.id}/dashboard")
    end
  end
end
