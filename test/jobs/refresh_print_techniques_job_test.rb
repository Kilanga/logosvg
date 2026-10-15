require "test_helper"

class RefreshPrintTechniquesJobTest < ActiveJob::TestCase
  CATALOGUE = %r{\Ahttps?://[^/]+/techniques\z}

  setup do
    PrintTechniques.reset!
    ENV["GENERATOR_URL"] = "http://generator.test"
  end

  teardown do
    PrintTechniques.reset!
    ENV.delete("GENERATOR_URL")
  end

  # Reported on 16/10/2026: every night the generation machine sleeps, three
  # tries ended in a failed job kept for good — 802 of them, burying anything
  # else. An unreachable service is a normal state: retried, then let go.
  test "an unreachable service is retried, then let go without failing" do
    stub_request(:get, CATALOGUE).to_return(status: 502, body: "")

    assert_nothing_raised do
      perform_enqueued_jobs { RefreshPrintTechniquesJob.perform_later }
    end

    assert_requested :get, CATALOGUE, times: 3
  end
end
