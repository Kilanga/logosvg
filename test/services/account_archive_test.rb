require "test_helper"

class AccountArchiveTest < ActiveSupport::TestCase
  test "a workshop's archive carries its logo and photos beside the JSON" do
    shop = printers(:rennes)
    png = Vips::Image.black(4, 4).write_to_buffer(".png")
    shop.logo.attach(io: StringIO.new(png), filename: "logo.png", content_type: "image/png")
    shop.photos.attach(io: StringIO.new(png), filename: "vitrine.png", content_type: "image/png")

    names = entries(AccountArchive.call(user: users(:printer), host: "pretatirer.test"))

    assert_includes names, AccountArchive::JSON_NAME
    assert_includes names, "atelier/logo.png"
    assert_includes names, "atelier/photo-1.png"
  end

  private
    def entries(bytes)
      names = []
      Zip::File.open_buffer(StringIO.new(bytes)) { |zip| zip.each { |entry| names << entry.name } }
      names
    end
end
