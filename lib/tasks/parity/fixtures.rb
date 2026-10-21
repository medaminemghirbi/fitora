module Parity
  # What the parity suite (test/parity, MIGRATION_AUDIT §12) needs beyond
  # Studio Lumen, built on top of it — deterministic, so both the Angular
  # reference and the Rails pages are compared on the same rows, run after
  # run:
  #
  # - 26 more members, so the list has three pages, inactive members and
  #   members without a subscription;
  # - a second, empty salle for the same admin ("Studio Lumen Lac"): the
  #   empty state, the salle switcher, isolation between two salles;
  # - a front-desk login ("Accueil": clients + contracts only), whose
  #   address is not confirmed yet, as a new staff login's is;
  # - a moderator, whose home is the desk (module 10);
  # - an activity no plan prices yet;
  # - the account pages' people: an admin who has not confirmed their
  #   address, and, for each app, one login to reset, one member to invite
  #   and one address to confirm — a token spent by one app cannot be
  #   spent again by the other (tokens! makes fresh ones each run).
  class Fixtures
    PASSWORD = Demo::StudioLumen::PASSWORD
    STAFF_EMAIL = "accueil@studiolumen.tn".freeze
    PENDING_EMAIL = "nouveau@parity.tn".freeze
    DESK_EMAIL = "desk@studiolumen.tn".freeze
    APPS = %w[angular rails].freeze

    # Fresh emailed-link tokens for each app's people → tmp/parity-tokens.json.
    def self.tokens!
      tokens = APPS.to_h do |app|
        [ app, {
          reset: User.find_by!(email: "reset.#{app}@parity.tn").generate_password_reset_token!,
          invitation: Client.find_by!(email: "invite.#{app}@parity.tn").generate_invitation_token!,
          verify: User.find_by!(email: "verify.#{app}@parity.tn").tap { |u| u.update!(email_verified_at: nil) }.generate_email_verification_token!
        } ]
      end
      File.write(Rails.root.join("tmp/parity-tokens.json"), JSON.pretty_generate(tokens))
    end

    FIRST = %w[Aya Badr Cyrine Dali Emna Firas Ghada Hamza Imen Jawher Khalil Lina Malek
               Nada Oussema Rim Sami Tasnim Wael Yasmine Zied Asma Bassem Chaima Donia Elyes].freeze
    LAST = %w[Abid Bouzid Chebbi Dhaouadi Essid Farhat Gharbi Hadded Jlassi Karoui Laabidi
              Mabrouk Nasri Ouertani Riahi Saadaoui Toumi Zouari Amri Baccouche Cherif Dridi
              Elloumi Fourati Guesmi Hamrouni].freeze

    def self.build!
      new.build!
    end

    def build!
      admin = User.find_by!(email: Demo::StudioLumen::ADMIN_EMAIL)
      lumen = admin.companies.find_by!(name: "Studio Lumen")
      members!(lumen, admin)
      # An activity no plan prices yet: the wizard's "no plan for this
      # activity" warning.
      lumen.activities.create!(name: "Stretching", emoji: "🤸", session_format: :collective, capacity: 12, duration: 45)
      lac = Company.open!(admin: admin, attributes: {
        name: "Studio Lumen Lac", currency: "TND", timezone: "Africa/Tunis", locale: "fr", city: "Les Berges du Lac", country: "TN"
      })
      lac.update!(setup_dismissed_at: Time.current)
      admin.update!(active_company: lumen)
      staff = staff!(lumen)
      desk = desk!(lumen)
      pending = User.create!(first_name: "Nour", last_name: "Saidi", email: PENDING_EMAIL, password: PASSWORD, role: :admin, locale: "fr")
      # An admin with an address confirmed and no salle yet: the company
      # setup page. One to look at, and one per app to open a salle with.
      nosalle = User.create!(first_name: "Sami", last_name: "Gharbi", email: "nosalle@parity.tn", password: PASSWORD, role: :admin, locale: "fr", email_verified_at: Time.current)
      APPS.each do |app|
        User.create!(first_name: "Reset", last_name: app.capitalize, email: "reset.#{app}@parity.tn", password: PASSWORD, role: :admin, locale: "fr", email_verified_at: Time.current)
        User.create!(first_name: "Verify", last_name: app.capitalize, email: "verify.#{app}@parity.tn", password: PASSWORD, role: :admin, locale: "fr")
        User.create!(first_name: "Setup", last_name: app.capitalize, email: "setup.#{app}@parity.tn", password: PASSWORD, role: :admin, locale: "fr", email_verified_at: Time.current)
        Client.create!(first_name: "Invite", last_name: app.capitalize, email: "invite.#{app}@parity.tn", phone: "+216 20 000 00#{APPS.index(app)}").join!(lumen)
      end

      updates_and_notifications!(admin, lumen)
      lumen.support_tickets.create!(subject: "Reçu non reçu par un adhérent", message: "Le reçu de Salma n'est pas arrivé par e-mail.", created_by: admin, status: :resolved).update_columns(created_at: 9.days.ago) # rubocop:disable Rails/SkipsModelValidations
      lumen.support_tickets.create!(subject: "Importer nos anciens adhérents", message: "Pouvez-vous nous aider à importer notre fichier Excel ?", created_by: admin).update_columns(created_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations

      fixtures = {
        salles: { lumen: lumen.id, lac: lac.id },
        # Members whose file the member-page states open: a full file, an
        # unsigned waiver, money owed, and nothing yet.
        clients: {
          salma: "salma.bouazizi@gmail.com", rania: "rania.chaabane@gmail.com",
          dali: "dali.dhaouadi@example.tn", badr: "badr.bouzid@example.tn"
        }.transform_values { |email| Client.find_by!(email: email).id },
        logins: {
          admin: { email: admin.email, password: PASSWORD },
          staff: { email: staff.email, password: PASSWORD },
          pending: { email: pending.email, password: PASSWORD },
          nosalle: { email: nosalle.email, password: PASSWORD },
          desk: { email: desk.email, password: PASSWORD },
          coach: { email: "amine@studiolumen.tn", password: PASSWORD },
          member: { email: "salma.bouazizi@gmail.com", password: PASSWORD },
          superadmin: { email: User.find_by!(role: :superadmin).email, password: "password123" }
        }
      }
      File.write(Rails.root.join("tmp/parity.json"), JSON.pretty_generate(fixtures))
      fixtures
    end

    private

    def members!(company, admin)
      yoga = company.contract_types.find_by!(name: "Yoga illimité")
      yoga_activity = company.activities.find_by!(name: "Yoga Vinyasa")

      FIRST.zip(LAST).each_with_index do |(first, last), i|
        client = Client.create!(
          first_name: first, last_name: last,
          phone: format("+216 %<a>02d %<b>03d %<c>03d", a: [ 20, 22, 25, 50, 98 ][i % 5], b: 100 + i * 7, c: 900 - i * 11),
          email: "#{first.downcase}.#{last.downcase}@example.tn"
        )
        membership = client.join!(company)
        membership.update!(joined_at: (200 - i * 6).days.ago, gender: i.even? ? "female" : "male", active: (i % 5 != 4))
        next unless (i % 3).zero?

        Contract.sell!(client: client, contract_type: yoga, activity: yoga_activity, created_by: admin,
                       starts_on: Date.current - (i % 10), collect_payment: i.even?, payment_method: "cash")
      end
    end

    # Two releases, and twelve notifications for the admin — read and unread,
    # minutes to weeks old, every staff kind — so the inbox has two pages.
    def updates_and_notifications!(admin, company)
      superadmin = User.find_by!(role: :superadmin)
      AppUpdate.create!(version: "2.4.0", title: "Encaissements plus rapides", description: "Le reçu s'imprime dès l'encaissement.", created_by: superadmin, published_at: 12.days.ago)
      AppUpdate.create!(version: "2.5.0", title: "Planning : glisser-déposer", description: "Déplacez une séance d'un geste ; les adhérents inscrits sont prévenus.", created_by: superadmin, published_at: 2.days.ago)

      members = company.clients.order(:first_name).limit(6).to_a
      [
        [ "contract_expiring", 2.minutes, false, { client_name: members[0].full_name, contract_type: "Yoga illimité", expires_at: 5.days.from_now.iso8601 } ],
        [ "invoice_issued", 3.hours, false, { number: "FIT-2026-0042", amount: "79", currency: "DT" } ],
        [ "contract_expiring", 26.hours, false, { client_name: members[1].full_name, contract_type: "Reformer 8 séances / mois", expires_at: 3.days.from_now.iso8601 } ],
        [ "employee_birthday", 2.days, true, { name: "Amine Ben Salah" } ],
        [ "system_update", 2.days + 1.hour, true, { version: "2.5.0", title: "Planning : glisser-déposer" } ],
        [ "contract_expiring", 3.days, true, { client_name: members[2].full_name, contract_type: "Carnet EMS 10 séances", expires_at: 1.day.from_now.iso8601 } ],
        [ "invoice_issued", 4.days, true, { number: "FIT-2026-0031", amount: "79", currency: "DT" } ],
        [ "contract_expiring", 5.days, true, { client_name: members[3].full_name, contract_type: "Yoga illimité", expires_at: 2.days.ago.iso8601 } ],
        [ "employee_birthday", 6.days, true, { name: "Ines Gharbi" } ],
        [ "contract_expiring", 9.days, true, { client_name: members[4].full_name, contract_type: "Coaching 5 séances", expires_at: 4.days.ago.iso8601 } ],
        [ "system_update", 12.days, true, { version: "2.4.0", title: "Encaissements plus rapides" } ],
        [ "invoice_issued", 30.days, true, { number: "FIT-2026-0012", amount: "79", currency: "DT" } ]
      ].each_with_index do |(kind, age, read, data), i|
        notification = Notification.create!(
          recipient: admin, company: company, kind: kind, data: data, dedup_key: "parity-#{i}",
          url: kind == "system_update" ? "/admin/updates" : "/admin/clients", read_at: read ? (age - 1.minute).ago : nil
        )
        notification.update_columns(created_at: age.ago) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # The front desk (module 10): the default moderator role, which checks
    # people in and books them — so its home is the desk.
    def desk!(company)
      user = User.create!(first_name: "Ines", last_name: "Gharbi", email: DESK_EMAIL, password: PASSWORD, role: :staff, locale: "fr", email_verified_at: Time.current)
      company.staff_members.create!(user: user, assigned_role: company.roles.find_by!(key: "moderator"))
      user
    end

    def staff!(company)
      role = company.roles.create!(name: "Accueil", permissions: %w[clients contracts])
      user = User.create!(first_name: "Yasmine", last_name: "Trabelsi", email: STAFF_EMAIL, password: PASSWORD, role: :staff, locale: "fr")
      company.staff_members.create!(user: user, assigned_role: role)
      user
    end

    # The catalogue's packs, on the Lac salle (empty otherwise): two
    # activities, a third deactivated, two formules pricing them (one off
    # sale), and a pack sold under the first.
    def self.lac_catalogue!
      lac = lac_salle
      lac_empty!
      lac.update!(settings: { features: { packs: true } })
      yoga = lac.activities.create!(name: "Yoga Lac", emoji: "🧘", session_format: :collective, duration: 60, capacity: 12)
      pilates = lac.activities.create!(name: "Pilates Lac", emoji: "🤸", session_format: :small_group, duration: 45, capacity: 6)
      lac.activities.create!(name: "Aquagym", emoji: "🏊", session_format: :collective, duration: 45, capacity: 15, active: false)
      monthly = lac.contract_types.create!(name: "Mensuel Lac", billing_period: :monthly, unlimited_bookings: true, color: "#0369a1")
      carnet = lac.contract_types.create!(name: "Carnet Lac", billing_period: :custom, validity_days: 56, session_count: 10, unlimited_bookings: false, color: "#be185d")
      lac.contract_types.create!(name: "Ancienne formule", billing_period: :yearly, unlimited_bookings: true, color: "#64748b", active: false)
      monthly.contract_type_activities.create!(activity: yoga, price: 120)
      monthly.contract_type_activities.create!(activity: pilates, price: 150)
      carnet.contract_type_activities.create!(activity: yoga, price: 90.5)
      pack = CatalogueEditor.save_pack(lac.packs.new, lac, { name: "Duo Lac", description: "Yoga et Pilates" }, activity_ids: [ yoga.id, pilates.id ])
      monthly.contract_type_packs.create!(pack: pack, price: 230)
    end

    def self.lac_empty!
      lac = lac_salle
      lac.contract_types.each { |plan| plan.contract_type_activities.delete_all + plan.contract_type_packs.delete_all }
      lac.packs.destroy_all
      lac.contract_types.destroy_all
      lac.activities.destroy_all
      lac.update!(settings: { features: { packs: false }, onboarding: { completed: [], skipped: [] } })
    end

    # The Lac salle's first-time setup, at the activities step (the company
    # confirmed) or at the formules step (two activities as well).
    def self.lac_onboarding!(step)
      lac = lac_salle
      lac_empty!
      lac.update!(settings: { onboarding: { completed: [ "company" ], skipped: [] } })
      return if step == "activities"

      lac.activities.create!(name: "Yoga Lac", emoji: "🧘", session_format: :collective, duration: 60, capacity: 12)
      lac.activities.create!(name: "Pilates Lac", emoji: "🤸", session_format: :small_group, duration: 45, capacity: 6)
    end

    # The Lac salle's team (module 5): a coach with a bio and a birthday,
    # one without, one deactivated, and the salle's moderator — whose seat,
    # the only back-office role there, is then taken. No coach has a mobile
    # login here: Angular lists a coach's login twice (B-08), and these
    # states are the ones compared pixel for pixel.
    def self.lac_team!
      lac = lac_salle
      lac_team_empty!
      lac.coaches.create!(first_name: "Nadia", last_name: "Ayari", email: "nadia@lumenlac.tn", phone: "+216 22 410 700",
                          bio: "Pilates et mobilité, certifiée Stott.", birthdate: Date.new(1991, 3, 8))
      lac.coaches.create!(first_name: "Karim", last_name: "Mansour", email: "karim@lumenlac.tn", phone: "+216 25 118 302")
      lac.coaches.create!(first_name: "Olfa", last_name: "Bouaziz", phone: "+216 98 552 014", active: false)
      moderator = User.create!(first_name: "Hela", last_name: "Chaabane", email: "hela@lumenlac.tn", password: PASSWORD, role: :staff, locale: "fr", email_verified_at: Time.current)
      lac.staff_members.create!(user: moderator, assigned_role: lac.roles.find_by!(key: "moderator"), birthdate: Date.new(1988, 11, 2))
    end

    def self.lac_team_empty!
      lac = lac_salle
      users = User.where(id: lac.staff_members.pluck(:user_id))
      lac.staff_members.delete_all
      users.where.missing(:staff_members).where.missing(:companies).destroy_all
      lac.coaches.destroy_all
    end

    def self.lac_salle
      Company.find_by!(name: "Studio Lumen Lac")
    end
  end
end
