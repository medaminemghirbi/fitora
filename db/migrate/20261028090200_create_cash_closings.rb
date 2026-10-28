# The end of a shift at the desk: what the cash drawer should hold (the
# cash payments that login took that day, less the cash it gave back), what
# was counted in it, and the difference — one per login, per salle, per day.
class CreateCashClosings < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_closings, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true, index: false
      t.references :closed_by, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.date :business_date, null: false
      t.decimal :expected_cash, precision: 10, scale: 2, null: false
      t.decimal :counted_cash, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.text :notes
      t.timestamps
    end
    add_index :cash_closings, %i[company_id closed_by_id business_date], unique: true
    add_index :cash_closings, %i[company_id business_date]
  end
end
