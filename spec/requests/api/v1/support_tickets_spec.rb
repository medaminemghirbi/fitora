require "rails_helper"

RSpec.describe "Api::V1::SupportTickets", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:company) { create(:company, admin: admin) }
  let(:sample_file) { fixture_file_upload("sample.png", "image/png") }

  describe "authorization" do
    it "forbids staff from filing a support ticket" do
      staff = create(:staff_member)

      post "/api/v1/support_tickets", params: { subject: "Bug", message: "Ça bug" }, headers: auth_headers(staff.user)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/support_tickets" do
    it "creates a ticket with an attachment" do
      post "/api/v1/support_tickets",
           params: { subject: "Erreur de paiement", message: "Le paiement échoue systématiquement.", attachments: [ sample_file ] },
           headers: auth_headers(admin)

      expect(response).to have_http_status(:created)
      body = response.parsed_body["support_ticket"]
      expect(body["subject"]).to eq("Erreur de paiement")
      expect(body["status"]).to eq("open")
      expect(body["attachments"].size).to eq(1)
      expect(body["attachments"].first["filename"]).to eq("sample.png")
    end

    it "rejects a ticket with no subject" do
      post "/api/v1/support_tickets", params: { message: "..." }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/support_tickets" do
    it "lists only this company's tickets" do
      create(:support_ticket, company: company, created_by: admin, subject: "Mine")
      create(:support_ticket, subject: "Someone else's")

      get "/api/v1/support_tickets", headers: auth_headers(admin)

      subjects = response.parsed_body["support_tickets"].map { |t| t["subject"] }
      expect(subjects).to eq([ "Mine" ])
    end
  end

  describe "GET /api/v1/support_tickets/:id/attachments/:attachment_id" do
    it "streams the attachment back" do
      ticket = create(:support_ticket, company: company, created_by: admin)
      ticket.attachments.attach(sample_file)

      get "/api/v1/support_tickets/#{ticket.id}/attachments/#{ticket.attachments.first.id}", headers: auth_headers(admin)
      follow_redirects!

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("image/png")
    end
  end
end
