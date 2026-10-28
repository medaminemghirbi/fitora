require "rails_helper"

# The till: the day's takings and each login closing its drawer.
RSpec.describe "Web till", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:desk) { create(:staff_member, company: company, role: :moderator).user }
  let(:base) { "/admin/#{company.id}/cash" }
  let(:client) { create(:client, company: company, first_name: "Salma", last_name: "Ben Ali") }
  let(:plan) { create(:contract_type, company: company, name: "Mensuel") }

  def take(amount, by:, method: :cash)
    contract = create(:contract, client: client, contract_type: plan)
    create(:payment, client: client, company: company, contract: contract, amount: amount, payment_method: method,
                     status: :paid, paid_at: Time.current, created_by: by)
  end

  it "shows the whole gym's day to the admin, by method and by login" do
    take(60, by: desk)
    take(40, by: admin, method: :card)
    web_sign_in(admin)
    get base

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("till-totals", "till-staff", "Salma Ben Ali", "100 DT")
  end

  it "shows a desk without `revenue` its own drawer only" do
    take(60, by: desk)
    take(40, by: admin)
    web_sign_in(desk)
    get base

    expect(response.body).to include("60 DT")
    expect(response.body).not_to include("till-staff", "100 DT")
  end

  it "closes the login's drawer with the difference, audited" do
    take(60, by: desk)
    web_sign_in(desk)
    post "#{base}/closings", params: { counted_cash: "50", notes: "Fond de caisse retiré" }, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["difference"].to_d).to eq(-10)
    expect(AuditLog.where(action: "cash.closed")).to exist

    get base
    expect(response.body).to include("till-diff is-short", "Recompter")
  end

  it "answers a refusal in the page's words" do
    web_sign_in(desk)
    post "#{base}/closings", params: { counted_cash: "beaucoup" }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq(Web::Translations.translate("cash.errors.invalid_amount", {}, locale: :fr))
  end

  it "refuses a login that may not take money" do
    desk.staff_members.first.assigned_role.update!(permissions: %w[clients checkin])
    web_sign_in(desk)
    get base
    expect(response).to have_http_status(:redirect)
    post "#{base}/closings", params: { counted_cash: "5" }, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
