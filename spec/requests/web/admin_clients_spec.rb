require "rails_helper"

# The members page and its wizard (MIGRATION_AUDIT §12.4, items 3–8).
# openapi: false — the API calls here are the oracle the pages are compared
# with, not examples of the contract (spec/rails_helper.rb).
RSpec.describe "Web members page", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:page_path) { "/admin/#{company.id}/clients" }

  def staff_with(permissions, company: self.company)
    role = create(:role, company: company, permissions: permissions)
    create(:staff_member, company: company, assigned_role: role).user
  end

  describe "who may open it" do
    it "nobody signed in: the sign-in page" do
      get page_path
      expect(response).to redirect_to("/connexion")
    end

    it "the admin" do
      web_sign_in(admin)
      get page_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<app-clients-list>", 'class="lst-head"')
    end

    it "staff with `clients`, without the admin's export" do
      web_sign_in(staff_with(%w[clients]))
      get page_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("clients-list#exportCsv")
    end

    it "staff without `clients`: their home, as capabilityGuard sends them" do
      web_sign_in(staff_with(%w[payments]))
      get page_path
      expect(response).to redirect_to("/admin/#{company.id}/calendar")
    end

    it "another gym's salle: refused, and nothing of it is shown" do
      other = create(:company)
      create(:client, company: other, first_name: "Secret", last_name: "Member")
      web_sign_in(admin)
      get "/admin/#{other.id}/clients"

      expect(response).to redirect_to("/admin/#{company.id}/dashboard")
      follow_redirect!
      expect(response.body).not_to include("Secret")
    end

    it "a salle the staff login was withdrawn from: refused" do
      staff = staff_with(%w[clients])
      staff.staff_members.update_all(active: false) # rubocop:disable Rails/SkipsModelValidations
      web_sign_in(staff)
      get page_path

      expect(response).not_to have_http_status(:ok)
    end

    it "a locked gym: the locked page" do
      subscription = create(:subscription, company: company)
      subscription.update!(active: false)
      web_sign_in(admin)
      get page_path

      expect(response).to redirect_to("/account-locked")
    end

    it "a coach: the coach shell" do
      web_sign_in(create(:staff_member, company: company, role: :coach).user)
      get page_path
      expect(response).to redirect_to("/coach/#{company.id}/today")
    end

    it "a member's session: their own home" do
      member = create(:client, company: company)
      post "/connexion", params: { email: member.email, password: "x" } # not signed in: refused
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "shows times in the time zone of the salle the URL names" do
    far = create(:company, admin: admin, timezone: "America/New_York")
    create(:client, company: far, joined_at: Time.utc(2026, 1, 2, 3, 0))
    web_sign_in(admin)
    get "/admin/#{far.id}/clients"

    expect(response.body).to include("1 janv. 2026") # 22:00 on 1 January in New York
  end

  describe "salle isolation (two tabs, two salles)" do
    let!(:second) { create(:company, admin: admin) }
    let!(:here) { create(:client, company: company, first_name: "Here") }
    let!(:there) { create(:client, company: second, first_name: "There") }

    it "each URL shows its own salle only, and never moves the account's saved salle" do
      web_sign_in(admin)
      saved = admin.reload.active_company_id

      get "/admin/#{company.id}/clients"
      expect(listed_client_ids).to eq([ here.id ])
      get "/admin/#{second.id}/clients"
      expect(listed_client_ids).to eq([ there.id ])
      get "/admin/#{company.id}/clients"
      expect(listed_client_ids).to eq([ here.id ])

      expect(admin.reload.active_company_id).to eq(saved)
    end

    it "adds a member to the salle the URL names, and only there" do
      web_sign_in(admin)
      post "/admin/#{second.id}/clients", params: { client: { first_name: "New", last_name: "One", phone: "+216 20 000 001" } }

      newcomer = Client.find_by!(first_name: "New")
      expect(newcomer.memberships.pluck(:company_id)).to eq([ second.id ])
    end
  end

  describe "the list is the API's list" do
    let(:yoga) { create(:activity, company: company, name: "Yoga") }
    let(:plan) { create(:contract_type, company: company, name: "Yoga illimité", activity: yoga) }

    before do
      30.times do |i|
        client = create(:client, company: company, first_name: "M#{format('%02d', i)}", last_name: %w[Alpha Beta Gamma][i % 3],
                                 joined_at: (40 - i).days.ago)
        client.membership_for(company).update!(gender: i.even? ? "female" : "male", active: i % 4 != 0)
        create(:contract, client: client, contract_type: plan, activity: yoga) if (i % 3).zero?
      end
      create(:contract, client: Client.find_by!(first_name: "M01"), contract_type: plan, activity: yoga,
                        status: :expired, starts_at: 60.days.ago, expires_at: 30.days.ago)
    end

    def api(params)
      get "/api/v1/clients", params: params, headers: auth_headers(admin).merge("X-Company-Id" => company.id)
      response.parsed_body
    end

    def web(params)
      get page_path, params: params
      listed_client_ids
    end

    matrix = [
      {}, { page: 2 }, { search: "M1" }, { search: "alpha" }, { status: "active" }, { status: "inactive" },
      { status: "contract_active" }, { status: "contract_expired" }, { status: "no_contract" },
      { gender: "female" }, { sort: "joined", direction: "desc" }, { sort: "name", direction: "desc", page: 2 },
      { joined_from: 20.days.ago.to_date.iso8601 }, { joined_to: 10.days.ago.to_date.iso8601, status: "active" },
      { search: "Beta", gender: "male", sort: "joined" }, { status: "no_contract", page: 2 }
    ]

    matrix.each do |params|
      it "rows, order and counts match GET /api/v1/clients for #{params.inspect}" do
        web_sign_in(admin)
        params = params.merge(contract_type_id: plan.id) if params[:status] == "contract_active"
        expected = api(params)
        rows = web(params)

        expect(rows).to eq(expected["clients"].pluck("id"))
        counts = response.body[%r{<span class="lst-head-count" id="cl-head-count">(\d+)</span>}, 1].to_i
        expect(counts).to eq(expected["counts"]["all"])
        %w[active inactive contract_active contract_expired no_contract].each do |status|
          pill = response.body[%r{for="client-status-#{status}"[^>]*>[^<]*<span class="fx-chip-count">(\d+)</span>}, 1].to_i
          expect(pill).to eq(expected["counts"][status]), "#{status} pill"
        end
        if expected["meta"]["total_pages"] > 1
          expect(response.body).to include("#{expected['meta']['total']} résultats")
        end
      end
    end

    it "the activity and plan filters too" do
      web_sign_in(admin)
      expect(web(activity_id: yoga.id)).to eq(api(activity_id: yoga.id)["clients"].pluck("id"))
      expect(web(contract_type_id: plan.id)).to eq(api(contract_type_id: plan.id)["clients"].pluck("id"))
    end

    it "answers a filter change with the three regions, as Turbo Streams" do
      web_sign_in(admin)
      get page_path, params: { status: "active" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      %w[cl-head-count cl-filters cl-card].each { |target| expect(response.body).to include(%(target="#{target}")) }
    end
  end

  describe "the CSV export" do
    before { create(:client, company: company, first_name: "Export", last_name: "Me") }

    it "the admin gets the API's file, named as the Angular app names it" do
      web_sign_in(admin)
      get "#{page_path}.csv"
      web_csv = response.body
      expect(response.headers["Content-Disposition"]).to include("adherents-#{Date.current.iso8601}.csv")

      get "/api/v1/clients", params: { format: "csv" }, headers: auth_headers(admin).merge("X-Company-Id" => company.id)
      expect(web_csv).to eq(response.body)
    end

    it "nobody else" do
      web_sign_in(staff_with(%w[clients]))
      get "#{page_path}.csv"
      expect(response).to be_redirect
    end
  end

  describe "the wizard (POST)" do
    let(:yoga) { create(:activity, company: company, name: "Yoga") }
    let(:plan) { create(:contract_type, company: company, name: "Yoga illimité", activity: yoga, price: 160) }
    let(:person) do
      { first_name: "Rym", last_name: "Haddad", phone: "+216 22 333 444", email: "", date_of_birth: "", gender: "",
        emergency_contact_name: "", emergency_contact_phone: "", notes: "" }
    end

    it "with no plan: the member alone, then their file with a toast" do
      web_sign_in(admin)
      expect { post page_path, params: { client: person } }.to change(Client, :count).by(1)

      client = Client.find_by!(first_name: "Rym")
      expect(response).to redirect_to("/admin/#{company.id}/clients/#{client.id}")
      expect(flash[:success]).to eq(Web::Translations.translate("clients.created", locale: :fr))
      expect(AuditLog.where(action: "client.created", auditable_id: client.id)).to exist
    end

    it "with a plan and the money: the contract and the payment, in one go" do
      web_sign_in(admin)
      post page_path, params: { client: person, subscription: {
        contract_type_id: plan.id, activity_id: yoga.id, starts_on: Date.current.iso8601, discount: "10",
        collect_payment: "true", payment_method: "cash"
      } }

      contract = Client.find_by!(first_name: "Rym").contracts.sole
      expect(contract.final_price).to eq(150)
      expect(contract.payments.sole.amount).to eq(150)
    end

    it "pay later: no payment" do
      web_sign_in(admin)
      post page_path, params: { client: person, subscription: {
        contract_type_id: plan.id, activity_id: yoga.id, starts_on: Date.current.iso8601, discount: "0",
        collect_payment: "false", payment_method: "cash"
      } }

      expect(Client.find_by!(first_name: "Rym").contracts.sole.payments).to be_empty
    end

    it "is the same sale as POST /api/v1/clients" do
      web_sign_in(admin)
      sale = { contract_type_id: plan.id, activity_id: yoga.id, starts_on: Date.current.iso8601, discount: "5", collect_payment: "true", payment_method: "bank_transfer" }
      post page_path, params: { client: person, subscription: sale }
      post "/api/v1/clients", params: { client: person.merge(first_name: "Twin"), subscription: sale },
                              headers: auth_headers(admin).merge("X-Company-Id" => company.id), as: :json

      web_contract, api_contract = %w[Rym Twin].map { |name| Client.find_by!(first_name: name).contracts.sole }
      fields = %w[contract_type_id activity_id base_price discount final_price payment_status status remaining_bookings]
      expect(web_contract.attributes.slice(*fields)).to eq(api_contract.attributes.slice(*fields))
      expect(web_contract.payments.sole.attributes.slice("amount", "payment_method", "status"))
        .to eq(api_contract.payments.sole.attributes.slice("amount", "payment_method", "status"))
    end

    it "a refused sale keeps nothing, and says why at the top of the wizard" do
      web_sign_in(admin)
      expect do
        post page_path, params: { client: person, subscription: { contract_type_id: SecureRandom.uuid, activity_id: yoga.id } },
                        headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end.not_to change(Client, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(target="cl-wizard-error"), "Plan not found")
    end

    it "selling a plan needs `contracts`, as on the API" do
      web_sign_in(staff_with(%w[clients]))
      expect do
        post page_path, params: { client: person, subscription: { contract_type_id: plan.id, activity_id: yoga.id } },
                        headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end.not_to change(Client, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "someone Fitora already knows: asked by email, not added, back to the list with what happened" do
      known = create(:client, company: create(:company), email: "rym@example.com", first_name: "Rym", last_name: "Elsewhere")
      web_sign_in(admin)

      expect {
        post page_path, params: { client: person.merge(email: "Rym@Example.com"), subscription: {
          contract_type_id: plan.id, activity_id: yoga.id, starts_on: Date.current.iso8601, collect_payment: "true", payment_method: "cash"
        } }
      }.to change(MembershipRequest, :count).by(1)
      expect(Contract.count).to eq(0)

      expect(response).to redirect_to(page_path)
      expect(flash[:success]).to eq(Web::Translations.translate("clients.join_request_sent", { email: "rym@example.com" }, locale: :fr))
      expect(known.reload.membership_for(company)).to be_nil
      follow_redirect!
      expect(response.body).not_to include("Elsewhere")
    end

    it "opens by itself on ?action=new" do
      web_sign_in(admin)
      get page_path, params: { action: "new" }
      expect(response.body).to include('data-clients-list-open-wizard-value="true"')
    end
  end

  describe "pre-migration admin URLs (§8.3)" do
    before { web_sign_in(admin) }

    it "go to the same page in the current salle, query string kept" do
      get "/admin/clients?search=sa&status=active"
      expect(response).to redirect_to("/admin/#{company.id}/clients?search=sa&status=active")
    end

    it "keep the Angular router's own redirects" do
      { "/admin" => "dashboard", "/admin/coaches" => "team", "/admin/staff" => "team", "/admin/modules" => "subscription",
        "/admin/contracts/plans" => "catalogue", "/admin/data-exchange" => "settings/data-exchange",
        "/admin/getting-started" => "onboarding" }.each do |legacy, page|
        get legacy
        expect(response).to redirect_to("/admin/#{company.id}/#{page}"), legacy
      end
    end

    it "a page that does not exist: where Angular's `**` sends it, home" do
      get "/admin/#{company.id}/no-such-page"
      expect(response).to redirect_to("/")
    end
  end
end
