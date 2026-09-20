# Everything the platform holds about one account, as JSON.
#
# Not a database dump: an export a person can actually read, with the
# platform's own vocabulary and nothing they did not put there. Files are
# listed with the address they download from rather than bundled — the client
# is never handed a print file, and a list of links is honest about what they
# may and may not take.
#
# See docs/SPEC.md, "RGPD".
class AccountExport
  def self.call(...) = new(...).call

  # The host is passed in rather than a view. An export has to carry absolute
  # addresses — it is read outside the browser that asked for it — but a
  # service that needs a whole request to exist cannot be called from a job or
  # a console, and cannot be tested without building one.
  def initialize(user:, host:)
    @user = user
    @host = host
  end

  def call
    {
      exported_at: Time.current.iso8601,
      account: account,
      designs: designs,
      print_requests: print_requests,
      reviews: reviews,
      printer: printer,
      designer_profile: designer_profile
    }.compact
  end

  private
    def routes = Rails.application.routes.url_helpers

    def account
      {
        email: @user.email_address,
        first_name: @user.first_name,
        last_name: @user.last_name,
        phone: @user.phone,
        city: @user.city,
        role: @user.role,
        terms_accepted_at: @user.terms_accepted_at&.iso8601,
        created_at: @user.created_at.iso8601
      }
    end

    def designs
      @user.designs.includes(:printer).map do |design|
        {
          reference: design.token,
          prompt: design.prompt,
          style: design.style,
          technique: design.technique,
          print_width_cm: design.print_width_cm,
          colors_requested: design.colors_requested,
          status: design.status,
          inks: design.inks_count,
          palette: design.palette,
          workshop: design.printer&.name,
          created_at: design.created_at.iso8601,
          deleted_at: design.deleted_at&.iso8601,
          # The watermarked rendering, which is what a client may take. The
          # print file itself goes to workshops and designers only.
          preview_url: (routes.design_image_url(design, host: @host) if design.ready?)
        }.compact
      end
    end

    def print_requests
      @user.print_requests.includes(:printer).map do |request|
        {
          reference: request.token,
          workshop: request.printer.name,
          status: request.status,
          textile_source: request.textile_source,
          textile: [ request.textile_model, request.textile_color ].compact_blank.join(" "),
          placements: request.placements,
          sizes: request.sizes,
          total_qty: request.total_qty,
          message: request.message,
          consent_text_version: request.consent_text_version,
          consented_at: request.consented_at&.iso8601,
          sent_at: request.sent_at&.iso8601
        }.compact_blank
      end
    end

    def reviews
      @user.reviews.includes(:review_level, :designer_profile, :messages).map do |review|
        {
          reference: review.token,
          level: review.review_level.name,
          designer: review.designer_profile&.display_name,
          status: review.status,
          brief: review.client_brief,
          price_cents: review.price_cents,
          refunded_cents: review.refunded_cents,
          rating: review.rating,
          rating_comment: review.rating_comment,
          messages: review.messages.map { |m| message_for(m) },
          created_at: review.created_at.iso8601
        }.compact_blank
      end
    end

    def message_for(message)
      { author: message.from_client? ? "moi" : "graphiste",
        body: message.body, sent_at: message.created_at.iso8601 }
    end

    # Only for the accounts that have one.
    def printer
      shop = @user.printer
      return nil if shop.nil?

      { name: shop.name, slug: shop.slug, city: shop.city, status: shop.status,
        orders_email: shop.orders_email,
        techniques: shop.techniques.map { |t| { technique: t.technique, label: t.display_label } } }
    end

    def designer_profile
      profile = @user.designer_profile
      return nil if profile.nil?

      { display_name: profile.display_name, bio: profile.bio, city: profile.city,
        specialties: profile.specialties, languages: profile.languages,
        status: profile.status, rating_avg: profile.rating_avg&.to_f,
        ratings_count: profile.ratings_count,
        levels: profile.review_levels.map(&:name) }
    end
end
