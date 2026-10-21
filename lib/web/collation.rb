module Web
  # String#localeCompare as the Angular pages call it with no locale — the
  # browser's, which in every parity run is the page's (fr-FR, ar-TN, en-US)
  # — for lists the server now sorts before the page sees them. ICU compares
  # in three passes: the characters alone (accents and case ignored), then
  # the accents (unaccented first), then the case (lower before upper); the
  # key below makes those passes in that order. Within the first pass,
  # whitespace comes first, then punctuation in ICU's own order, then
  # digits, then letters — Latin before Arabic, except in Arabic, where ICU
  # puts the Arabic script first. Inside a script, code-point order stands
  # in for ICU's; a page that also sorts in the browser (team_page) settles
  # any difference there.
  module Collation
    MARKS = /\p{Mn}/
    # ICU root's order for the punctuation and symbols a name can hold.
    PUNCTUATION = "_-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$".chars.each_with_index.to_h.freeze

    def self.key(text, locale: I18n.locale)
      decomposed = text.to_s.unicode_normalize(:nfd)
      letters = decomposed.gsub(MARKS, "")
      arabic_first = locale.to_s == "ar"
      [ letters.downcase.chars.map { |c| primary(c, arabic_first) }, accents(decomposed), letters.chars.map { |c| c == c.downcase ? 0 : 1 } ]
    end

    def self.sort(items, locale: I18n.locale, &name)
      items.sort_by { |item| key(name.call(item), locale: locale) }
    end

    def self.primary(char, arabic_first)
      return [ 0, 0 ] if char.match?(/\s/)
      return [ 1, PUNCTUATION[char] ] if PUNCTUATION.key?(char)
      return [ 2, char.ord ] if char.match?(/\d/)
      return [ arabic_first ? 3 : 5, char.ord ] if char.match?(/\p{Arabic}/)

      [ 4, char.ord ]
    end
    private_class_method :primary

    # Each character's accents, in order: "" for none, so an unaccented
    # letter sorts first.
    def self.accents(decomposed)
      decomposed.scan(/\P{Mn}\p{Mn}*/).map { |cluster| cluster[1..] }
    end
    private_class_method :accents
  end
end
