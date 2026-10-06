require "test_helper"

# Decided on 06/10/2026: Référencement includes 100 generations a month for
# the workshop's clients, Atelier+ none at all.
class PrinterGenerationQuotaTest < ActiveSupport::TestCase
  test "the listing plan has a monthly ceiling, Atelier+ has none" do
    assert_equal 100, PrinterGenerationQuota.for(printers(:rennes)).limit
    assert_nil PrinterGenerationQuota.for(printers(:lyon)).limit
    assert_nil PrinterGenerationQuota.for(nil).limit
    assert PrinterGenerationQuota.for(printers(:lyon)).allows?(1_000)
  end

  test "this month's designs count, failed ones and last month's do not" do
    rennes = printers(:rennes)
    before = PrinterGenerationQuota.for(rennes).used

    design_for(rennes)
    design_for(rennes, status: "failed")
    design_for(rennes, created_at: 1.month.ago.beginning_of_month)

    assert_equal before + 1, PrinterGenerationQuota.for(rennes).used
  end

  test "the workshop is told once a month, when the ceiling is reached" do
    rennes = printers(:rennes)
    quota = PrinterGenerationQuota.for(rennes)
    (quota.limit - quota.used).times { design_for(rennes) }

    assert quota.exceeded?
    assert_enqueued_emails(1) { quota.notify_if_reached! }
    assert_enqueued_emails(0) { PrinterGenerationQuota.for(rennes.reload).notify_if_reached! }

    rennes.update_column(:generation_quota_notified_on, 1.month.ago.to_date)
    assert_enqueued_emails(1) { PrinterGenerationQuota.for(rennes.reload).notify_if_reached! }
  end

  test "nobody is told while there is room left" do
    assert_enqueued_emails(0) { PrinterGenerationQuota.for(printers(:rennes)).notify_if_reached! }
  end

  # Since October 2026 one click draws three proposals: it is still one
  # generation for the workshop.
  test "the proposals of one click count once" do
    rennes = printers(:rennes)
    before = PrinterGenerationQuota.for(rennes).used

    3.times { design_for(rennes, batch_token: "click-1") }
    design_for(rennes)

    assert_equal before + 2, PrinterGenerationQuota.for(rennes).used
  end

  private
    def design_for(printer, status: "ready", created_at: Time.current, batch_token: nil)
      Design.insert!({ user_id: users(:client).id, printer_id: printer.id, prompt: "un renard",
                       technique: "screen_printing", print_width_cm: 25, status: status, batch_token: batch_token,
                       token: SecureRandom.base58(24), created_at: created_at, updated_at: created_at })
    end
end
