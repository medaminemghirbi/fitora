# Fitora's invoices to the gyms, written out as a Tunisian invoice must be:
# who issues it (raison sociale, address, matricule fiscal, contact), and
# the price — TTC, as it always was — split into HT, TVA and the timbre
# fiscal.
#
# - platform_settings: Fitora's identity, the TVA rate (19 %) and the timbre
#   (1,000 DT), which the superadmin keeps up to date in the console.
# - invoices: the TVA rate and the timbre an invoice was issued with, frozen
#   with it like its amount (nil / 0 outside dinars: TVA not applicable), and
#   who issued it, once Fitora's identity is complete.
#
# The invoices already issued were TTC at the same terms: those in dinars,
# for an amount, get them.
class InvoiceTaxTerms < ActiveRecord::Migration[8.1]
  def change
    change_table :platform_settings, bulk: true do |t|
      t.string :legal_name
      t.string :address
      t.string :city
      t.string :tax_id
      t.string :phone
      t.string :email
      t.string :website
      t.decimal :vat_percent, precision: 5, scale: 2, null: false, default: 19
      t.integer :stamp_duty_millimes, null: false, default: 1_000
    end

    change_table :invoices, bulk: true do |t|
      t.decimal :vat_percent, precision: 5, scale: 2
      t.integer :stamp_duty_millimes, null: false, default: 0
      t.jsonb :issuer
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE invoices SET vat_percent = 19, stamp_duty_millimes = 1000
          WHERE currency = 'TND' AND amount_cents > 0
        SQL
      end
    end
  end
end
