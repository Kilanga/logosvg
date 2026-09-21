require "test_helper"

# "Aucune requête N+1 sur les listes" is a rule, so it is measured rather than
# reviewed. Each budget is generous — what it catches is a screen that issues
# one query per row, not a screen that issues a few more than it might.
class QueryBudgetTest < ActionDispatch::IntegrationTest
  setup { attach_files }

  test "the client's design list stays flat as designs are added" do
    sign_in_as users(:client)

    assert_flat(client_designs_path) { create_design }
  end

  test "the client's print request list stays flat" do
    sign_in_as users(:client)

    assert_flat(client_print_requests_path) { create_print_request }
  end

  test "the client's review list stays flat" do
    sign_in_as users(:client)

    assert_flat(client_reviews_path) { create_review }
  end

  test "the workshop's request list stays flat" do
    sign_in_as users(:printer)

    assert_flat(workshop_print_requests_path) { create_print_request }
  end

  test "the designer's queue stays flat" do
    sign_in_as users(:designer)

    assert_flat(designer_reviews_path) { create_review(status: "queued") }
  end

  test "the administration's review list stays flat" do
    sign_in_as users(:admin)

    assert_flat(admin_reviews_path(filtre: "all")) { create_review }
  end

  test "the printer directory stays flat" do
    assert_flat(printers_path) { create_printer }
  end

  test "the designer directory stays flat" do
    assert_flat(designers_path) { create_designer }
  end

  test "the administration dashboard stays flat as designers are added" do
    sign_in_as users(:admin)

    assert_flat(admin_dashboard_path) { create_designer_with_reviews }
  end

  private
    # The measure: how many more queries three extra rows cost. A list that
    # loads its associations properly costs nothing for them.
    def assert_flat(path, added: 3)
      get path
      before = count_queries { get path }

      added.times { yield }

      after = count_queries { get path }
      growth = after - before

      assert_operator growth, :<=, added,
                      "#{path} : #{growth} requêtes de plus pour #{added} lignes de plus " \
                      "(#{before} → #{after})"
    end

    def count_queries
      count = 0
      counter = ->(_name, _start, _finish, _id, payload) do
        count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end

    # --- Rows to add ---------------------------------------------------------

    def create_design
      Design.create!(user: users(:client), printer: printers(:rennes),
                     prompt: "un motif de plus #{SecureRandom.hex(4)}",
                     technique: "screen_printing", print_width_cm: 25,
                     status: "ready", print_format: "svg", inks_count: 2,
                     palette: [ { "hex" => "#1F5F7A" } ]).tap { |d| attach_to(d) }
    end

    def create_print_request
      PrintRequest.create!(design: create_design, client: users(:client),
                           printer: printers(:rennes), print_width_cm: 25,
                           sizes: { "M" => 20 }, total_qty: 20,
                           contact_name: "Claire", contact_email: "claire@example.invalid",
                           consent_text_version: "2026-09-v1", consented_at: Time.current,
                           sent_at: Time.current)
    end

    def create_review(status: "delivered")
      Review.create!(design: create_design, client: users(:client),
                     review_level: review_levels(:check),
                     designer_profile: (designer_profiles(:ines) unless status == "queued"),
                     status: status, price_cents: 1900, platform_fee_cents: 380,
                     revisions_included: 1, paid_at: 1.day.ago,
                     delivered_at: (1.day.ago if status == "delivered"))
    end

    def create_printer
      user = User.create!(email_address: "atelier-#{SecureRandom.hex(4)}@example.invalid",
                          password: "motdepasse-test", first_name: "A", last_name: "B",
                          role: "printer", terms_accepted_at: Time.current)
      printer = Printer.create!(user: user, name: "Atelier #{SecureRandom.hex(3)}",
                                orders_email: user.email_address, description: "Un atelier.",
                                address: "1 rue", postal_code: "44000", city: "Nantes")
      printer.techniques.create!(technique: "screen_printing", max_colors: 4,
                                 output_format: "svg", color_space: "rgb", primary: true)
      printer.update!(status: :published)
      Subscription.create!(printer: printer, plan: "listing", status: "active")
      printer
    end

    def create_designer(**attributes)
      user = User.create!(email_address: "graphiste-#{SecureRandom.hex(4)}@example.invalid",
                          password: "motdepasse-test", first_name: "C", last_name: "D",
                          role: "designer", terms_accepted_at: Time.current)
      profile = DesignerProfile.create!(user: user, display_name: "Graphiste #{SecureRandom.hex(3)}",
                                        bio: "Une présentation assez longue pour passer la validation.",
                                        city: "Lyon", status: "active", payouts_enabled: true,
                                        **attributes)
      profile.review_levels << review_levels(:check)
      profile
    end

    # The dashboard asks each designer for its return rate, which is the shape
    # most likely to go quadratic.
    def create_designer_with_reviews
      profile = create_designer

      2.times do
        Review.create!(design: create_design, client: users(:client),
                       review_level: review_levels(:check), designer_profile: profile,
                       status: "delivered", price_cents: 1900, platform_fee_cents: 380,
                       revisions_included: 1, paid_at: 1.day.ago, delivered_at: 1.day.ago)
      end

      profile
    end

    # --- Files ---------------------------------------------------------------

    def attach_files
      [ designs(:fox_screen), designs(:fox_dtf) ].each { |design| attach_to(design) }
    end

    def attach_to(design)
      design.print_file.attach(io: StringIO.new(svg), filename: "design.svg",
                               content_type: "image/svg+xml")
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">) +
        %(<rect width="10" height="10" fill="#1F5F7A"/></svg>)
    end
end
