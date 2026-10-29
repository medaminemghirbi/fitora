require "rails_helper"

# Active Storage's direct-upload routes stay closed (config/routes.rb): an
# anonymous visitor with nothing but the sign-in page's CSRF token could
# otherwise declare a blob of any size and write its body to the disk the
# database lives on. The routes that serve stored files keep working.
RSpec.describe "Security: Active Storage direct uploads", type: :request do
  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  it "refuses to create a blob for a visitor holding the sign-in page's CSRF token" do
    get "/connexion"
    token = response.body[/<meta name="csrf-token" content="([^"]+)"/, 1]
    expect(token).to be_present

    expect {
      post "/rails/active_storage/direct_uploads",
           params: { blob: { filename: "anything.bin", byte_size: 50.gigabytes, checksum: Digest::MD5.base64digest("x"),
                             content_type: "application/octet-stream" } }.to_json,
           headers: { "Content-Type" => "application/json", "X-CSRF-Token" => token }
    }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "refuses the disk upload even with a validly signed upload URL" do
    body = "uploaded straight to storage"
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "anything.bin", byte_size: body.bytesize, checksum: Digest::MD5.base64digest(body), content_type: "application/octet-stream"
    )
    ActiveStorage::Current.url_options = { host: "www.example.com" }
    path = URI(blob.service_url_for_direct_upload).path

    put path, params: body, headers: blob.service_headers_for_direct_upload

    expect(response).to have_http_status(:not_found)
    expect(blob.service.exist?(blob.key)).to be(false)
  end

  it "still serves a stored file through its signed link" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("logo bytes"), filename: "logo.png", content_type: "image/png")

    get Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    expect(response).to have_http_status(:found)

    get URI(response.location).path
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("logo bytes")
  end
end
