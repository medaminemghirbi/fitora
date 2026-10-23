# One price per plan, in the currency the superadmin chooses, converted for
# every gym into its own (SubscriptionPrice.for, ExchangeRate.convert) —
# where a currency seen for the first time used to copy the reference
# price as a bare number (165 TND became 165 €).
#
# - platform_settings.price_currency: what the prices are set in. TND, the
#   old reference currency, so the prices in force today stay as they are.
# - exchange_rates: how many units of each currency one euro buys,
#   refreshed nightly (RefreshExchangeRatesJob).
class PriceInOneCurrency < ActiveRecord::Migration[8.1]
  def change
    add_column :platform_settings, :price_currency, :string, null: false, default: "TND"

    create_table :exchange_rates, id: :uuid do |t|
      t.string :currency, null: false
      t.decimal :per_eur, precision: 20, scale: 10, null: false
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :exchange_rates, :currency, unique: true
  end
end
