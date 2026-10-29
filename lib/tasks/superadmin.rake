# The console's second factor (TwoFactor) is set up here, on the server, and
# nowhere else: /superadmin/connexion only ever asks for a code. A sign-in
# page that set an app up after the password let whoever had the password
# bind their own; this needs the server as well.
#
# For a new superadmin, and when the phone that had it is lost or replaced:
# a new secret, shown here as a QR code, set up once the app's code proves it
# was scanned. Until then nothing changes — an app already set up keeps
# working. After, only the new app's codes are taken, and every session of
# that superadmin ends.
#
#   kamal app exec --interactive "bin/rails superadmin:setup_two_factor EMAIL=admin@fitora.tn"
namespace :superadmin do
  desc "Set up a superadmin's authenticator app from a QR code shown here (EMAIL=…)"
  task setup_two_factor: :environment do
    email = ENV["EMAIL"].to_s.downcase.strip.presence or abort("Name the superadmin: EMAIL=…")
    user = User.superadmin.find_by(email: email) or abort("No superadmin #{email}.")

    secret = TwoFactor.new_secret
    puts RQRCode::QRCode.new(TwoFactor.provisioning_uri(secret, user.email)).as_ansi
    puts "Scan it with the authenticator app, or type in this key: #{secret.scan(/.{1,4}/).join(" ")}"

    set_up = 3.times.any? do
      print "The 6-digit code the app shows now: "
      code = $stdin.gets or abort("\nNo code given: nothing changed.")
      user.enable_two_factor!(secret, code) or puts("That is not the app's code.")
    end
    abort("Nothing changed: start again.") unless set_up

    user.revoke_all_tokens!
    puts "Two-factor set up for #{email}: sign in at /superadmin/connexion with this app's codes."
  end

  # Its name from when the next sign-in set the app up.
  desc "Same as superadmin:setup_two_factor"
  task reset_two_factor: :setup_two_factor
end
