require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Receipts
  # Fitora's invoice to a gym, for one period of access, laid out as a
  # Tunisian invoice: the issuer — raison sociale, address, matricule
  # fiscal, contact — beside the date and number and the client; the line;
  # then the price, TTC as it always was, split into HT, TVA and timbre
  # fiscal, and the total written out. Outside dinars there is neither TVA
  # nor timbre.
  #
  # The counterpart of ContractPdf, which invoices a gym's member. Rendered
  # on demand, never stored: the Invoice row holds everything — the amount,
  # its tax terms and its issuer, frozen at issue (Invoice#totals,
  # #issuer_details).
  class SubscriptionInvoicePdf
    INK = "1A1330".freeze
    GREY = "6B6386".freeze
    ACCENT = "4A2A8F".freeze
    RULE = "1A1330".freeze
    SHADE = "EFECF6".freeze

    LABEL_BY_PERIOD = { "monthly" => "mensuel", "yearly" => "annuel" }.freeze
    PLAN_LABELS = { "starter" => "Starter", "pro" => "Pro" }.freeze
    MONTHS = %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre].freeze
    # Figures after the decimal comma: millimes in dinars, none in CFA francs.
    DECIMALS = Hash.new(2).merge("TND" => 3, "XOF" => 0).freeze

    def self.call(invoice:)
      new(invoice: invoice).call
    end

    def initialize(invoice:)
      @invoice = invoice
      # Billed to the account, headed by its first salle.
      @company = invoice.billing_company
      @admin = invoice.admin
      @issuer = invoice.issuer_details
      @totals = invoice.totals
    end

    def call
      Prawn::Document.new(page_size: "A4", margin: [ 40, 40, 52, 40 ], info: { Title: "Facture #{invoice.number}", Creator: "Fitora" }) do |pdf|
        @pdf = pdf
        header
        pdf.move_down 26
        boxes
        pdf.move_down 24
        lines
        pdf.move_down 16
        amounts
        pdf.move_down 16
        in_words
        settlement
        footer
      end.render
    end

    private

    attr_reader :pdf, :invoice, :company, :admin, :issuer, :totals

    # Who issues it, on the left; how to reach them, on the right.
    def header
      top = pdf.cursor
      half = pdf.bounds.width / 2

      pdf.bounding_box([ 0, top ], width: half) do
        pdf.text clean(issuer["legal_name"] || "Fitora"), size: 13, style: :bold, color: ACCENT
        pdf.move_down 3
        [ issuer["address"], issuer["city"] ].compact.each { |line| pdf.text clean(line), size: 9.5, color: INK, leading: 2 }
        labelled("Matricule fiscal", issuer["tax_id"]) if issuer["tax_id"]
      end
      left_bottom = pdf.cursor

      pdf.bounding_box([ half, top ], width: half) do
        labelled("Tél", issuer["phone"], align: :right) if issuer["phone"]
        labelled("E-mail", issuer["email"], align: :right) if issuer["email"]
        labelled("Site", issuer["website"], align: :right) if issuer["website"]
      end
      pdf.move_cursor_to [ left_bottom, pdf.cursor ].min
    end

    def labelled(label, value, align: :left)
      pdf.formatted_text [ { text: "#{label} : ", color: GREY }, { text: clean(value), color: INK } ], size: 9.5, align: align, leading: 2
    end

    # The date and the number on the left, the client on the right — two
    # ruled boxes, as the paper form has them.
    def boxes
      top = pdf.cursor
      width = pdf.bounds.width * 0.46

      pdf.bounding_box([ 0, top ], width: width) do
        pdf.table([ [ "Date", fr_short(invoice.issued_at.to_date) ], [ "Facture", invoice.number ] ],
                  width: width, column_widths: [ 70, width - 70 ],
                  cell_style: { size: 10, padding: [ 7, 8 ], border_width: 1.2, border_color: RULE, text_color: INK }) do |t|
          t.column(0).font_style = :bold
          t.column(1).text_color = ACCENT
          t.row(1).size = 14
          t.row(1).column(0).size = 13
        end
      end
      left_bottom = pdf.cursor

      pdf.bounding_box([ pdf.bounds.width - width, top ], width: width) do
        client = [ company&.name, admin&.full_name, company&.address, [ company&.city, company&.country ].compact_blank.join(", "), company&.email ]
        pdf.table([ [ "Client" ], [ client.compact_blank.map { |line| clean(line) }.join("\n") ] ],
                  width: width, cell_style: { size: 9.5, padding: [ 6, 8 ], border_width: 1.2, border_color: RULE, text_color: INK, leading: 2 }) do |t|
          t.row(0).font_style = :bold
          t.row(0).size = 12
          t.row(0).align = :center
          t.row(0).background_color = SHADE
        end
      end
      pdf.move_cursor_to [ left_bottom, pdf.cursor ].min
    end

    # One line: the plan and the period it covers, at its HT price.
    def lines
      header = [ "Désignation", "Prix unitaire HT", "Quantité", "Total HT" ]
      row = [ { content: "#{designation}\n<font size='8.5'><color rgb='#{GREY}'>#{period}</color></font>", inline_format: true },
              money(totals.ht), "1", money(totals.ht) ]

      pdf.table([ header, row ], width: pdf.bounds.width, column_widths: column_widths,
                cell_style: { size: 10, padding: [ 8, 8 ], border_width: 1.2, border_color: RULE, text_color: INK }) do |t|
        t.row(0).font_style = :bold
        t.row(0).align = :center
        t.row(0).background_color = SHADE
        t.row(1).columns(1..3).align = :center
        t.row(1).columns(1..3).valign = :center
      end
    end

    # Total HT, the TVA on it and the timbre, then the TTC apart — the
    # figures under the line's own Total column.
    def amounts
      label_width = pdf.bounds.width - column_widths.last
      rows = [ [ "Total HT", money(totals.ht) ] ]
      if totals.vat_percent
        rows << [ "TVA #{percent(totals.vat_percent)} %", money(totals.vat) ]
        rows << [ "Timbre fiscal", money(totals.stamp) ] if totals.stamp.positive?
      else
        rows << [ "TVA", "Non applicable" ]
      end
      style = { size: 10.5, padding: [ 7, 8 ], border_width: 1.2, border_color: RULE, text_color: INK }

      pdf.table(rows, width: pdf.bounds.width, column_widths: [ label_width, column_widths.last ], cell_style: style) do |t|
        t.column(0).font_style = :bold
        t.column(1).align = :right
      end
      pdf.move_down 10
      pdf.table([ [ "Total TTC", money(totals.ttc) ] ], width: pdf.bounds.width, column_widths: [ label_width, column_widths.last ],
                cell_style: style.merge(size: 12, font_style: :bold, background_color: SHADE)) do |t|
        t.column(1).align = :right
        t.column(1).text_color = ACCENT
      end
    end

    # The total written out, as a Tunisian invoice states it.
    def in_words
      return unless invoice.currency == "TND"

      pdf.formatted_text [ { text: "Arrêtée la présente facture à la somme de : ", color: GREY },
                           { text: "#{AmountInWords.dinars(totals.ttc)} TTC.", color: INK, styles: [ :bold ] } ], size: 9.5
      pdf.move_down 8
    end

    def settlement
      lines =
        if invoice.trial?
          [ "Période d'essai offerte : aucun montant dû." ]
        elsif invoice.paid?
          [ "Facture réglée le #{fr_long(invoice.paid_at.to_date)}#{" (paiement confirmé par #{invoice.issued_by.full_name})" if invoice.issued_by}." ]
        else
          # A change of plan's bill, waiting for the money.
          [ "Facture à régler." ]
        end
      lines << invoice.notes if invoice.notes.present?
      pdf.text clean(lines.join(" ")), size: 9, color: GREY, leading: 3
    end

    def footer
      pdf.repeat(:all) do
        pdf.fill_color GREY
        pdf.draw_text clean("#{issuer["legal_name"] || "Fitora"} · #{invoice.number}"), at: [ 0, -24 ], size: 8
        pdf.fill_color "000000"
      end
      pdf.number_pages "Page <page> / <total>", at: [ pdf.bounds.right - 80, -16 ], width: 80, align: :right, size: 8, color: GREY
    end

    def column_widths
      width = pdf.bounds.width
      [ width - 300, 110, 80, 110 ]
    end

    def designation
      return "Abonnement Fitora, période d'essai" if invoice.trial?

      "Abonnement Fitora #{PLAN_LABELS.fetch(invoice.plan, invoice.plan)}, #{LABEL_BY_PERIOD.fetch(invoice.billing_period, invoice.billing_period)}"
    end

    # PDF's built-in fonts are WinAnsi: an arrow or an em-dash raises rather
    # than degrading, so the range is spelled out in words.
    def period
      "Période du #{fr_long(invoice.period_start)} au #{fr_long(invoice.period_end)}"
    end

    # An amount in thousandths of the invoice's currency: "137,815 DT",
    # "1 250,00 €".
    def money(thousandths)
      decimals = DECIMALS[invoice.currency]
      whole, fraction = format("%.#{decimals}f", (BigDecimal(thousandths) / 1000).round(decimals)).split(".")
      whole = whole.reverse.scan(/\d{1,3}/).join(" ").reverse
      "#{[ whole, fraction ].compact.join(",")} #{clean(CurrencyCatalog.symbol(invoice.currency))}"
    end

    def percent(value)
      value.to_d.to_s("F").delete_suffix(".0").tr(".", ",")
    end

    def fr_short(date) = date.strftime("%d/%m/%Y")

    def fr_long(date) = "#{date.day} #{MONTHS[date.month - 1]} #{date.year}"

    # The built-in fonts know WinAnsi only: anything else (a name in Arabic)
    # is a question mark, not an invoice that fails to download.
    def clean(text)
      text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
    end
  end
end
