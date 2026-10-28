require "prawn"

module Receipts
  # A member's card, the size of a bank card (85.6 × 54 mm), to print and
  # hand over — or to send them as a PDF: the gym's name (its logo on Pro),
  # the member's face and name, and the QR code the desk scans, with its
  # number written under it for the day the card is left at home.
  class MemberCardPdf
    WIDTH = 242.65
    HEIGHT = 153.07
    PAD = 10
    QR_SIZE = 78
    INK = "1A1330".freeze
    GREY = "6B6386".freeze
    DEFAULT_BRAND = "4A2A8F".freeze

    def self.call(membership:)
      new(membership: membership).call
    end

    def initialize(membership:)
      @membership = membership
      @company = membership.company
      @client = membership.client
    end

    def call
      Prawn::Document.new(page_size: [ WIDTH, HEIGHT ], margin: 0) do |pdf|
        band(pdf)
        face(pdf)
        identity(pdf)
        qr(pdf)
      end.render
    end

    private

    attr_reader :membership, :company, :client

    # The top band in the gym's colour, its logo or its name on it.
    def band(pdf)
      pdf.fill_color brand_color
      pdf.fill_rectangle [ 0, HEIGHT ], WIDTH, 34
      pdf.fill_color "FFFFFF"
      if (logo = PrintableImage.io(company.brand_logo))
        pdf.image logo, at: [ PAD, HEIGHT - 5 ], fit: [ 90, 24 ]
      else
        pdf.text_box company.name, at: [ PAD, HEIGHT - 9 ], width: WIDTH - 2 * PAD - 60, height: 18,
                                   size: 12, style: :bold, overflow: :shrink_to_fit
      end
      pdf.text_box "CARTE MEMBRE", at: [ WIDTH - PAD - 70, HEIGHT - 13 ], width: 70, size: 6.5, align: :right,
                                   character_spacing: 0.8
      pdf.fill_color "000000"
    end

    def face(pdf)
      return unless photo?

      pdf.image StringIO.new(photo_bytes), at: [ PAD, HEIGHT - 42 ], fit: [ 52, 64 ]
    end

    def identity(pdf)
      left = photo? ? PAD + 60 : PAD
      width = WIDTH - QR_SIZE - PAD * 2 - left
      pdf.fill_color INK
      pdf.text_box client.full_name, at: [ left, HEIGHT - 46 ], width: width, height: 30, size: 11, style: :bold,
                                     overflow: :shrink_to_fit, leading: 1
      pdf.fill_color GREY
      since = membership.joined_at && "Membre depuis #{membership.joined_at.to_date.strftime('%m/%Y')}"
      details = [ since, company.city.presence ].compact.join("\n")
      pdf.text_box details, at: [ left, HEIGHT - 80 ], width: width, size: 7, leading: 2
      pdf.fill_color "000000"
    end

    # The QR code, drawn module by module (no image to decode), and its
    # number under it.
    def qr(pdf)
      code = membership.card_code.to_s
      return if code.empty?

      modules = RQRCode::QRCode.new(code, level: :m).modules
      cell = QR_SIZE.to_f / modules.size
      x0 = WIDTH - PAD - QR_SIZE
      y0 = HEIGHT - 42
      pdf.fill_color INK
      modules.each_with_index do |row, y|
        row.each_with_index do |dark, x|
          pdf.fill_rectangle [ x0 + x * cell, y0 - y * cell ], cell, cell if dark
        end
      end
      pdf.text_box code.scan(/.{1,4}/).join(" "), at: [ x0 - 6, y0 - QR_SIZE - 4 ], width: QR_SIZE + 12, size: 9,
                                                  align: :center, style: :bold, character_spacing: 1
      pdf.fill_color "000000"
    end

    # The photo, read once: nil when there is none Prawn can draw.
    def photo_bytes
      return @photo_bytes if defined?(@photo_bytes)

      @photo_bytes = PrintableImage.io(membership.photo)&.read
    end

    def photo?
      photo_bytes.present?
    end

    # The gym's colour on Pro, Fitora's otherwise — as on the screens.
    def brand_color
      color = company.brand_color
      color.to_s.match?(/\A#\h{6}\z/) ? color.delete_prefix("#").upcase : DEFAULT_BRAND
    end
  end
end
