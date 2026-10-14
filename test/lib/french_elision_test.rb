require "test_helper"

# Reported on 14/10/2026: « client de Atelier 2 ».
class FrenchElisionTest < ActiveSupport::TestCase
  test "de becomes d' before a name starting with a vowel" do
    assert_equal "La fiche d'Atelier 1 Test est publiée.",
                 I18n.t("admin.printers.update.published", name: "Atelier 1 Test")
    assert_equal "La fiche d'Écran Vert est publiée.",
                 I18n.t("admin.printers.update.published", name: "Écran Vert")
  end

  test "de stays before a consonant, an h, or a number" do
    assert_equal "La fiche de Rennes Sérigraphie est publiée.",
                 I18n.t("admin.printers.update.published", name: "Rennes Sérigraphie")
    assert_equal "La fiche de Hautes Encres est publiée.",
                 I18n.t("admin.printers.update.published", name: "Hautes Encres")
    assert_equal "moins de 5 secondes", I18n.t("datetime.distance_in_words.less_than_x_seconds", count: 5)
  end
end
