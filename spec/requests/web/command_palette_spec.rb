require "rails_helper"

# The command palette (⌘K). openapi: false — the API calls are oracles.
RSpec.describe "Web command palette", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }
  let(:api_headers) { auth_headers(admin).merge("X-Company-Id" => company.id) }
  let(:yoga) { create(:contract_type, company: company, name: "Yoga illimité", price: 160) }

  def palette_value(name, html = response.body)
    JSON.parse(CGI.unescapeHTML(html[/data-command-palette-#{name}-value="([^"]*)"/, 1]))
  end

  it "comes with the admin shell's pages and an admin's actions" do
    web_sign_in(admin)
    get "/admin/#{company.id}/clients"
    expect(response.body).to include('<app-command-palette _nghost-command-palette="" data-controller="command-palette"', "data-palette-open")

    urls = palette_value("commands").pluck("url")
    expect(urls).to include("/admin/#{company.id}/dashboard", "/admin/#{company.id}/clients", "/admin/#{company.id}/settings")
    # B-16: the activity form, in the catalogue.
    expect(palette_value("actions").pluck("url")).to eq(
      %w[clients payments catalogue team].map { |page| "/admin/#{company.id}/#{page}?action=new" }
    )
  end

  it "staff get the pages they may open, no actions and no search" do
    role = create(:role, company: company, permissions: %w[clients])
    staff = create(:staff_member, company: company, assigned_role: role).user
    web_sign_in(staff)
    get "/admin/#{company.id}/clients"

    expect(palette_value("commands").pluck("url")).to eq([ "/admin/#{company.id}/clients", "/admin/#{company.id}/calendar" ])
    expect(palette_value("actions")).to eq([])
    expect(response.body).to include('data-command-palette-search-url-value=""')

    get "/admin/#{company.id}/palette", params: { q: "sa" }, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "is the admin shell's alone (B-17)" do
    get "/connexion"
    expect(response.body).to include("<app-command-palette _nghost-command-palette=\"\"></app-command-palette>")
  end

  describe "the search" do
    before do
      web_sign_in(admin)
      7.times { |i| create(:client, company: company, first_name: "Sami#{i}", last_name: "Ben Ali") }
      sami = company.clients.order(:first_name).first
      create(:contract, client: sami, contract_type: yoga)
      create(:payment, client: sami, company: company, amount: 120, currency: "TND")
    end

    it "lists the first five of each, as the three API lists order them" do
      get "/admin/#{company.id}/palette", params: { q: "sami" }, as: :json
      found = response.parsed_body

      get "/api/v1/clients", params: { search: "sami" }, headers: api_headers
      clients = response.parsed_body["clients"].first(5)
      expect(found["clients"].pluck("label")).to eq(clients.pluck("full_name"))
      expect(found["clients"].pluck("sub")).to eq(clients.map { |c| c["phone"].nil? ? c["email"] : c["phone"] })
      expect(found["clients"].first["url"]).to eq("/admin/#{company.id}/clients/#{clients.first['id']}")

      get "/api/v1/contracts", params: { q: "sami" }, headers: api_headers
      contracts = response.parsed_body["contracts"].first(5)
      expect(found["contracts"].map { |c| [ c["label"], c["sub"] ] }).to eq(contracts.map { |m| [ m["client"]["full_name"], m["plan"]["name"] ] })

      get "/api/v1/payments", params: { q: "sami" }, headers: api_headers
      payments = response.parsed_body["payments"].first(5)
      expect(found["payments"].pluck("sub")).to eq(payments.map { |p| "#{p['amount']} #{p['currency']}" })
      expect(found["payments"].first["url"]).to eq("/admin/#{company.id}/payments?q=sami")
    end
  end
end
