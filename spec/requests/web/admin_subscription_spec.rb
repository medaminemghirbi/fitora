require "rails_helper"

# Module 6: the Fitora subscription page. openapi: false.
RSpec.describe "Web subscription", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:base) { "/admin/#{company.id}/subscription" }

  before do
    Subscription.start_trial!(admin, currency: "TND")
    web_sign_in(admin)
  end

  it "shows the trial, its free days and both plans" do
    get base
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<app-subscription", 'data-state="trial"', "sub-opt")
    expect(response.body).to include("14")
  end

  it "stays open to a locked admin (B-10), while their other pages go to /account-locked" do
    admin.subscription.update!(active: false)
    get base
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-state="closed"')
    get "/admin/#{company.id}/clients"
    expect(response).to redirect_to("/account-locked")
  end

  it "asks for a plan as a support ticket of kind upgrade, with the phone" do
    post "#{base}/request", params: { subject: "Passage à Pro", message: "Merci", contact_phone: "+216 22 123 456" }, as: :json
    expect(response).to have_http_status(:created)
    ticket = company.support_tickets.sole
    expect([ ticket.kind, ticket.contact_phone, ticket.subject ]).to eq([ "upgrade", "+216 22 123 456", "Passage à Pro" ])
    expect(AuditLog.where(action: "support_ticket.created", auditable_id: ticket.id)).to exist

    post "#{base}/request", params: { subject: "Passage à Pro", message: "Merci", contact_phone: "" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("Contact phone can't be blank")
  end

  it "answers a request from a locked account with the API's 402" do
    admin.subscription.update!(active: false)
    post "#{base}/request", params: { subject: "x", message: "y", contact_phone: "+216 22 123 456" }, as: :json
    expect(response).to have_http_status(:payment_required)
    expect(response.parsed_body["error"]).to be_present
  end

  it "keeps the old /modules link working" do
    get "/admin/#{company.id}/modules"
    expect(response).to redirect_to(base)
  end

  describe "the invoices" do
    let(:superadmin) { create(:user, :superadmin) }

    it "lists the bill a change of plan left to pay, first, then the paid ones, each a PDF" do
      SuperadminActions.update_subscription(company, { plan: "pro", billing_period: "monthly" }, by: superadmin)
      bill = admin.subscription.reload.due_invoice
      trial = admin.subscription.invoices.find_by!(trial: true)

      get base
      expect(response.body).to include(Web::Translations.translate("subscription.invoices_title", locale: :fr))
      expect(response.body.index(bill.number)).to be < response.body.index(trial.number)
      expect(response.body).to include(Web::Translations.translate("subscription.invoice_due", locale: :fr))

      get "/admin/#{company.id}/invoices/#{bill.id}"
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("#{bill.number}.pdf")
    end

    it "opens no other account's invoice" do
      other = create(:company)
      invoice = create(:invoice, company: other, number: "FIT-1999-0001")
      get "/admin/#{company.id}/invoices/#{invoice.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "stay open to a locked admin, as the page does" do
      admin.subscription.update!(active: false)
      invoice = admin.subscription.invoices.first
      get "/admin/#{company.id}/invoices/#{invoice.id}"
      expect(response.media_type).to eq("application/pdf")
    end

    it "the API lists what was paid, and names the bill apart" do
      SuperadminActions.update_subscription(company, { plan: "starter", billing_period: "monthly" }, by: superadmin)
      bill = admin.subscription.reload.due_invoice
      headers = auth_headers(admin).merge("X-Company-Id" => company.id)

      get "/api/v1/subscription", headers: headers
      expect(response.parsed_body["invoices"].pluck("id")).not_to include(bill.id)
      expect(response.parsed_body.dig("subscription", "due_invoice", "id")).to eq(bill.id)
      expect(response.parsed_body.dig("subscription", "due_invoice", "paid_at")).to be_nil

      get "/api/v1/invoices", headers: headers
      expect(response.parsed_body["invoices"].pluck("id")).not_to include(bill.id)
    end
  end
end
