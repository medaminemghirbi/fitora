require "rails_helper"

# A member's face and what else the desk does from their file.
RSpec.describe "Web member file", type: :request, openapi: false do
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
    expect(response.body).to include("prof-photo-img", "member-photo#open")

    delete "#{base}/photo"
    expect(response).to have_http_status(:no_content)
  end

  it "refuses a file that is not an image" do
    text = Rack::Test::UploadedFile.new(StringIO.new("not an image"), "text/plain", original_filename: "notes.txt")
    post "#{base}/photo", params: { photo: text }

    expect(response).to have_http_status(:unprocessable_content)
    expect(membership.reload.photo).not_to be_attached
  end

  it "offers a WhatsApp reminder on the file, and no card or door" do
    get base
    expect(response.body).to include("https://wa.me/21620338183?text=")
    expect(response.body).not_to include("/entries", "/card")
  end

  describe "where they stand, first and in one sentence" do
    let(:plan) { create(:contract_type, company: company, name: "Yoga illimité") }
    let(:words) { ->(key, **vars) { Web::Translations.translate(key, vars, locale: :fr) } }

    def verdict
      response.body[/<section[^>]*class="prof-verdict".*?<\/section>/m]
    end

    it "no subscription: says so, and offers to sell one" do
      get base
      expect(verdict).to include('data-tone="off"', words.call("clients.verdict_none"), "subscriptions#sell")
      expect(response.body).not_to include("prof-subscription")
    end

    it "all paid: in order, with nothing to do" do
      create(:contract, company: company, client: client, contract_type: plan, payment_status: :paid)
      get base
      expect(verdict).to include('data-tone="ok"', words.call("clients.verdict_ok"), words.call("clients.verdict_paid"))
      expect(verdict).not_to include("<button")
    end

    it "money owed: the amount first, and one way to collect it" do
      create(:contract, company: company, client: client, contract_type: plan)
      get base
      expect(verdict).to include('data-tone="warn"', "à encaisser", "client-profile#openPayment")
      expect(response.body.scan("subscriptions#collect").size).to eq(0)
    end

    it "ended: says so, and leaves the renewal on the subscription" do
      create(:contract, company: company, client: client, contract_type: plan, payment_status: :paid, starts_at: 40.days.ago, expires_at: 10.days.ago)
      get base
      expect(verdict).to include('data-tone="bad"')
      expect(response.body[/<section[^>]*class="prof-card prof-subscription".*?<\/section>/m]).to include("subscriptions#renew")
    end
  end

  it "shows the member's details, and only the ones the gym has" do
    client.membership_for(company).update!(address: "12 rue Habib Thameur", emergency_contact_name: "Nour", emergency_contact_phone: "20 111 222", health_notes: "Hernie discale")
    get base
    expect(response.body).to include('href="tel:20338183"', "12 rue Habib Thameur", "Nour", 'href="tel:20111222"', "Hernie discale", "prof-health has-notes")
    details = response.body[%r{<section[^>]*class="prof-card prof-details".*?</section>}m]
    expect(details).to include("12 rue Habib Thameur")
    expect(details).not_to include(Web::Translations.translate("clients.date_of_birth", {}, locale: :fr))
  end

  it "keeps what is coming apart from what happened" do
    activity = create(:activity, company: company, name: "Yoga")
    ahead = create(:session, company: company, activity: activity, starts_at: 3.days.from_now.change(hour: 18))
    past = create(:session, company: company, activity: create(:activity, company: company, name: "Boxe"), starts_at: 3.days.ago)
    create(:booking, session: ahead, client: client, status: :confirmed)
    create(:booking, session: past, client: client, status: :completed)

    get base
    expect(response.body[/<section[^>]*class="prof-card prof-upcoming".*?<\/section>/m]).to include("Yoga")
    feed = response.body[/<section[^>]*class="prof-card prof-feed".*?<\/section>/m]
    expect(feed).to include("Boxe")
    expect(feed).not_to include("Yoga")
  end

  describe "marking them present" do
    let(:activity) { create(:activity, company: company) }

    it "is offered only when they have a class today" do
      get base
      expect(response.body).not_to include("client-profile#checkIn")

      session = create(:session, company: company, activity: activity, starts_at: Time.current.in_time_zone(company.time_zone).noon)
      create(:booking, session: session, client: client, status: :confirmed)
      get base
      expect(response.body).to include("client-profile#checkIn")
    end
  end
end
