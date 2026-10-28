# The door: a member shows a card (its QR code, or its number typed in) and
# the desk sees at once whether they may come in — the visit is written
# down, and a gym with no classes at all finally knows who trains there.
#
# card_code is per gym, on the membership: the same person at two gyms has
# two cards, and one gym's scanner never finds another gym's member. Eight
# digits, so it can be typed on a keypad when the card is forgotten.
class AddMemberCardsAndVisits < ActiveRecord::Migration[8.1]
  def up
    add_column :memberships, :card_code, :string
    add_index :memberships, %i[company_id card_code], unique: true, where: "card_code IS NOT NULL"

    # Every membership that exists gets its card now, so no member has to be
    # opened and saved before the desk can scan them.
    execute <<~SQL
      UPDATE memberships SET card_code = codes.code
        FROM (
          SELECT id, lpad((10000000 + floor(random() * 89999999))::bigint::text, 8, '0') AS code FROM memberships
        ) AS codes
       WHERE memberships.id = codes.id
    SQL
    # random() can draw the same number twice in one gym; those draw again
    # until none clash.
    loop do
      clashes = execute(<<~SQL).cmd_tuples
        UPDATE memberships SET card_code = lpad((10000000 + floor(random() * 89999999))::bigint::text, 8, '0')
         WHERE id IN (
           SELECT id FROM (
             SELECT id, row_number() OVER (PARTITION BY company_id, card_code ORDER BY created_at) AS n FROM memberships
           ) ranked WHERE n > 1
         )
      SQL
      break if clashes.zero?
    end

    create_table :visits, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true, index: false
      t.references :client, type: :uuid, null: false, foreign_key: true, index: false
      t.references :contract, type: :uuid, foreign_key: true
      t.references :checked_in_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :checked_in_at, null: false
      # Let in although the desk was told not to (expired, unpaid…), and why.
      t.boolean :forced, null: false, default: false
      t.string :reason
      # Whether the visit took a session off a counted formule, so undoing
      # it gives the session back.
      t.boolean :consumed_session, null: false, default: false
      t.timestamps
    end
    add_index :visits, %i[company_id checked_in_at]
    add_index :visits, %i[client_id checked_in_at]
  end

  def down
    drop_table :visits
    remove_index :memberships, %i[company_id card_code]
    remove_column :memberships, :card_code
  end
end
