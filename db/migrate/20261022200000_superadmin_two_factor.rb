# The superadmin console's second factor (TwoFactor): an authenticator app's
# six-digit codes, asked for after the password at /superadmin/connexion.
#
# - otp_secret_ciphertext: the app's secret, encrypted (never stored plain);
# - otp_enabled_at: when the app was set up — nil, it is set up at the next
#   sign-in;
# - otp_last_used_at: the time step of the last code accepted, so no code
#   is accepted twice.
#
# Every superadmin session open now ends (token_version moves on): the next
# sign-in is the first with two factors.
class SuperadminTwoFactor < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.text :otp_secret_ciphertext
      t.datetime :otp_enabled_at
      t.datetime :otp_last_used_at
    end

    reversible do |dir|
      dir.up { execute "UPDATE users SET token_version = token_version + 1 WHERE role = 2" }
    end
  end
end
