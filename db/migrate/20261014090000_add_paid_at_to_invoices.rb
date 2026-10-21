# An invoice can now be issued before the money arrives: a change of plan
# bills the account at once (an invoice "to pay"), and "payment received"
# settles it. paid_at says which is which. Every invoice before this one
# recorded money that had arrived, so each is paid as of its issue.
class AddPaidAtToInvoices < ActiveRecord::Migration[8.1]
  def up
    add_column :invoices, :paid_at, :datetime
    execute "UPDATE invoices SET paid_at = issued_at"
    add_index :invoices, [ :subscription_id, :paid_at ]
  end

  def down
    execute "DELETE FROM invoices WHERE paid_at IS NULL"
    remove_index :invoices, [ :subscription_id, :paid_at ]
    remove_column :invoices, :paid_at
  end
end
