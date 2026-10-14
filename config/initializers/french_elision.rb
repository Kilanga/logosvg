# « de » before a name that starts with a vowel is « d' » in French (reported
# on 14/10/2026: « vient de Atelier 1 Test », « client de Atelier 2 »).
#
# Names are the users' own — a shop, a designer — so the translation cannot
# know them in advance. The elision is made here, once, when a translation
# containing « de %{…} » is interpolated: every message benefits, and none has
# to pass a second, pre-elided variable. Names starting with an « h » are left
# alone: an aspirated h takes no elision, and a name gives no way to tell.
module FrenchElision
  VOWEL = /\A[aeiouyàâäéèêëîïôöùûüœæAEIOUYÀÂÄÉÈÊËÎÏÔÖÙÛÜŒÆ]/
  PATTERN = /\b([Dd])e %\{(\w+)\}/

  def interpolate(locale, subject, values = ::I18n::EMPTY_HASH)
    if locale.to_s == "fr" && subject.is_a?(String) && subject.include?("e %{")
      subject = subject.gsub(PATTERN) do
        letter, key = Regexp.last_match(1), Regexp.last_match(2)
        value = values[key.to_sym].to_s
        value.match?(VOWEL) ? "#{letter}'%{#{key}}" : Regexp.last_match(0)
      end
    end

    super
  end
end

I18n::Backend::Simple.include(FrenchElision)
