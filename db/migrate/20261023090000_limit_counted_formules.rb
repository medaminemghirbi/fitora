# A counted formule saved from the formule form carried its count in
# session_count alone, and booking_limit — what a sale counts down — stayed
# empty, so "Carte 10 séances" sold with no limit at all
# (ContractType#limit_bookings_to_session_count keeps them together now).
#
# Those formules get their limit, and the terms sold under them that are
# still running get what is left of it: the count, less the seats they took
# (a confirmed, completed or no-show booking spent one; Session#take_seat!).
class LimitCountedFormules < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      WITH fixed AS (
        UPDATE contract_types
           SET booking_limit = session_count, updated_at = now()
         WHERE unlimited_bookings = false AND booking_limit IS NULL AND session_count IS NOT NULL
        RETURNING id, booking_limit
      )
      UPDATE contracts
         SET remaining_bookings = GREATEST(fixed.booking_limit - (
               SELECT COUNT(*) FROM bookings
                WHERE bookings.contract_id = contracts.id AND bookings.status IN (0, 2, 3)
             ), 0),
             updated_at = now()
        FROM fixed
       WHERE contracts.contract_type_id = fixed.id
         AND contracts.remaining_bookings IS NULL
         AND contracts.status IN (0, 1)
    SQL
  end

  def down
    # The limits are what the gyms typed; nothing to put back.
  end
end
