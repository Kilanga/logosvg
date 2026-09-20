require "test_helper"

# Keeping data no longer than it is useful — and not one day less where a
# commercial record depends on it.
class PurgeStaleDataJobTest < ActiveJob::TestCase
  setup { @retention = Rails.application.config.tshirt.privacy }

  # --- Designs --------------------------------------------------------------

  test "a design nobody ever sent anywhere is deleted once it is old enough" do
    design = designs(:pending_design)
    design.update_column(:created_at, (@retention[:design_retention_days] + 1).days.ago)

    PurgeStaleDataJob.perform_now

    assert_not Design.exists?(design.id)
  end

  test "a recent design is left alone" do
    PurgeStaleDataJob.perform_now

    assert Design.exists?(designs(:pending_design).id)
  end

  # A design a workshop was asked to print is part of that workshop's record.
  test "a design that was sent to a workshop survives" do
    design = designs(:fox_screen)
    design.update_column(:created_at, 5.years.ago)

    PurgeStaleDataJob.perform_now

    assert Design.exists?(design.id)
  end

  test "a design a designer was paid to look at survives too" do
    design = designs(:fox_dtf)
    design.print_requests.destroy_all
    design.update_column(:created_at, 5.years.ago)

    PurgeStaleDataJob.perform_now

    assert Design.exists?(design.id), "a review still points at it"
  end

  # --- Print requests -------------------------------------------------------
  #
  # The order stays; the person does not.

  test "an old print request is anonymised rather than deleted" do
    request = print_requests(:waiting)
    request.update_column(:created_at, (@retention[:print_request_anonymize_days] + 1).days.ago)

    PurgeStaleDataJob.perform_now
    request.reload

    assert_nil request.contact_email
    assert_nil request.contact_phone
    assert_equal I18n.t("privacy.anonymised"), request.contact_name
    assert_equal 15, request.total_qty, "what the workshop printed is untouched"
  end

  test "a recent print request keeps its contact" do
    PurgeStaleDataJob.perform_now

    assert_equal "claire@example.invalid", print_requests(:waiting).reload.contact_email
  end

  # --- Closed accounts ------------------------------------------------------

  test "a closed account is emptied of the person once the delay is past" do
    user = users(:deleted_client)
    user.update_column(:deleted_at, (@retention[:deleted_account_purge_days] + 1).days.ago)

    PurgeStaleDataJob.perform_now
    user.reload

    assert_match(/compte-supprime-/, user.email_address)
    assert_equal I18n.t("privacy.anonymised"), user.first_name
    assert_nil user.phone
    assert_nil user.city
  end

  test "an account closed yesterday is left alone" do
    users(:deleted_client).update_column(:deleted_at, 1.day.ago)

    PurgeStaleDataJob.perform_now

    assert_equal "parti@example.invalid", users(:deleted_client).reload.email_address
  end

  test "an account that is still open is never touched" do
    PurgeStaleDataJob.perform_now

    assert_equal "claire@example.invalid", users(:client).reload.email_address
  end

  # The row stays because a print request and a review both refuse to lose
  # their client — the workshop's job and the designer's payment outlive it.
  test "emptying an account leaves its commercial records standing" do
    user = users(:client)
    user.soft_delete!
    user.update_column(:deleted_at, 60.days.ago)

    PurgeStaleDataJob.perform_now

    assert PrintRequest.exists?(print_requests(:waiting).id)
    assert Review.exists?(reviews(:delivered).id)
    assert_equal user.id, print_requests(:waiting).reload.client_id
  end

  test "an account already emptied is not emptied again" do
    user = users(:deleted_client)
    user.update_column(:deleted_at, 60.days.ago)

    PurgeStaleDataJob.perform_now
    first = user.reload.updated_at

    PurgeStaleDataJob.perform_now

    assert_equal first, user.reload.updated_at
  end

  test "a closed account can no longer sign in, emptied or not" do
    users(:deleted_client).update_column(:deleted_at, 60.days.ago)

    PurgeStaleDataJob.perform_now

    assert_nil User.authenticate_by(email_address: "parti@example.invalid",
                                    password: "motdepasse-test")
  end
end
