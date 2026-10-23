require_relative "demo/studio_lumen"
require_relative "demo/abonnements"

# Studio Lumen, the demo studio (lib/tasks/demo/studio_lumen.rb). Two ways
# to get it, neither of them ever in production:
#
#   bin/rails demo:local
#     Into your local development database, beside whatever is already
#     there. Re-running it rebuilds Studio Lumen and nothing else.
#
#   DATABASE_URL=postgres:///backend_demo bin/rails db:prepare demo:seed
#     A database of its own, emptied first — the clean slate to present on.
#
# And a gym to test the subscriptions pages on, beside the rest:
#
#   bin/rails demo:abonnements
#
# Logins go to tmp/demo.json.
namespace :demo do
  desc "Add (or rebuild) Studio Lumen in the local development database — development only"
  task local: :environment do
    abort("demo:local only runs in development (RAILS_ENV is #{Rails.env}).") unless Rails.env.development?

    fixtures = ActiveRecord::Base.transaction do
      Demo::StudioLumen.remove!
      Demo::StudioLumen.build!
    end
    Demo::StudioLumen.announce(fixtures)
  end

  desc "Add (or rebuild) Salle Test Abonnements — every subscription state, to try the subscriptions pages on — development only"
  task abonnements: :environment do
    abort("demo:abonnements only runs in development (RAILS_ENV is #{Rails.env}).") unless Rails.env.development?

    logins = ActiveRecord::Base.transaction do
      Demo::Abonnements.remove!
      Demo::Abonnements.build!
    end
    company = Company.joins(:admin).find_by!(users: { email: Demo::Abonnements::ADMIN_EMAIL })
    puts "Salle Test Abonnements ready — #{company.memberships.count} members, #{company.contracts.count} subscriptions."
    puts JSON.pretty_generate(logins)
  end

  desc "Reset the demo database to Studio Lumen (DATABASE_URL must name a *_demo database)"
  task seed: :environment do
    abort("demo:seed never runs in production.") if Rails.env.production?

    database = ActiveRecord::Base.connection_db_config.database.to_s
    abort("Refusing to seed #{database.inspect}: the demo seed only runs on a database named *_demo.") unless database.end_with?("_demo")

    connection = ActiveRecord::Base.connection
    tables = connection.tables - %w[schema_migrations ar_internal_metadata]
    connection.execute("TRUNCATE #{tables.map { |t| connection.quote_table_name(t) }.join(', ')} RESTART IDENTITY CASCADE")
    # Subscription prices and platform settings: the admin's own pages read them.
    Rails.application.load_seed

    Demo::StudioLumen.announce(Demo::StudioLumen.build!)
  end
end
