require "rails_helper"

# The orders below are Chromium's own: `[...names].sort((a, b) =>
# a.localeCompare(b, locale))` in Node 20 (ICU), for each locale.
RSpec.describe Web::Collation do
  names = [ "émilie", "Emilie", "emilie", "Eve", "Ève", "eve", "Zoé", "zoe", "Zoe", "Ali Ben", "Alibaba", "Ali-Baba", "Ali", "ali",
            "Amine Ben Salah", "Amine", "Yasmine Trabelsi", "Yassine Jaziri", "Sarah Trabelsi", "Lina Gharbi", "Çelik", "Celik",
            "Hela Chaabane", "Karim Mansour", "Nadia Ayari", "Olfa Bouaziz", "O'Neil", "Oneil", "3D Studio", "Ahmed", "أحمد", "محمد", "Zied" ]
  latin = [ "3D Studio", "Ahmed", "ali", "Ali", "Ali Ben", "Ali-Baba", "Alibaba", "Amine", "Amine Ben Salah", "Celik", "Çelik", "emilie",
            "Emilie", "émilie", "eve", "Eve", "Ève", "Hela Chaabane", "Karim Mansour", "Lina Gharbi", "Nadia Ayari", "O'Neil", "Olfa Bouaziz",
            "Oneil", "Sarah Trabelsi", "Yasmine Trabelsi", "Yassine Jaziri", "Zied", "zoe", "Zoe", "Zoé" ]

  it "sorts as localeCompare does in French and English: Latin, then Arabic" do
    expected = latin + [ "أحمد", "محمد" ]
    expect(described_class.sort(names.shuffle(random: Random.new(1)), locale: :fr, &:itself)).to eq(expected)
    expect(described_class.sort(names.shuffle(random: Random.new(2)), locale: :en, &:itself)).to eq(expected)
  end

  it "sorts as localeCompare does in Arabic: digits, then the Arabic script, then Latin" do
    expected = [ "3D Studio", "أحمد", "محمد" ] + latin.drop(1)
    expect(described_class.sort(names.shuffle(random: Random.new(3)), locale: :ar, &:itself)).to eq(expected)
  end
end
