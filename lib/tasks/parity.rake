require_relative "demo/studio_lumen"
require_relative "parity/fixtures"

# The data the parity suite runs on (test/parity, MIGRATION_AUDIT §12): never
# in production, and only into a database named *_demo, like demo:seed.
#
#   export DATABASE_URL=postgres:///backend_parity_demo FITORA_FROZEN_TIME=2026-10-14T10:00:00+01:00
#   bin/rails db:prepare parity:seed
#   bin/rails "parity:state[trial_3]"
namespace :parity do
  desc "Reset the parity database: Studio Lumen plus the parity fixtures (tmp/parity.json)"
  task seed: :environment do
    Rake::Task["demo:seed"].invoke
    Parity::Fixtures.build!
    puts "Parity fixtures ready — logins and salle ids in tmp/parity.json"
  end

  # The states a screenshot needs that the data alone does not give.
  #   trial_14 / trial_3 / trial_0   — free days left on the admin's trial
  #   lock / unlock                  — the admin's account closed or open
  #   tokens                         — fresh emailed-link tokens per app (tmp/parity-tokens.json)
  #   resend_ready                   — the pending admin may be sent the link again
  #   locale_fr / locale_ar / locale_en — the salles' own language, which the
  #                                       Angular app re-applies on every load
  #   lac_catalogue / lac_empty      — the Lac salle with packs on and a small
  #                                    priced catalogue, or empty again
  #   lac_onboarding_activities / lac_onboarding_plans — the Lac salle's setup
  #                                    flow at that step (reset: lac_empty)
  #   pro / pro_off                  — the admin's account on a paid Pro period,
  #                                    or back on its trial
  #   lac_team / lac_team_empty      — the Lac salle with a team (a moderator
  #                                    among them), or none
  desc "Put the parity database in a named state"
  task :state, [ :name ] => :environment do |_, args|
    abort("parity:state never runs in production.") if Rails.env.production?
    abort("parity:state only runs on a *_demo database.") unless ActiveRecord::Base.connection_db_config.database.to_s.end_with?("_demo")

    admin = User.find_by!(email: Demo::StudioLumen::ADMIN_EMAIL)
    case args[:name]
    when /\Atrial_(\d+)\z/
      days = Regexp.last_match(1).to_i
      # The whole free period moves, so it still lasts its 14 days.
      invoice = admin.subscription.invoices.where(trial: true).order(:period_end).last
      period_end = Date.current + (days - 1)
      invoice.update!(period_start: period_end - (Subscription::TRIAL_DAYS - 1), period_end: period_end)
    when "tokens"
      Parity::Fixtures.tokens!
    when "resend_ready"
      # The clock is stopped, so a cool-down would never run out by itself.
      User.find_by!(email: Parity::Fixtures::PENDING_EMAIL).update!(email_verification_sent_at: nil)
    when "lock", "unlock"
      admin.subscription.update!(active: args[:name] == "unlock")
    when /\Alocale_(fr|en|ar)\z/
      admin.companies.update_all(locale: Regexp.last_match(1)) # rubocop:disable Rails/SkipsModelValidations
    when "lac_catalogue"
      Parity::Fixtures.lac_catalogue!
    when "lac_empty"
      Parity::Fixtures.lac_empty!
    when "pro"
      # A paid Pro period after the trial: Pro's tools open.
      subscription = admin.subscription
      subscription.update!(plan: "pro")
      subscription.issue_invoice!(issued_by: User.find_by!(role: :superadmin)) unless subscription.pro_features?
      # The mobile app's keys exist before either app asks (they are made
      # on first read, and two reads at once would make two).
      admin.companies.each(&:ensure_app_keys!)
    when "pro_off"
      subscription = admin.subscription
      subscription.invoices.where(trial: false).destroy_all
      subscription.update!(plan: nil)
    when "lac_team"
      Parity::Fixtures.lac_team!
    when "lac_team_empty"
      Parity::Fixtures.lac_team_empty!
    when /\Alac_onboarding_(activities|plans)\z/
      Parity::Fixtures.lac_onboarding!(Regexp.last_match(1))
    else
      abort("unknown state #{args[:name].inspect}")
    end
    puts "parity state: #{args[:name]}"
  end
end
