module Receipts
  # An attached image (the gym's logo, its signature) as something Prawn can
  # draw — or nil. Prawn embeds PNG and JPEG only, so a WebP logo is simply
  # left off the document rather than failing it.
  #
  # Prawn decodes a PNG whole to embed it (a JPEG goes in as it is), so a PNG
  # of a hundred KB can declare 5,000 × 5,000 pixels and take 300 MB to print —
  # every time a contract or a receipt is downloaded. Above MAX_PIXELS it is
  # left off, judged from its header alone; Company refuses such uploads.
  module PrintableImage
    PRINTABLE = %w[image/png image/jpeg].freeze
    MAX_PIXELS = 2048 * 2048
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
    HEADER_BYTES = 24

    def self.io(attachment)
      return nil unless attachment&.attached?
      return nil unless attachment.content_type.in?(PRINTABLE)

      head = attachment.blob.download_chunk(0...HEADER_BYTES)
      unless drawable?(head)
        Rails.logger.warn("[receipts] #{attachment.name} is #{png_size(head).join(' × ')} px, over #{MAX_PIXELS}: left off the PDF")
        return nil
      end

      StringIO.new(attachment.download)
    rescue ActiveStorage::FileNotFoundError
      nil
    end

    # The width and height a PNG's header declares, or nil: not a PNG.
    def self.png_size(head)
      head = head.to_s.b
      return nil unless head.start_with?(PNG_SIGNATURE) && head.byteslice(12, 4) == "IHDR"

      head.byteslice(16, 8).unpack("NN")
    end

    # False for a PNG over MAX_PIXELS; anything else draws as before.
    def self.drawable?(head)
      size = png_size(head)
      size.nil? || size.inject(:*) <= MAX_PIXELS
    end
  end
end
