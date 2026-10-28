require "rails_helper"

# Fitora's terms and privacy policy, and the sign-up's consent to them.
RSpec.describe "Web legal pages", type: :request, openapi: false do
  it "shows the terms and the privacy policy to anyone, with the publisher Billing names" do
    PlatformSetting.current.update!(legal_name: "Fitora SARL", tax_id: "1234567/A/M/000", email: "legal@fitora.tn")

    get "/cgu"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conditions générales", "Fitora SARL", "1234567/A/M/000", "legal@fitora.tn",
                                     "#{Subscription::TRIAL_DAYS} premiers jours")

    get "/confidentialite"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Politique de confidentialité", "2004-63")
  end

  it "shows the English translation, and the French text to an Arabic reader with a note" do
    cookies[:fitora_locale] = "en"
    get "/cgu"
    expect(response.body).to include("Terms of use and sale", "only the French version is binding")

    cookies[:fitora_locale] = "ar"
    get "/confidentialite"
    expect(response.body).to include("Qui est responsable de vos données", 'lang="ar" dir="rtl"')
  end

  it "is linked from the landing page" do
    get "/"
    expect(response.body).to include('href="/cgu"', 'href="/confidentialite"')
  end

  describe "signing up" do
    let(:fields) { { first_name: "Sana", last_name: "Ali", email: "sana@example.com", password: "password123" } }

    it "refuses an account without the terms accepted, and says why" do
      expect { post "/inscription", params: fields }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("reg-terms-error")
    end

    it "records when the terms were accepted" do
      freeze_time do
        post "/inscription", params: fields.merge(accept_terms: "1")
        expect(User.find_by!(email: "sana@example.com").terms_accepted_at).to eq(Time.current)
      end
    end
  end
end
