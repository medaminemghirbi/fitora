# The account that runs the console, created once: as soon as a superadmin
# exists this does nothing, whatever the environment says, so no deploy can reset
# a password or add a second account.
#
# In production its address and first password must come from SUPERADMIN_EMAIL and
# SUPERADMIN_PASSWORD: no password written in this repository ever opens a real
# console. Elsewhere they default to a local account. The console then asks for an
# authenticator's code, set up on the server (lib/tasks/superadmin.rake).
unless User.superadmin.exists?
  defaults = Rails.env.production? ? {} : { email: "admin@fitora.test", password: "password123" }
  email = ENV["SUPERADMIN_EMAIL"].presence || defaults[:email]
  password = ENV["SUPERADMIN_PASSWORD"].presence || defaults[:password]
  raise "No superadmin yet: set SUPERADMIN_EMAIL and SUPERADMIN_PASSWORD for this first deploy." if email.blank? || password.blank?

  User.create!(first_name: "Fitora", last_name: "Superadmin", email: email, password: password, role: :superadmin, locale: "fr")
  puts "Superadmin #{email} created. Set up its authenticator app, then sign in at /superadmin/connexion:"
  puts "  bin/rails superadmin:setup_two_factor EMAIL=#{email}"
end
