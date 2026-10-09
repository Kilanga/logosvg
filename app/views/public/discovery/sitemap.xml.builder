xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  [ root_url, printers_url, designers_url, contact_url, help_url,
    legal_notice_url, terms_url, subscription_terms_url, designer_terms_url,
    privacy_url, cookies_url, ranking_url ].each do |url|
    xml.url { xml.loc url }
  end

  @printers.each do |printer|
    xml.url do
      xml.loc printer_url(printer)
      xml.lastmod printer.updated_at.to_date.iso8601
    end
  end

  @designers.each do |designer|
    xml.url do
      xml.loc designer_url(designer)
      xml.lastmod designer.updated_at.to_date.iso8601
    end
  end
end
