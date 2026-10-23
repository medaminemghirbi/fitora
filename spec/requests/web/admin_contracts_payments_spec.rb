require "rails_helper"

# Module 3: contracts and payments. openapi: false — the API calls are oracles.
RSpec.describe "Web contracts and payments", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:api_headers) { auth_headers(admin).merge("X-Company-Id" => company.id) }
  let(:yoga) { create(:contract_type, company: company, name: "Yoga illimité", price: 160) }
  let(:pilates) { create(:contract_type, company: company, name: "Pilates", price: 120) }

  def listed_contract_ids(html = response.body)
    html.scan(/data-subscription="\{&quot;id&quot;:&quot;([0-9a-f-]{36})/).flatten
  end

  # The work-list tab for `status` ("" for all) and the count it shows.
  def list_count(status, html = response.body)
    html[%r{data-value="#{status}" data-action="contracts-list#setFilter"><span class="abo-list-label">[^<]*</span><span class="abo-list-count[^"]*">(\d+)</span>}, 1]&.to_i
  end

  # In the page's language: the salle's, which signing in remembers.
  def say(key, **params)
    Web::Translations.translate(key, params, locale: cookies["fitora_locale"].presence || "fr")
  end

  # A stored time as the gym reads it.
  def local(time)
    time.in_time_zone(company.time_zone)
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

  describe "the subscriptions list" do
    before { web_sign_in(admin) }

    [ {}, { status: "active" }, { status: "expiring" }, { status: "expired" }, { status: "unpaid" }, { status: "paused" },
      { payment: "unpaid" }, { q: "lina" }, { q: "pilates", status: "active" } ].each do |filters|
      it "rows and counts match GET /api/v1/contracts for #{filters.inspect}" do
        get "/api/v1/contracts", params: filters, headers: api_headers
        api = response.parsed_body
        get "/admin/#{company.id}/contracts", params: filters

        expect(listed_contract_ids).to eq(api["contracts"].pluck("id"))
        expect(list_count("")).to eq(api["counts"]["all"])
        %w[active expiring expired unpaid].each { |list| expect(list_count(list)).to eq(api["counts"][list]) }
      end
    end

    it "puts a lapsed term in the expired list, as the dashboard counts it — nothing ever stores `expired`" do
      lapsed = create(:contract, client: company.clients.first, contract_type: yoga, payment_status: :paid,
                                 starts_at: 40.days.ago, expires_at: 10.days.ago)
      expect(lapsed.reload.status).to eq("active")

      get "/admin/#{company.id}/contracts", params: { status: "expired" }
      expect(listed_contract_ids).to eq([ lapsed.id ])
      expect(response.body).to include(%(<span class="abo-state" data-state="expired">#{say("contracts.state_expired")}</span>))
      dashboard = Dashboard::Statistics.call(company: company)[:attention].find { |row| row[:key] == "expired" }
      expect(dashboard[:count]).to eq(list_count("expired"))
    end

    it "opens the unpaid list for the dashboard's old ?payment=unpaid link" do
      get "/admin/#{company.id}/contracts", params: { payment: "unpaid" }
      expect(response.body).to match(/class="abo-list is-active"[^>]*data-value="unpaid"/)
      expect(listed_contract_ids.size).to eq(2)
    end

    it "shows the usually-empty lists only while they hold something" do
      get "/admin/#{company.id}/contracts"
      expect(list_count("paused")).to eq(1)
      expect(list_count("cancelled")).to be_nil
      expect(list_count("upcoming")).to be_nil
    end

    it "filters by formule, with how many each holds" do
      get "/admin/#{company.id}/contracts", params: { contract_type_id: pilates.id }
      expect(listed_contract_ids.size).to eq(2)
      expect(response.body).to include("Pilates (2)", "Yoga illimité (2)")
    end

    it "ignores a payment filter other than unpaid or paid, as the Angular page does" do
      get "/admin/#{company.id}/contracts", params: { payment: "bogus" }
      expect(listed_contract_ids.size).to eq(4)
    end

    it "offers what to do now as buttons: collect what is owed, renew what is due" do
      get "/admin/#{company.id}/contracts", params: { q: "lina" }
      expect(response.body).to include("subscriptions#collect", "subscriptions#renew", "subscriptions#cancel", "subscriptions#sell")
    end

    it "shows the portfolio's worth only to a login with revenue" do
      get "/admin/#{company.id}/contracts"
      expect(response.body).to include(Web::Translations.translate("contracts.portfolio_value", locale: admin.locale))

      delete "/deconnexion"
      staff = staff_with(%w[contracts])
      web_sign_in(staff)
      get "/admin/#{company.id}/contracts"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(Web::Translations.translate("contracts.portfolio_value", locale: staff.locale))
      # Without `payments`, nothing to collect from here.
      expect(response.body).not_to include("subscriptions#collect")
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

  describe "selling" do
    let(:sami) { company.clients.find_by!(first_name: "Sami") }
    let(:boxe) { create(:activity, company: company, name: "Boxe") }

    before do
      yoga.contract_type_activities.create!(activity: boxe, price: 90)
      web_sign_in(admin)
    end

    it "finds members, with what they already hold" do
      get "/admin/#{company.id}/contracts/members", params: { search: "sami" }
      member = response.parsed_body["members"].sole
      expect(member).to include("id" => sami.id, "name" => "Sami Ben Ali")
      expect(member["holds"].pluck("item")).to include("activity|#{yoga.activities.first.id}")
    end

    it "sells an offer, collected now by the method picked, audited" do
      post "/admin/#{company.id}/contracts", params: {
        client_id: sami.id, contract_type_id: yoga.id, activity_id: boxe.id, starts_on: Date.current.iso8601,
        discount: 10, collect_payment: true, payment_method: "bank_transfer"
      }, as: :json
      expect(response).to have_http_status(:created)
      contract = sami.contracts_for(company).find_by!(activity: boxe)
      expect([ contract.final_price.to_f, contract.payment_status, contract.payments.sole.payment_method ]).to eq([ 80.0, "paid", "bank_transfer" ])
      expect(AuditLog.where(action: "contract.created", auditable_id: contract.id)).to exist
    end

    it "sells unpaid when the desk collects later" do
      post "/admin/#{company.id}/contracts", params: { client_id: sami.id, contract_type_id: yoga.id, activity_id: boxe.id }, as: :json
      expect(response).to have_http_status(:created)
      contract = sami.contracts_for(company).find_by!(activity: boxe)
      expect([ contract.payment_status, local(contract.starts_at).to_date ]).to eq([ "unpaid", local(Time.current).to_date ])
    end

    it "refuses to collect for a login without payments, and an unknown member" do
      delete "/deconnexion"
      staff = staff_with(%w[contracts])
      web_sign_in(staff)
      post "/admin/#{company.id}/contracts", params: { client_id: sami.id, contract_type_id: yoga.id, activity_id: boxe.id, collect_payment: true }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq(say("contracts.errors.not_allowed"))

      post "/admin/#{company.id}/contracts", params: { client_id: SecureRandom.uuid, contract_type_id: yoga.id, activity_id: boxe.id }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "refuses an offer the grid does not price, in the page's language" do
      post "/admin/#{company.id}/contracts", params: { client_id: sami.id, contract_type_id: pilates.id, activity_id: boxe.id }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(say("contracts.errors.no_price", plan: "Pilates", item: "Boxe"))
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

    it "answers a refused pause in the page's language" do
      paused = company.contracts.where.not(paused_at: nil).first
      post "/admin/#{company.id}/contracts/#{paused.id}/pause"
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(say("contracts.errors.already_paused"))
    end

    it "collects the whole amount, by the method picked — cash unless told otherwise" do
      post "/admin/#{company.id}/contracts/#{contract.id}/collect", params: { payment_method: "other" }, as: :json
      expect(response).to have_http_status(:no_content)
      payment = contract.payments.last
      expect([ payment.payment_method, payment.amount.to_f, contract.reload.payment_status ]).to eq([ "other", 120.0, "paid" ])
      expect(AuditLog.where(action: "payment.recorded", auditable_id: payment.id)).to exist

      post "/admin/#{company.id}/contracts/#{contract.id}/collect"
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(say("payments.errors.already_paid"))
    end

    it "refuses to collect for a login without payments" do
      delete "/deconnexion"
      staff = staff_with(%w[contracts])
      web_sign_in(staff)
      post "/admin/#{company.id}/contracts/#{contract.id}/collect"
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq(say("contracts.errors.not_allowed"))
    end

    it "edits the dates, and the discount only while unpaid" do
      starts = local(2.days.from_now).to_date
      patch "/admin/#{company.id}/contracts/#{contract.id}", params: { starts_on: starts.iso8601, expires_on: (starts + 45).iso8601, discount: 20 }, as: :json
      expect(response).to have_http_status(:no_content)
      expect([ local(contract.reload.starts_at).to_date, local(contract.expires_at).to_date, contract.final_price.to_f ]).to eq([ starts, starts + 45, 100.0 ])
      expect(AuditLog.where(action: "contract.updated", auditable_id: contract.id)).to exist

      paid = company.contracts.find_by!(contract_type: yoga, client: company.clients.find_by!(first_name: "Sami"))
      patch "/admin/#{company.id}/contracts/#{paid.id}", params: { discount: 30 }, as: :json
      expect(response.parsed_body["error"]).to eq(say("contracts.errors.discount_locked"))

      patch "/admin/#{company.id}/contracts/#{contract.id}", params: { starts_on: starts.iso8601, expires_on: (starts - 1).iso8601 }, as: :json
      expect(response.parsed_body["error"]).to eq(say("contracts.errors.end_before_start"))
    end

    it "cancels, which forgives what it still owed, audited" do
      client = contract.client
      owed_before = client.outstanding_balance(company)
      post "/admin/#{company.id}/contracts/#{contract.id}/cancel"
      expect(response).to have_http_status(:no_content)
      expect(contract.reload).to have_attributes(status: "cancelled", amount_due: 0.0)
      expect(client.outstanding_balance(company)).to eq(owed_before - contract.final_price)
      expect(AuditLog.where(action: "contract.cancelled", auditable_id: contract.id)).to exist

      post "/admin/#{company.id}/contracts/#{contract.id}/cancel"
      expect(response.parsed_body["error"]).to eq(say("contracts.errors.already_cancelled"))
    end

    it "renews onto the same formule, or onto another one priced for the activity" do
      # Within Contract::RENEWAL_WINDOW of their end.
      same = company.contracts.find_by!(contract_type: yoga, client: company.clients.find_by!(first_name: "Lina"))
      other = create(:contract, client: same.client, contract_type: pilates, payment_status: :paid, expires_at: 3.days.from_now)

      post "/admin/#{company.id}/contracts/#{contract.id}/renew", as: :json
      expect(response).to have_http_status(:unprocessable_content) # not due yet: the model's refusal, with the day it opens
      opens = local(contract.expires_at - Contract::RENEWAL_WINDOW).to_date
      expect(response.parsed_body["error"]).to eq(say("contracts.errors.renew_too_early",
                                                      date: Web::DateFormat.angular(opens.in_time_zone(company.time_zone), "d MMM y", locale: cookies["fitora_locale"].presence || "fr")))

      expect { post "/admin/#{company.id}/contracts/#{same.id}/renew", as: :json }.to change(company.contracts, :count).by(1)
      renewal = company.contracts.find_by!(renewed_from_id: same.id)
      expect([ renewal.contract_type, renewal.starts_at, renewal.payment_status ]).to eq([ yoga, same.expires_at, "unpaid" ])

      post "/admin/#{company.id}/contracts/#{other.id}/renew", params: { contract_type_id: "nope" }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("Contract plan not found")

      post "/admin/#{company.id}/contracts/#{other.id}/renew", params: { contract_type_id: yoga.id, activity_id: yoga.activities.first.id }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(company.contracts.find_by!(renewed_from_id: other.id).contract_type).to eq(yoga)
      expect(AuditLog.where(action: "contract.renewed").count).to eq(2)
    end

    it "renews and collects in one go, with the discount agreed for the new term" do
      due = company.contracts.find_by!(contract_type: yoga, client: company.clients.find_by!(first_name: "Lina"))
      post "/admin/#{company.id}/contracts/#{due.id}/renew", params: { discount: 25, collect_payment: true, payment_method: "cash" }, as: :json
      expect(response).to have_http_status(:no_content)
      renewal = company.contracts.find_by!(renewed_from_id: due.id)
      expect([ renewal.final_price.to_f, renewal.payment_status, renewal.payments.sole.amount.to_f ]).to eq([ 135.0, "paid", 135.0 ])
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
      post "/admin/#{company.id}/contracts/#{foreign.id}/cancel"
      expect(foreign.reload.cancelled?).to be(false)
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
