# The gym's matricule fiscal, printed on every receipt it hands a member —
# a Tunisian invoice without it is not one.
class AddTaxIdToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :tax_id, :string
  end
end
