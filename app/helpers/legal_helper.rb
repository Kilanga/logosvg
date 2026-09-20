module LegalHelper
  # The six documents, in the order they are usually read. Named here so the
  # footer and each page's own navigation stay in step.
  def legal_pages
    {
      "legal_notice" => legal_notice_path,
      "terms" => terms_path,
      "subscription_terms" => subscription_terms_path,
      "designer_terms" => designer_terms_path,
      "privacy" => privacy_path,
      "ranking" => ranking_path
    }
  end

  # One section of a legal page: a heading and its paragraphs, taken from the
  # locale so the text lives with every other sentence the site shows.
  def legal_section(key)
    tag.section do
      concat tag.h2(t("legal.#{@page}.#{key}.title"),
                    class: "font-display text-xl font-bold uppercase")
      concat tag.div(class: "mt-3 space-y-3 text-muted") {
        safe_join(Array(t("legal.#{@page}.#{key}.body")).map { |p| tag.p(p) })
      }
    end
  end
end
