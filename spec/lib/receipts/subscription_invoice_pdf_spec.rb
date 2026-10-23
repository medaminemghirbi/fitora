require "rails_helper"

RSpec.describe Receipts::SubscriptionInvoicePdf do
  let(:admin) { create(:user, :admin, first_name: "Sami", last_name: "Trabelsi") }
  let(:company) { create(:company, admin: admin, name: "Atlas Fitness", address: "12 avenue Habib Bourguiba", city: "Sousse") }

  # The text the PDF draws: Prawn writes it as hex strings, split for
  # kerning, in the built-in fonts' WinAnsi.
  def text_of(pdf)
    pdf.scan(/\[(.*?)\]\s*TJ|<(\h*)>\s*Tj/m).map { |array, single|
      (array ? array.scan(/<(\h*)>/).flatten : [ single ]).map { |hex| [ hex ].pack("H*") }.join
    }.join("\n").force_encoding("Windows-1252").encode("UTF-8")
  end

  before do
    PlatformSetting.current.update!(legal_name: "Fitora SARL", address: "Les Berges du Lac", city: "1053 Tunis",
                                    tax_id: "1234567/A/M/000", phone: "+216 71 000 000", email: "facturation@fitora.tn", website: "www.fitora.tn")
  end

  it "lays out a Tunisian invoice: issuer and matricule fiscal, client, the line in HT, TVA, timbre and the TTC in words" do
    invoice = create(:invoice, company: company, number: "FIT-2026-0042", amount_cents: 16_500, currency: "TND")

    text = text_of(described_class.call(invoice: invoice))

    expect(text).to include("Fitora SARL", "Matricule fiscal : ", "1234567/A/M/000", "+216 71 000 000", "www.fitora.tn",
                            "Facture", "FIT-2026-0042", "Client", "Atlas Fitness", "Sami Trabelsi", "12 avenue Habib Bourguiba",
                            "Abonnement Fitora Starter, mensuel", "137,815 DT", "TVA 19 %", "26,185 DT", "Timbre fiscal", "1,000 DT",
                            "Total TTC", "165,000 DT", "Cent soixante-cinq dinars TTC.")
  end

  it "says TVA does not apply to an invoice in another currency, and adds no timbre" do
    company.update!(currency: "EUR")
    invoice = create(:invoice, company: company, amount_cents: 64_800, currency: "EUR")

    text = text_of(described_class.call(invoice: invoice))

    expect(text).to include("648,00 €", "Non applicable")
    expect(text).not_to include("Timbre fiscal", "Arrêtée")
  end

  it "prints a name its fonts cannot draw rather than failing" do
    company.update!(name: "نادي أطلس")
    invoice = create(:invoice, company: company)

    expect { described_class.call(invoice: invoice) }.not_to raise_error
  end

  it "fits on one page" do
    pdf = described_class.call(invoice: create(:invoice, company: company, notes: "Virement reçu"))
    expect(pdf.scan(%r{/Type /Page\b}).size).to eq(1)
  end
end
