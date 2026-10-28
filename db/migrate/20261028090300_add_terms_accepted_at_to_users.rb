# When the admin accepted Fitora's terms and privacy policy at sign-up.
# Accounts opened before the terms existed have none.
class AddTermsAcceptedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :terms_accepted_at, :datetime
  end
end
