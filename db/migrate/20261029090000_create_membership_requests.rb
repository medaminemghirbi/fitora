# A gym asking to add someone who is already on Fitora — a member of another
# gym, or someone with their own login. Until the person accepts from the
# emailed link there is no membership: the gym holds only what it typed
# itself, and sees nothing another gym recorded (MembershipRequest).
class CreateMembershipRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :membership_requests, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true, index: false
      t.references :client, type: :uuid, null: false, foreign_key: true
      t.references :requested_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      # What the gym typed: the person's name and phone as it knows them, and
      # what it wrote for its own membership (Membership::PROFILE_FIELDS, notes).
      t.jsonb :person, null: false, default: {}
      t.jsonb :membership, null: false, default: {}
      t.string :token_digest, null: false
      t.datetime :sent_at, null: false
      t.timestamps
    end
    add_index :membership_requests, %i[company_id client_id], unique: true
    add_index :membership_requests, :token_digest, unique: true
    add_index :membership_requests, %i[company_id sent_at]
  end
end
