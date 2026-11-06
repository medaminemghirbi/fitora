require "rails_helper"

# Fitora's terms and privacy policy.
RSpec.describe "Web legal pages", type: :request, openapi: false do
  it "shows the terms and the privacy policy to anyone, with the publisher Identity names" do
    PlatformSetting.current.update!(legal_name: "Fitora SARL", tax_id: "1234567/A/M/000", email: "legal@fitora.tn")

    get "/cgu"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conditions générales", "Fitora SARL", "1234567/A/M/000", "legal@fitora.tn",
                                     "Le compte du Client est créé par Fitora", "une copie de ses données")
    expect(response.body).not_to include("Starter", "essai gratuit", "timbre fiscal", "et de vente", "comptables")

    get "/confidentialite"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Politique de confidentialité", "2004-63")
  end

  it "shows the English translation, and the French text to an Arabic reader with a note" do
    cookies[:fitora_locale] = "en"
    get "/cgu"
    expect(response.body).to include("Terms of use", "only the French version is binding", "a copy of its data")

    cookies[:fitora_locale] = "ar"
    get "/confidentialite"
    expect(response.body).to include("Qui est responsable de vos données", 'lang="ar" dir="rtl"')
  end

  it "is linked from the landing page" do
    get "/"
    expect(response.body).to include('href="/cgu"', 'href="/confidentialite"')
  end
end
