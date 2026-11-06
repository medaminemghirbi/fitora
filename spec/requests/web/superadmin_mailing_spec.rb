require "rails_helper"

# The console's mailing: reusable templates with variables, ticking the admin
# accounts, sending, and what became of it.
RSpec.describe "The superadmin console's mailing", type: :request, openapi: false do
  let(:superadmin) { create(:user, :superadmin, password: "password123") }
  let(:admin) { create(:user, :admin, first_name: "Meriem", email: "meriem@lumen.tn") }
  let!(:company) { create(:company, admin: admin, name: "Studio Lumen") }

  before { web_sign_in(superadmin) }

  def words(key, **params) = Web::Translations.translate(key, params, locale: :fr)

  describe "the templates" do
    it "are offered in the side menu, and created with their variables" do
      get "/superadmin/mail_templates"
      expect(response.body).to include('href="/superadmin/mail_templates" class="sa-nav-item is-active"', 'href="/superadmin/mailings"')

      get "/superadmin/mail_templates/new"
      expect(response.body).to include('name="mail_template[subject]"', 'data-mail-editor-token-param="{{prenom}}"', 'data-mail-editor-token-param="{{lien_connexion}}"')

      post "/superadmin/mail_templates", params: { mail_template: { name: "Maintenance", subject: "Maintenance  pour {{salle}}", body: "Bonjour {{prenom}}" } }
      expect(response).to redirect_to("/superadmin/mail_templates")
      expect(MailTemplate.find_by!(name: "Maintenance").subject).to eq("Maintenance pour {{salle}}")
    end

    it "keep what was typed and say what is wrong" do
      post "/superadmin/mail_templates", params: { mail_template: { name: "", subject: "", body: "Bonjour {{prénom}}" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Bonjour {{prénom}}", words("common.required"), "prénom")
      expect(MailTemplate.count).to eq(0)
    end

    it "refuse a name already taken" do
      create(:mail_template, name: "Maintenance")

      post "/superadmin/mail_templates", params: { mail_template: { name: "maintenance", subject: "Objet", body: "Texte" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "change and go, without touching what was sent" do
      template = create(:mail_template, name: "Avant")
      mailing = create(:mailing, subject: template.subject)

      get "/superadmin/mail_templates/#{template.id}/edit"
      expect(response.body).to include('value="Avant"', "/superadmin/mailings/new?template_id=#{template.id}")

      patch "/superadmin/mail_templates/#{template.id}", params: { mail_template: { name: "Après", subject: "Nouvel objet", body: "Texte" } }
      expect(response).to redirect_to("/superadmin/mail_templates")
      expect(template.reload.name).to eq("Après")

      delete "/superadmin/mail_templates/#{template.id}", as: :json
      expect(response).to have_http_status(:no_content)
      expect(MailTemplate.count).to eq(0)
      expect(mailing.reload.subject).to eq("Bonjour {{prenom}}")
    end

    it "send a template that is not there back to the list" do
      get "/superadmin/mail_templates/00000000-0000-4000-8000-000000000000/edit"
      expect(response).to redirect_to("/superadmin/mail_templates")
    end
  end

  describe "writing a mailing" do
    let(:fields) { { mailing: { subject: "Bonjour {{prenom}}", body: "Pour {{salle}}" }, recipient_ids: [ admin.id ] } }

    it "lists the active admin accounts, nobody else, with what the preview needs" do
      staff = create(:staff_member, company: company, role: :moderator).user
      gone = create(:user, :admin, email: "parti@example.test", active: false)

      get "/superadmin/mailings/new"

      expect(response.body).to include("meriem@lumen.tn", "Studio Lumen", %(value="#{admin.id}"), "&quot;prenom&quot;:&quot;Meriem&quot;")
      expect(response.body).not_to include(%(value="#{staff.id}"), %(value="#{gone.id}"), %(value="#{superadmin.id}"))
    end

    it "opens on a template, or on one account ticked" do
      template = create(:mail_template, subject: "Objet du modèle", body: "Texte du modèle")

      get "/superadmin/mailings/new", params: { template_id: template.id, admin_id: admin.id }

      expect(response.body).to include('value="Objet du modèle"', "Texte du modèle", %(value="#{template.id}" selected), %(value="#{admin.id}" checked))
    end

    it "is one click from a gym's page" do
      get "/superadmin/companies/#{company.id}"
      expect(response.body).to include("/superadmin/mailings/new?admin_id=#{admin.id}")
    end

    it "sends, then shows where it stands" do
      expect { post "/superadmin/mailings", params: fields }.to have_enqueued_job(DeliverMailingJob).once

      mailing = Mailing.sole
      expect(mailing.sent_by).to eq(superadmin)
      expect(response).to redirect_to("/superadmin/mailings/#{mailing.id}")
      expect(flash[:success]).to include("1")

      follow_redirect!
      expect(response.body).to include("meriem@lumen.tn", "Bonjour {{prenom}}", words("superadmin.mailing.status_pending"), words("superadmin.mailing.refresh"))

      mailing.recipients.sole.update!(status: :sent, sent_at: Time.current)
      get "/superadmin/mailings"
      expect(response.body).to include("Bonjour {{prenom}}", words("superadmin.mailing.count_sent", count: 1))
      get "/superadmin/mailings/#{mailing.id}"
      expect(response.body).not_to include(words("superadmin.mailing.refresh"))
    end

    it "keeps everything and says what is missing" do
      expect { post "/superadmin/mailings", params: { mailing: { subject: "", body: "Bonjour {{prénom}}" }, recipient_ids: [] } }
        .not_to have_enqueued_job(DeliverMailingJob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Bonjour {{prénom}}", words("superadmin.mailing.none_selected"), words("common.required"), "prénom")

      post "/superadmin/mailings", params: { mailing: { subject: "", body: "Texte" }, recipient_ids: [ admin.id ] }
      expect(response.body).to include(%(value="#{admin.id}" checked))
    end

    it "searches what was sent" do
      create(:mailing, subject: "Maintenance")
      create(:mailing, subject: "Autre", body: "Rien")

      get "/superadmin/mailings", params: { search: "mainten" }

      expect(response.body).to include("Maintenance</a>").or include("<mark")
      expect(response.body).not_to include("Autre")
    end

    it "sends a mailing that is not there back to the list" do
      get "/superadmin/mailings/00000000-0000-4000-8000-000000000000"
      expect(response).to redirect_to("/superadmin/mailings")
    end
  end

  it "is the superadmin's only" do
    company.update!(setup_dismissed_at: Time.current)
    delete "/deconnexion"
    web_sign_in(admin)

    %w[/superadmin/mailings /superadmin/mailings/new /superadmin/mail_templates /superadmin/mail_templates/new].each do |path|
      get path
      expect(response).to redirect_to("/admin/#{company.id}/dashboard"), path
    end
    expect { post "/superadmin/mailings", params: { mailing: { subject: "S", body: "B" }, recipient_ids: [ admin.id ] } }.not_to change(Mailing, :count)
    expect { post "/superadmin/mail_templates", params: { mail_template: { name: "N", subject: "S", body: "B" } } }.not_to change(MailTemplate, :count)
  end
end
