require "rails_helper"

# Module 3: contracts and payments. openapi: false — the API calls are oracles.
RSpec.describe "Web contracts and payments", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:api_headers) { auth_headers(admin).merge("X-Company-Id" => company.id) }
  let(:yoga) { create(:contract_type, company: company, name: "Yoga illimité", price: 160) }
  let(:pilates) { create(:contract_type, company: company, name: "Pilates", price: 120) }

  def listed_contract_ids(html = response.body)
    html.scan(/data-contract="\{&quot;id&quot;:&quot;([0-9a-f-]{36})/).flatten
  end

  def staff_with(permissions)
    role = create(:role, company: company, permissions: permissions)
    create(:staff_member, company: company, assigned_role: role).user
  end

  before do
    sami = create(:client, company: company, first_name: "Sami", last_name: "Ben Ali")
    lina = create(:client, company: company, first_name: "Lina", last_name: "Trabelsi")
    create(:contract, client: sami, contract_type: yoga, payment_status: :paid)
    create(:contract, client: lina, contract_type: pilates, payment_status: :unpaid)
    create(:contract, client: lina, contract_type: yoga, payment_status: :paid, expires_at: 5.days.from_now)
    create(:contract, client: sami, contract_type: pilates, payment_status: :unpaid, paused_at: 1.day.ago)
  end

  describe "the contracts list" do
    before { web_sign_in(admin) }

    [ {}, { status: "expiring" }, { status: "paused" }, { payment: "unpaid" }, { q: "lina" }, { q: "pilates", status: "active" } ].each do |filters|
      it "rows, counts and totals match GET /api/v1/contracts for #{filters.inspect}" do
        get "/api/v1/contracts", params: filters, headers: api_headers
        api = response.parsed_body
        get "/admin/#{company.id}/contracts", params: filters

        expect(listed_contract_ids).to eq(api["contracts"].pluck("id"))
        expect(response.body).to include(%(<span class="lst-head-count" id="ct-count">#{api['counts']['all']}</span>))
        api["counts"].slice("active", "expiring", "paused", "cancelled").each do |status, count|
          expect(response.body).to match(%r{for="contract-status-#{status}".*?<span class="fx-chip-count">#{count}</span>}m)
        end
        expect(response.body).to include("#{api['totals']['expiring_soon']}</dd>")
      end
    end

    it "filters by plan, as its tab says" do
      get "/admin/#{company.id}/contracts", params: { contract_type_id: pilates.id }
      expect(listed_contract_ids.size).to eq(2)
      expect(response.body).to include("Pilates (2)", "Yoga illimité (2)")
    end

    it "ignores a payment filter other than unpaid or paid, as the Angular page does" do
      get "/admin/#{company.id}/contracts", params: { payment: "bogus" }
      expect(listed_contract_ids.size).to eq(4)
    end

    it "keeps the payment filter out of hasFilters (K-06): a chip, but no reset" do
      get "/admin/#{company.id}/contracts", params: { payment: "unpaid" }
      expect(response.body).to include("fx-active-chip")
      expect(response.body).not_to include("data-contracts-reset")
    end

    it "shows the portfolio's worth only to a login with revenue" do
      get "/admin/#{company.id}/contracts"
      expect(response.body).to include(Web::Translations.translate("contracts.portfolio_value", locale: "fr"))

      delete "/deconnexion"
      web_sign_in(staff_with(%w[contracts]))
      get "/admin/#{company.id}/contracts"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(Web::Translations.translate("contracts.portfolio_value", locale: "fr"))
    end

    it "sends a login without contracts home" do
      delete "/deconnexion"
      web_sign_in(staff_with(%w[clients]))
      get "/admin/#{company.id}/contracts"
      expect(response).to be_redirect
    end

    it "redirects the old plan and activity lists to the catalogue" do
      get "/admin/#{company.id}/contracts/plans?x=1"
      expect(response).to redirect_to("/admin/#{company.id}/catalogue?x=1")
      expect(response).to have_http_status(:found)
    end
  end

  describe "the row actions" do
    let(:contract) { company.contracts.find_by!(contract_type: pilates, paused_at: nil) }

    before { web_sign_in(admin) }

    it "pauses and resumes, with the audit trail the API writes" do
      post "/admin/#{company.id}/contracts/#{contract.id}/pause"
      expect(response).to have_http_status(:no_content)
      expect(contract.reload.paused?).to be(true)
      post "/admin/#{company.id}/contracts/#{contract.id}/resume"
      expect(contract.reload.paused?).to be(false)
      expect(AuditLog.where(auditable_id: contract.id).pluck(:action)).to include("contract.paused", "contract.resumed")
    end

    it "answers a refused pause with the model's message" do
      paused = company.contracts.where.not(paused_at: nil).first
      post "/admin/#{company.id}/contracts/#{paused.id}/pause"
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("This subscription is already paused.")
    end

    it "collects the whole amount in cash, as POST /api/v1/payments does" do
      post "/admin/#{company.id}/contracts/#{contract.id}/collect"
      expect(response).to have_http_status(:no_content)
      payment = contract.payments.last
      expect([ payment.payment_method, payment.amount.to_f, contract.reload.payment_status ]).to eq([ "cash", 120.0, "paid" ])
      expect(AuditLog.where(action: "payment.recorded", auditable_id: payment.id)).to exist
    end

    it "refuses to collect for a login without payments, with the API's message" do
      delete "/deconnexion"
      web_sign_in(staff_with(%w[contracts]))
      post "/admin/#{company.id}/contracts/#{contract.id}/collect"
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("You are not allowed to perform this action")
    end

    it "renews onto the same formule, or onto another one priced for the activity" do
      # Within Contract::RENEWAL_WINDOW of their end.
      same = company.contracts.find_by!(contract_type: yoga, client: company.clients.find_by!(first_name: "Lina"))
      other = create(:contract, client: same.client, contract_type: pilates, payment_status: :paid, expires_at: 3.days.from_now)

      post "/admin/#{company.id}/contracts/#{contract.id}/renew", as: :json
      expect(response).to have_http_status(:unprocessable_content) # not due yet: the model's refusal

      expect { post "/admin/#{company.id}/contracts/#{same.id}/renew", as: :json }.to change(company.contracts, :count).by(1)
      expect(company.contracts.find_by!(renewed_from_id: same.id).contract_type).to eq(yoga)

      post "/admin/#{company.id}/contracts/#{other.id}/renew", params: { contract_type_id: "nope" }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("Contract plan not found")

      post "/admin/#{company.id}/contracts/#{other.id}/renew", params: { contract_type_id: yoga.id, activity_id: yoga.activities.first.id }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(company.contracts.find_by!(renewed_from_id: other.id).contract_type).to eq(yoga)
      expect(AuditLog.where(action: "contract.renewed").count).to eq(2)
    end

    it "sends the documents as PDFs under the Angular names" do
      get "/admin/#{company.id}/contracts/#{contract.id}/agreement"
      expect(response.headers["Content-Disposition"]).to include(%(filename="contrat-#{contract.invoice_ref}.pdf"))
      get "/admin/#{company.id}/contracts/#{contract.id}/receipt"
      expect(response.headers["Content-Disposition"]).to include(%(filename="facture-#{contract.invoice_ref}.pdf"))
      expect(response.body.byteslice(0, 4)).to eq("%PDF")
    end

    it "never reaches another gym's contract" do
      foreign = create(:contract)
      post "/admin/#{company.id}/contracts/#{foreign.id}/pause"
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.paused?).to be(false)
    end
  end

  describe "the payments list" do
    before do
      company.contracts.where(payment_status: :unpaid).find_each do |contract|
        Payments::Actions.record(contract.client, company: company, by: admin, params: { payment_method: "bank_transfer", contract_id: contract.id })
      end
      web_sign_in(admin)
    end

    [ {}, { status: "paid" }, { payment_method: "bank_transfer" }, { q: "sami" }, { status: "refunded" } ].each do |filters|
      it "rows and counts match GET /api/v1/payments for #{filters.inspect}" do
        get "/api/v1/payments", params: filters, headers: api_headers
        api = response.parsed_body
        get "/admin/#{company.id}/payments", params: filters

        expect(response.body.scan(/data-payment-id="([0-9a-f-]{36})"/).flatten).to eq(api["payments"].pluck("id"))
        expect(response.body).to include(%(<span class="lst-head-count" id="pay-count">#{api['counts']['all']}</span>))
        expect(response.body).to include("(#{api['method_counts']['bank_transfer'] || 0})")
      end
    end

    it "opens the record dialog for ?action=new" do
      get "/admin/#{company.id}/payments", params: { action: "new" }
      expect(response.body).to include('data-payments-list-open-value="true"')
    end

    it "offers the refund to the admin only, and refunds" do
      payment = company.payments.paid.first
      get "/admin/#{company.id}/payments"
      expect(response.body).to include("payments-list#refund")
      post "/admin/#{company.id}/payments/#{payment.id}/refund"
      expect(payment.reload.status).to eq("refunded")

      delete "/deconnexion"
      web_sign_in(staff_with(%w[payments clients]))
      get "/admin/#{company.id}/payments"
      expect(response.body).not_to include("payments-list#refund")
      post "/admin/#{company.id}/payments/#{company.payments.paid.first.id}/refund"
      expect(response).to have_http_status(:forbidden)
    end

    it "finds members and what they owe, as the dialog reads them from the API" do
      lina = company.clients.find_by!(first_name: "Lina")
      due = create(:contract, client: lina, contract_type: pilates, payment_status: :unpaid)

      get "/admin/#{company.id}/payments/clients", params: { search: "lin" }
      expect(response.parsed_body["clients"].pluck("full_name")).to eq([ "Lina Trabelsi" ])

      get "/admin/#{company.id}/payments/payables", params: { client_id: lina.id }
      expect(response.parsed_body["payables"]).to eq([
        { "kind" => "contract", "id" => due.id, "label" => "Abonnements — Pilates", "amount_due" => 120.0 }
      ])
    end

    it "records a payment in cash against what was picked" do
      lina = company.clients.find_by!(first_name: "Lina")
      due = create(:contract, client: lina, contract_type: pilates, payment_status: :unpaid)
      post "/admin/#{company.id}/payments", params: { client_id: lina.id, amount: 120, notes: "desk", contract_id: due.id }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(due.reload.payment_status).to eq("paid")
      expect(due.payments.last.payment_method).to eq("cash")
    end

    it "keeps the dialog's lookups behind clients, as the API does" do
      delete "/deconnexion"
      web_sign_in(staff_with(%w[payments]))
      get "/admin/#{company.id}/payments/clients", params: { search: "lin" }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
