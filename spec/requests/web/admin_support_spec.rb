require "rails_helper"

# Module 2: the support page. openapi: false — the contract is the API's.
RSpec.describe "Web support page", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:png) { Rack::Test::UploadedFile.new(StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")), "image/png", original_filename: "capture.png") }

  before { web_sign_in(admin) }

  it "shows the form and this salle's history" do
    company.support_tickets.create!(subject: "Mine", message: "x", created_by: admin)
    create(:company).support_tickets.create!(subject: "Not mine", message: "y", created_by: admin)
    get "/admin/#{company.id}/support"

    expect(response.body).to include("<app-admin-support", "Mine")
    expect(response.body).not_to include("Not mine")
  end

  it "sends a ticket with its file: the new history and a toast, as Turbo Streams" do
    expect do
      post "/admin/#{company.id}/support", params: { subject: " Hello ", message: " Help ", attachments: [ png ] },
                                           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end.to change(SupportTicket, :count).by(1)

    ticket = SupportTicket.last
    expect([ ticket.subject, ticket.attachments.count ]).to eq([ "Hello", 1 ])
    expect(AuditLog.where(action: "support_ticket.created", auditable_id: ticket.id)).to exist
    expect(response.body).to include(%(target="support-history"), %(target="toasts"), "toast-item--success")
  end

  it "a refused ticket: the error toast, nothing kept" do
    expect do
      post "/admin/#{company.id}/support", params: { subject: "", message: "" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end.not_to change(SupportTicket, :count)
    expect(response.body).to include("toast-item--error")
  end

  it "opens an attachment of this salle's ticket, and no other's (B-06)" do
    ticket = company.support_tickets.create!(subject: "S", message: "M", created_by: admin)
    ticket.attachments.attach(png)
    get "/admin/#{company.id}/support/#{ticket.id}/attachments/#{ticket.attachments.first.id}"
    follow_redirects!
    expect(response.media_type).to eq("image/png")

    other = create(:company, admin: admin)
    get "/admin/#{other.id}/support/#{ticket.id}/attachments/#{ticket.attachments.first.id}"
    expect(response).to have_http_status(:not_found)
  end

  # A redirect to a link that expires, not the file held in memory: a 100 MB
  # attachment took twice that in the server's RAM on every download.
  it "hands an attachment over by an expiring link, never reading it into memory" do
    ticket = company.support_tickets.create!(subject: "S", message: "M", created_by: admin)
    ticket.attachments.attach(png)
    expect_any_instance_of(ActiveStorage::Blob).not_to receive(:download)

    get "/admin/#{company.id}/support/#{ticket.id}/attachments/#{ticket.attachments.first.id}"
    expect(response).to redirect_to(%r{/rails/active_storage/blobs/redirect/})
    link = response.location

    travel ServesAttachments::LINK_EXPIRES_IN + 1.minute do
      get link
      expect(response).to have_http_status(:not_found)
    end
  end

  it "is the admin's alone" do
    role = create(:role, company: company, permissions: %w[clients])
    delete "/deconnexion"
    web_sign_in(create(:staff_member, company: company, assigned_role: role).user)
    get "/admin/#{company.id}/support"
    expect(response).to be_redirect
  end
end
