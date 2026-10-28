require "rails_helper"

# A member's face and card, from their file.
RSpec.describe "Web member photo and card", type: :request, openapi: false do
  include PngHelper

  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:client) { create(:client, company: company, first_name: "Salma", last_name: "Ben Ali", phone: "20 338 183") }
  let(:base) { "/admin/#{company.id}/clients/#{client.id}" }
  let(:membership) { client.membership_for(company) }

  before { web_sign_in(company.admin) }

  def png
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/sample.png"), "image/png")
  end

  it "takes a photo for this gym only, shows it on the file, and removes it" do
    post "#{base}/photo", params: { photo: png }
    expect(response).to have_http_status(:created)
    expect(membership.reload.photo).to be_attached
    expect(response.parsed_body["photo_url"]).to start_with("/rails/active_storage/blobs/")

    get base
    expect(response.body).to include("prof-photo-img", "member-photo#open", "N° #{membership.card_code}")

    delete "#{base}/photo"
    expect(response).to have_http_status(:no_content)
  end

  it "refuses a file that is not an image" do
    text = Rack::Test::UploadedFile.new(StringIO.new("not an image"), "text/plain", original_filename: "notes.txt")
    post "#{base}/photo", params: { photo: text }

    expect(response).to have_http_status(:unprocessable_content)
    expect(membership.reload.photo).not_to be_attached
  end

  it "hands out the member's card as a PDF" do
    get "#{base}/card"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body).to start_with("%PDF")
  end

  it "offers a WhatsApp reminder and the way to the door on the file" do
    get base
    expect(response.body).to include("https://wa.me/21620338183?text=", "/admin/#{company.id}/entries?member=#{client.id}")
  end
end
