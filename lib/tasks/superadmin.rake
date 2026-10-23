# The console's second factor (TwoFactor), when the phone that had it is
# lost or replaced: turned off for that superadmin, whose sessions end; the
# next sign-in at /superadmin/connexion sets up an app again, from a new QR
# code. Needs the server — the console itself has no way round its own door.
#
#   bin/rails superadmin:reset_two_factor EMAIL=admin@fitora.tn
namespace :superadmin do
  desc "Turn off a superadmin's authenticator app, to set it up again (EMAIL=…)"
  task reset_two_factor: :environment do
    email = ENV["EMAIL"].to_s.downcase.strip.presence or abort("Name the superadmin: EMAIL=…")
    user = User.superadmin.find_by(email: email) or abort("No superadmin #{email}.")

    user.disable_two_factor!
    user.revoke_all_tokens!
    puts "Two-factor turned off for #{email}: the next sign-in at /superadmin/connexion sets it up again."
  end
end
