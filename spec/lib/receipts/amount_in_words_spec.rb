require "rails_helper"

RSpec.describe Receipts::AmountInWords do
  {
    0 => "zéro", 1 => "un", 17 => "dix-sept", 21 => "vingt et un", 71 => "soixante et onze", 72 => "soixante-douze",
    80 => "quatre-vingts", 81 => "quatre-vingt-un", 91 => "quatre-vingt-onze", 99 => "quatre-vingt-dix-neuf",
    100 => "cent", 101 => "cent un", 180 => "cent quatre-vingts", 200 => "deux cents", 201 => "deux cent un",
    1_000 => "mille", 2_000 => "deux mille", 21_000 => "vingt et un mille", 80_000 => "quatre-vingt mille",
    200_000 => "deux cent mille", 1_000_000 => "un million", 200_000_000 => "deux cents millions",
    2_689 => "deux mille six cent quatre-vingt-neuf"
  }.each do |value, words|
    it("writes #{value} as \"#{words}\"") { expect(described_class.number(value)).to eq(words) }
  end

  it "writes an amount in dinars, the millimes in figures" do
    expect(described_class.dinars(165_000)).to eq("Cent soixante-cinq dinars")
    expect(described_class.dinars(884_425)).to eq("Huit cent quatre-vingt-quatre dinars et 425 millimes")
    expect(described_class.dinars(1_000)).to eq("Un dinar")
    expect(described_class.dinars(1_000_000_000)).to eq("Un million de dinars")
  end
end
