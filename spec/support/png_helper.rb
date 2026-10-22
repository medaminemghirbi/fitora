# A PNG that only declares its size: signature, IHDR, IEND — no pixels.
# Enough for anything that reads the header (Receipts::PrintableImage), and
# what an oversized upload looks like to it.
module PngHelper
  def png_declaring(width, height)
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    StringIO.new("\x89PNG\r\n\x1A\n".b + chunk.("IHDR".b, [ width, height, 8, 6, 0, 0, 0 ].pack("NNCCCCC")) + chunk.("IEND".b, "".b))
  end
end

RSpec.configure do |config|
  config.include PngHelper
end
