require "rails_helper"

# Module 4: the catalogue. openapi: false — the API calls are oracles.
RSpec.describe "Web catalogue", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:base) { "/admin/#{company.id}/catalogue" }
  let!(:yoga) { create(:activity, company: company, name: "Yoga") }
  let!(:pilates) { create(:activity, company: company, name: "Pilates") }
  let!(:plan) { create(:contract_type, company: company, name: "Mensuel", activity: yoga, price: 120) }

  def staff_with(permissions)
    role = create(:role, company: company, permissions: permissions)
    create(:staff_member, company: company, assigned_role: role).user
  end

  before { web_sign_in(admin) }

  describe "the page" do
    it "opens on the price grid, a column per formule and a row per activity" do
      get base
      expect(response.body).to include("<app-price-grid", "Mensuel", %(data-row="activity:#{yoga.id}"), %(data-price="120"))
      # Pilates is sold under no formule.
      expect(response.body).to match(%r{Pilates\s*</span><span[^>]*class="pg-unsold"})
    end

    it "shows the three steps until there is an activity and a formule" do
      plan.update!(active: false)
      get base
      expect(response.body).to include("cat-steps")
    end

    it "lists, searches and pages each tab as the components do" do
      get base, params: { tab: "activites", q: "yo" }
      expect(response.body).to include("<app-activities", %(<mark class="fx-hl">Yo</mark>ga))
      expect(response.body).not_to include(">Pilates<")

      create_list(:activity, 25, company: company)
      get base, params: { tab: "activites", page: 2 }
      expect(response.body.scan("act-item").size).to eq(2) # 27, 25 a page
    end

    it "never shows the packs tab to a gym without packs" do
      get base, params: { tab: "packs" }
      expect(response.body).to include("<app-price-grid")
      expect(response.body).not_to include('data-tab="packs"')
    end

    it "is for a login holding contract_types" do
      delete "/deconnexion"
      web_sign_in(staff_with(%w[contracts]))
      get base
      expect(response).to be_redirect
    end

    it "answers a fragment — the tabs and the panel — for the page to merge" do
      get base, params: { tab: "formules", fragment: 1 }
      expect(response.body).to start_with(%(<nav _ngcontent-catalogue="" class="nav nav-tabs cat-tabs"))
      expect(response.body).not_to include("<html")
    end
  end

  describe "writes, as the API makes them" do
    it "creates and edits an activity, refusing what the model refuses in English" do
      post "#{base}/activities", params: { activity: { name: "Boxe", session_format: "collective", duration: 60, capacity: 15 } }, as: :json
      expect(response).to have_http_status(:created)
      boxe = company.activities.find_by!(name: "Boxe")

      patch "#{base}/activities/#{boxe.id}", params: { activity: { name: "" } }, as: :json
      get "/api/v1/activities", headers: auth_headers(admin)
      patch "/api/v1/activities/#{boxe.id}", params: { activity: { name: "" } }, headers: auth_headers(admin), as: :json
      api_error = response.parsed_body["error"]
      patch "#{base}/activities/#{boxe.id}", params: { activity: { name: "" } }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(api_error)

      delete "#{base}/activities/#{boxe.id}", as: :json
      expect(boxe.reload.active).to be(false)
    end

    it "adopts activities from the platform's catalogue" do
      template = ActivityTemplate.create!(key: "boxing", family: "combat", names: { "fr" => "Boxe" }, session_format: "collective", duration: 60, capacity: 12)
      post "#{base}/activities/adopt", params: { activity_template_ids: [ template.id ] }, as: :json
      expect(response.parsed_body["activities"].pluck("name")).to eq([ "Boxe" ])
    end

    it "prices one cell of the grid, leaving the rest of the formule alone" do
      patch "#{base}/plans/#{plan.id}", params: { activity_prices: [ { activity_id: yoga.id, price: 120 }, { activity_id: pilates.id, price: 99.5 } ] }, as: :json
      expect(response.parsed_body.dig("plan", "activity_prices").to_h { |r| [ r["activity_name"], r["price"].to_f ] }).to eq("Yoga" => 120.0, "Pilates" => 99.5)
      expect(plan.reload.name).to eq("Mensuel")

      patch "#{base}/plans/#{plan.id}", params: { activity_prices: [ { activity_id: pilates.id, price: 99.5 } ] }, as: :json
      expect(plan.reload.contract_type_activities.map(&:activity_id)).to eq([ pilates.id ])
    end

    it "creates a formule with its prices, and ignores another gym's activity" do
      foreign = create(:activity)
      post "#{base}/plans", params: { contract_type: { name: "Carnet", billing_period: "custom", validity_days: 56, session_count: 10, unlimited_bookings: false, color: "#be185d", active: true },
                                      activity_prices: [ { activity_id: yoga.id, price: 90 }, { activity_id: foreign.id, price: 1 } ], pack_prices: [] }, as: :json
      expect(response).to have_http_status(:created)
      expect(company.contract_types.find_by!(name: "Carnet").contract_type_activities.map(&:activity_id)).to eq([ yoga.id ])
    end

    it "keeps formules to a login holding contract_types, and activities to one holding activities" do
      delete "/deconnexion"
      web_sign_in(staff_with(%w[contract_types]))
      patch "#{base}/plans/#{plan.id}", params: { contract_type: { name: "X" } }, as: :json
      expect(response).to have_http_status(:ok)
      post "#{base}/activities", params: { activity: { name: "Boxe" } }, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    context "with packs on" do
      before { company.update!(settings: { features: { packs: true } }) }

      it "saves a pack with its activities, and refuses one with a single activity" do
        post "#{base}/packs", params: { pack: { name: "Duo" }, activity_ids: [ yoga.id, pilates.id ] }, as: :json
        expect(response).to have_http_status(:created)
        expect(company.packs.find_by!(name: "Duo").activities).to contain_exactly(yoga, pilates)

        post "#{base}/packs", params: { pack: { name: "Solo" }, activity_ids: [ yoga.id ] }, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(company.packs.find_by(name: "Solo")).to be_nil
      end

      it "deactivates and reactivates a pack" do
        pack = CatalogueEditor.save_pack(company.packs.new, company, { name: "Duo" }, activity_ids: [ yoga.id, pilates.id ])
        delete "#{base}/packs/#{pack.id}", as: :json
        expect(pack.reload.active).to be(false)
        patch "#{base}/packs/#{pack.id}", params: { pack: { active: true } }, as: :json
        expect(pack.reload.active).to be(true)
      end
    end

    it "refuses pack writes, as absent, for a gym without packs" do
      post "#{base}/packs", params: { pack: { name: "Duo" }, activity_ids: [ yoga.id, pilates.id ] }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("Packs are not enabled for this gym")
    end
  end
end
