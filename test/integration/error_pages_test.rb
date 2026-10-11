require "test_helper"

# Les pages d'erreur sont des fichiers statiques de public/, servis par Rails
# sans le layout ni les assets compilés (décidé le 11/10/2026 : en français, à
# la DA du site). Ce test garde ce qui les ferait casser sans bruit.
class ErrorPagesTest < ActiveSupport::TestCase
  PAGES = %w[ 400.html 404.html 406-unsupported-browser.html 422.html 500.html ].freeze

  PAGES.each do |page|
    test "#{page} est en français, à la DA, et sans style en ligne" do
      html = Rails.public_path.join(page).read

      assert_includes html, '<html lang="fr">'
      assert_includes html, "Prêt-à-tirer"
      assert_includes html, "contact@pretatirer.fr"
      assert_no_match(/<style|style=/, html, "la CSP (style-src 'self') bloquerait un style en ligne")

      stylesheet = html[%r{href="(/erreurs/[^"?]+\.css)}, 1]
      assert stylesheet, "feuille de styles attendue sous /erreurs/"
      assert Rails.public_path.join(stylesheet.delete_prefix("/")).exist?
    end
  end

  test "les polices de la feuille d'erreur existent" do
    css = Rails.public_path.join("erreurs/erreurs.css").read
    fonts = css.scan(%r{url\("(/erreurs/[^"]+)"\)}).flatten

    assert_equal 2, fonts.size
    fonts.each { |font| assert Rails.public_path.join(font.delete_prefix("/")).exist?, font }
  end
end
