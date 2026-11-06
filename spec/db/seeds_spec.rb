require "rails_helper"

# Every deploy runs db/seeds.rb on a database people are using. Runs inside the
# example's transaction (use_transactional_fixtures), so it leaves nothing behind.
RSpec.describe "db/seeds.rb" do
  let(:template_names) { [ "Accès suspendu", "Accès rétabli", "Demande de support en cours" ] }

  def seed = silence_stream($stdout) { Rails.application.load_seed }

  it "runs again and again, adding only what Fitora needs to start" do
    expect { 2.times { seed } }.not_to raise_error

    expect(User.superadmin.count).to eq(1)
    expect(PlatformSetting.count).to eq(1)
    expect(ActivityTemplate.count).to be > 0
    expect(MailTemplate.pluck(:name)).to match_array(template_names)
    # No sample data.
    expect(User.where(role: :admin).count).to eq(0)
    expect(Company.count).to eq(0)
    expect(Client.count).to eq(0)
  end

  describe "the superadmin" do
    def seed_superadmin(env = {})
      stub_const("ENV", ENV.to_h.except("SUPERADMIN_EMAIL", "SUPERADMIN_PASSWORD").merge(env))
      load Rails.root.join("db/seeds/superadmin.rb")
    end

    def in_production = allow(Rails).to(receive(:env).and_return("production".inquiry))

    around { |example| silence_stream($stdout) { example.run } }

    it "defaults to a local account outside production" do
      seed_superadmin

      expect(User.superadmin.sole).to have_attributes(email: "admin@fitora.test")
    end

    it "takes its address and password from the environment in production" do
      in_production

      seed_superadmin("SUPERADMIN_EMAIL" => "Boss@Fitora.tn", "SUPERADMIN_PASSWORD" => "a-long-first-password")

      account = User.superadmin.sole
      expect(account.email).to eq("boss@fitora.tn")
      expect(account.authenticate("a-long-first-password")).to eq(account)
    end

    it "stops the first deploy without them rather than using a password from this repository" do
      in_production

      [ {}, { "SUPERADMIN_EMAIL" => "boss@fitora.tn" }, { "SUPERADMIN_PASSWORD" => "a-long-first-password" } ].each do |env|
        expect { seed_superadmin(env) }.to raise_error(/SUPERADMIN_EMAIL and SUPERADMIN_PASSWORD/)
      end
      expect(User.superadmin).to be_empty
    end

    it "is created once: later deploys need nothing, change nothing and add nobody" do
      seed_superadmin("SUPERADMIN_EMAIL" => "boss@fitora.tn", "SUPERADMIN_PASSWORD" => "first-password")
      account = User.superadmin.sole
      account.update!(password: "changed-since")
      version = account.reload.token_version
      in_production

      seed_superadmin
      seed_superadmin("SUPERADMIN_EMAIL" => "other@fitora.tn", "SUPERADMIN_PASSWORD" => "another-password")

      expect(User.superadmin.sole).to eq(account)
      expect(account.reload.authenticate("changed-since")).to eq(account)
      expect(account.token_version).to eq(version)
    end

    it "never writes the password to the output" do
      stub_const("ENV", ENV.to_h.merge("SUPERADMIN_EMAIL" => "boss@fitora.tn", "SUPERADMIN_PASSWORD" => "a-long-first-password"))

      expect { load Rails.root.join("db/seeds/superadmin.rb") }
        .to output(/setup_two_factor EMAIL=boss@fitora\.tn/).to_stdout_from_any_process.and(not_output_password)
    end

    def not_output_password = output(/\A(?!.*a-long-first-password)/m).to_stdout_from_any_process
  end

  describe "the mailing's first templates" do
    before { seed }

    it "use only variables that exist, and read well once filled in" do
      expect(MailTemplate.all.flat_map(&:unknown_variables)).to be_empty

      admin = create(:company, name: "Studio Lumen").admin
      values = AdminMailing.values_for(admin)
      MailTemplate.find_each do |template|
        filled = AdminMailing.fill(template.body, values)
        expect(filled).to include("Bonjour #{admin.first_name},")
        expect(filled).not_to include("{{")
      end
      expect(AdminMailing.fill(MailTemplate.find_by!(name: "Accès rétabli").body, values)).to include("Studio Lumen", "/connexion")
    end

    it "stay as a superadmin left them: reworded, renamed or deleted, whatever the next deploys do" do
      MailTemplate.find_by!(name: "Accès rétabli").update!(subject: "Mon objet")
      MailTemplate.find_by!(name: "Accès suspendu").update!(name: "Compte suspendu")
      MailTemplate.find_by!(name: "Demande de support en cours").destroy!

      2.times { seed }

      expect(MailTemplate.pluck(:name)).to contain_exactly("Accès rétabli", "Compte suspendu")
      expect(MailTemplate.find_by!(name: "Accès rétabli").subject).to eq("Mon objet")
    end

    it "does not take over a template of the same name already there" do
      PlatformSetting.current.update!(seeded_mail_templates: [])
      MailTemplate.find_by!(name: "Accès rétabli").update!(name: "ACCÈS RÉTABLI", subject: "Le mien")

      seed

      expect(MailTemplate.find_by!(name: "ACCÈS RÉTABLI").subject).to eq("Le mien")
      expect(MailTemplate.count).to eq(3)
    end
  end

  private

  def silence_stream(stream)
    old = stream.dup
    stream.reopen(File::NULL)
    stream.sync = true
    yield
  ensure
    stream.reopen(old)
    old.close
  end
end
