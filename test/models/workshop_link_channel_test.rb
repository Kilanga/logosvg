require "test_helper"

class WorkshopLinkChannelTest < ActiveSupport::TestCase
  setup { @printer = printers(:lyon) }

  test "the key is made from the label" do
    channel = @printer.link_channels.create!(label: "Salon de Rennes")

    assert_equal "salon-de-rennes", channel.key
  end

  test "a label that collides gets a number, not a random suffix" do
    @printer.link_channels.create!(label: "Flyer")

    assert_equal "flyer-2", @printer.link_channels.create!(label: "flyer").key
    assert_equal "flyer-3", @printer.link_channels.create!(label: "FLYER!").key
  end

  test "the two built-in sources cannot be taken" do
    assert_equal "qr-2", @printer.link_channels.create!(label: "QR").key
    assert_equal "link-2", @printer.link_channels.create!(label: "Link").key
  end

  test "two shops may each have a flyer" do
    @printer.link_channels.create!(label: "Flyer")

    assert_equal "flyer", printers(:rennes).link_channels.create!(label: "Flyer").key
  end

  test "a label with nothing to make a key from is refused" do
    channel = @printer.link_channels.build(label: "?!…")

    assert_not channel.valid?
    assert channel.errors.added?(:label, :invalid)
  end

  test "a label is required and short" do
    assert_not @printer.link_channels.build(label: "  ").valid?
    assert_not @printer.link_channels.build(label: "a" * 41).valid?
    assert @printer.link_channels.build(label: "a" * 40).valid?
  end

  test "a shop is held to ten channels" do
    WorkshopLinkChannel::LIMIT.times { |n| @printer.link_channels.create!(label: "Canal #{n}") }

    channel = @printer.link_channels.build(label: "Un de trop")

    assert_not channel.valid?
    assert channel.errors.added?(:base, :limit_reached, count: WorkshopLinkChannel::LIMIT)
  end

  test "the database refuses a duplicate key even if validation is skipped" do
    @printer.link_channels.create!(label: "Flyer")

    assert_raises ActiveRecord::RecordNotUnique do
      @printer.link_channels.build(label: "Autre", key: "flyer").save!(validate: false)
    end
  end

  test "deleting the shop deletes its channels" do
    @printer.link_channels.create!(label: "Flyer")

    assert_difference -> { WorkshopLinkChannel.count }, -1 do
      @printer.link_channels.delete_all
    end
  end

  # --- What `?s=` may name -------------------------------------------------------

  test "a source is the qr code, one of the shop's channels, or the plain link" do
    @printer.link_channels.create!(label: "Flyer")

    assert_equal "qr", @printer.link_source("qr")
    assert_equal "flyer", @printer.link_source("flyer")
    assert_equal "link", @printer.link_source(nil)
    assert_equal "link", @printer.link_source("")
    assert_equal "link", @printer.link_source("inconnu")
    assert_equal "link", @printer.link_source([ "flyer" ])
  end

  test "another shop's channel is not a channel here" do
    printers(:rennes).link_channels.create!(label: "Flyer")

    assert_equal "link", @printer.link_source("flyer")
  end
end
