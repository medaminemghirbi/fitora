# A salle's invoice counter is nothing without the salle: deleting the salle
# deletes it. The foreign key refused instead, so no salle that had ever
# sold a subscription could be deleted — rebuilding the demo studio
# (Demo::StudioLumen.remove!) among them. Nothing references the counter.
class CascadeContractInvoiceSequences < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :contract_invoice_sequences, :companies
    add_foreign_key :contract_invoice_sequences, :companies, on_delete: :cascade
  end
end
