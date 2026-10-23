module Demo
  # "Salle Test Abonnements" — a gym to try the subscriptions pages on, with
  # one subscription in every state the desk meets: running, to renew (by
  # date and by sessions spent), expired (paid or still owed), unpaid,
  # paused, queued behind a renewal, starting later, cancelled, a renewal
  # chain with its history, a pack, and members with none at all. Fitora Pro,
  # paid for a year, so nothing locks it. Dates are relative to the day it is
  # built: rebuild it (bin/rails demo:abonnements) when they have drifted.
  class Abonnements
    ADMIN_EMAIL = "test@fitora.test".freeze
    DESK_EMAIL = "accueil@fitora.test".freeze
    SELLER_EMAIL = "vente@fitora.test".freeze
    PASSWORD = "test-abo-2026".freeze
    DOMAIN = "abonnements.test".freeze

    def self.build!
      admin = User.create!(first_name: "Test", last_name: "Abonnements", email: ADMIN_EMAIL, password: PASSWORD,
                           role: :admin, locale: "fr", email_verified_at: Time.current)
      company = Company.open!(
        admin: admin,
        attributes: { name: "Salle Test Abonnements", currency: "TND", timezone: "Africa/Tunis", locale: "fr",
                      city: "Tunis", country: "TN", address: "1 avenue Habib Bourguiba, Tunis", phone: "+216 71 000 000",
                      email: "contact@#{DOMAIN}" }
      )
      company.update!(setup_dismissed_at: Time.current, signatory_name: "Test Abonnements, gérant",
                      settings: { features: { packs: true, drop_in: true, waitlist: true } })
      pay_fitora_for_a_year(company)

      Time.use_zone(company.time_zone) do
        catalogue = build_catalogue(company)
        build_team(company)
        build_schedule(company, catalogue)
        build_members(company, admin, catalogue)
      end

      { app: "http://localhost:3000", admin: { email: ADMIN_EMAIL, password: PASSWORD },
        desk: { email: DESK_EMAIL, password: PASSWORD, role: "Modérateur — vend et encaisse" },
        seller: { email: SELLER_EMAIL, password: PASSWORD, role: "Vente — vend, n'encaisse pas" } }
    end

    # Fitora Pro, yearly, its invoice paid: what a superadmin does from the
    # console (SuperadminActions), so the trial never runs out under it.
    def self.pay_fitora_for_a_year(company)
      operator = User.find_by(role: :superadmin)
      SuperadminActions.update_subscription(company, { plan: "pro", billing_period: "yearly" }, by: operator)
      SuperadminActions.issue_invoice(company, by: operator, notes: "Compte de test")
    end

    def self.build_catalogue(company)
      activity = ->(name, emoji, format, capacity) { company.activities.create!(name: name, emoji: emoji, session_format: format, capacity: capacity, duration: 60) }
      muscu = activity.call("Musculation", "🏋️", :collective, 30)
      boxe = activity.call("Boxe", "🥊", :small_group, 8)
      yoga = activity.call("Yoga", "🧘", :collective, 15)

      plan = ->(name, period, color, **rest) { company.contract_types.create!(name: name, billing_period: period, color: color, unlimited_bookings: !rest.key?(:session_count), **rest) }
      mensuel = plan.call("Mensuel", :monthly, "#4f46e5")
      trimestriel = plan.call("Trimestriel", :quarterly, "#0f766e")
      annuel = plan.call("Annuel", :yearly, "#b45309")
      carte = plan.call("Carte 10 séances", :custom, "#be185d", validity_days: 60, session_count: 10)

      { [ mensuel, muscu ] => 60, [ mensuel, boxe ] => 70, [ mensuel, yoga ] => 55,
        [ trimestriel, muscu ] => 160, [ trimestriel, boxe ] => 190,
        [ annuel, muscu ] => 550,
        [ carte, boxe ] => 90, [ carte, yoga ] => 80 }.each do |(formule, covered), price|
        formule.contract_type_activities.create!(activity: covered, price: price)
      end

      combo = company.packs.create!(name: "Muscu + Boxe", activities: [ muscu, boxe ], description: "Les deux, un seul abonnement.")
      mensuel.contract_type_packs.create!(pack: combo, price: 110)
      trimestriel.contract_type_packs.create!(pack: combo, price: 300)

      { muscu: muscu, boxe: boxe, yoga: yoga, mensuel: mensuel, trimestriel: trimestriel, annuel: annuel, carte: carte, combo: combo }
    end

    # The desk (sells and collects) and a seller who may not take money —
    # to see the dialogs without "Encaisser".
    def self.build_team(company)
      seller_role = company.roles.create!(name: "Vente", permissions: %w[clients contracts bookings checkin])
      [ [ DESK_EMAIL, "Accueil", company.roles.find_by!(key: "moderator") ], [ SELLER_EMAIL, "Vente", seller_role ] ].each do |email, first, role|
        user = User.create!(first_name: first, last_name: "Test", email: email, password: PASSWORD, role: :staff,
                            locale: "fr", email_verified_at: Time.current)
        company.staff_members.create!(user: user, assigned_role: role, active: true)
      end
      company.coaches.create!(first_name: "Karim", last_name: "Coach", email: "karim.coach@#{DOMAIN}", phone: "+216 22 000 001")
    end

    # A month of classes around today, so bookings have somewhere to go.
    def self.build_schedule(company, catalogue)
      coach = company.coaches.first
      monday = Date.current.beginning_of_week(:monday)
      [ [ :muscu, [ 1, 2, 3, 4, 5, 6 ], "18:00" ], [ :boxe, [ 2, 4 ], "19:00" ], [ :yoga, [ 1, 3, 5 ], "08:00" ] ].each do |key, days, time|
        company.recurring_schedules.create!(activity: catalogue.fetch(key), coach: coach, weekdays: days, start_time: time,
                                            recurrence_type: :weekly, starts_on: monday - 7, ends_on: monday + 28)
               .tap(&:generate_sessions!)
      end
    end

    def self.build_members(company, admin, c)
      today = Date.current
      member = lambda do |first, last, joined_days_ago|
        client = Client.create!(first_name: first, last_name: last, phone: "+216 #{rand(20..99)} #{rand(100..999)} #{rand(100..999)}",
                                email: "#{first.downcase}.#{last.downcase.delete(' ')}@#{DOMAIN}")
        client.join!(company).update!(joined_at: joined_days_ago.days.ago)
        client
      end
      sell = lambda do |client, formule, covered, starts_on, paid: true, discount: 0, method: "cash"|
        Contract.sell!(client: client, contract_type: c.fetch(formule), created_by: admin, starts_on: starts_on, discount: discount,
                       activity: covered == :combo ? nil : c.fetch(covered), pack: covered == :combo ? c.fetch(:combo) : nil,
                       collect_payment: paid, payment_method: method)
      end

      # En cours, réglé.
      sell.call(member.call("Sami", "Ben Ali", 200), :mensuel, :muscu, today - 10)
      # À renouveler : finit dans 3 jours, réglé.
      sell.call(member.call("Lina", "Trabelsi", 150), :mensuel, :boxe, today - 27, method: "bank_transfer")
      # À renouveler et non réglé : finit dans 8 jours.
      sell.call(member.call("Youssef", "Ayari", 120), :trimestriel, :muscu, today - 82, paid: false)
      # Finit aujourd'hui.
      sell.call(member.call("Bilel", "Gasmi", 90), :mensuel, :boxe, today - 30)
      # Expiré il y a 5 jours, réglé : à relancer.
      sell.call(member.call("Amira", "Jebali", 180), :mensuel, :yoga, today - 35)
      # Expiré il y a 40 jours et jamais réglé : expiré et dû.
      sell.call(member.call("Karim", "Mejri", 300), :mensuel, :muscu, today - 70, paid: false)

      # Carte 10 séances toutes utilisées : à renouveler avant sa date.
      sell.call(member.call("Nour", "Hamdi", 60), :carte, :boxe, today - 20).update_columns(remaining_bookings: 0) # rubocop:disable Rails/SkipsModelValidations
      # Deux abonnements : musculation au mois, et une carte boxe entamée.
      fares = member.call("Fares", "Hammami", 100)
      sell.call(fares, :mensuel, :muscu, today - 5)
      sell.call(fares, :carte, :boxe, today - 12, paid: false).update_columns(remaining_bookings: 4) # rubocop:disable Rails/SkipsModelValidations

      # En pause depuis 6 jours (blessure).
      hela = sell.call(member.call("Hela", "Mansouri", 140), :mensuel, :yoga, today - 15)
      hela.pause!
      hela.update_columns(paused_at: 6.days.ago) # rubocop:disable Rails/SkipsModelValidations

      # Finit dans 2 jours, déjà renouvelé : le renouvellement attend son tour, non réglé.
      sell.call(member.call("Omar", "Dridi", 110), :mensuel, :muscu, today - 28).renew!(created_by: admin)

      # Pack Muscu + Boxe, non réglé.
      sell.call(member.call("Sonia", "Ferchichi", 45), :mensuel, :combo, today - 3, paid: false)
      # Annuel avec une remise de 50 DT.
      sell.call(member.call("Walid", "Kammoun", 400), :annuel, :muscu, today - 100, discount: 50, method: "bank_transfer")
      # Commence dans 5 jours.
      sell.call(member.call("Dorra", "Sfar", 2), :mensuel, :yoga, today + 5, paid: false)

      # Résilié : vendu par erreur, plus rien de dû.
      leila = member.call("Leila", "Ben Romdhane", 30)
      Contracts::Actions.cancel(sell.call(leila, :mensuel, :boxe, today - 10, paid: false), company: company, by: admin)

      # Fidèle depuis 4 mois : trois termes passés renouvelés en chaîne, le quatrième en cours.
      aziz = member.call("Aziz", "Trabelsi", 130)
      previous = nil
      [ 95, 65, 35, 5 ].each do |days_ago|
        term = sell.call(aziz, :mensuel, :muscu, today - days_ago)
        term.update_columns(renewed_from_id: previous&.id) # rubocop:disable Rails/SkipsModelValidations
        previous = term
      end

      # Sans abonnement : de quoi vendre depuis la fiche, ou depuis la liste.
      member.call("Mariem", "Zouari", 1)
      member.call("Mehdi", "Saidi", 0)
    end
    private_class_method :pay_fitora_for_a_year, :build_catalogue, :build_team, :build_schedule, :build_members

    # Takes the test gym back out, and only it: its admin and, through it,
    # the gym; its staff logins; its members (none belongs to another gym).
    def self.remove!
      admin = User.find_by(email: ADMIN_EMAIL)
      return if admin.nil?

      company_ids = admin.companies.ids
      member_ids = Membership.where(company_id: company_ids).pluck(:client_id)
      staff_user_ids = StaffMember.where(company_id: company_ids).pluck(:user_id) - [ admin.id ]
      admin.companies.each do |company|
        company.recurring_schedules.destroy_all
        company.sessions.destroy_all
        company.payments.destroy_all
        company.contracts.destroy_all
      end
      admin.reload.destroy!
      Client.where(id: member_ids).where.missing(:memberships).destroy_all
      User.where(id: staff_user_ids).where.missing(:staff_members).where.missing(:companies).destroy_all
    end
  end
end
