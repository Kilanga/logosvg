require "test_helper"

# Le pendant, côté travaux de fond, de test/integration/strict_loading_test.rb.
#
# La chaîne de génération ne traverse aucun contrôleur : Solid Queue rend un
# `Design` par son identifiant global, c'est-à-dire un `Design.find` nu, sans la
# moindre association préchargée. Tout saut paresseux y lève en développement —
# et nulle part ailleurs, puisque la suite ne tourne pas avec le réglage.
#
# C'est ainsi que `design.user`, lu au fond de GeneratorClient pour calculer le
# pseudonyme RGPD, a tué la génération avant son premier appel HTTP : le
# travail échouait, l'écran du client tournait, et les 776 tests restaient
# verts.
class JobsStrictLoadingTest < ActiveJob::TestCase
  GENERATE = "http://generator.test/generate".freeze
  JOB = "http://generator.test/jobs/job-42".freeze

  setup do
    ENV["GENERATOR_URL"] = "http://generator.test"
    ENV["GENERATOR_API_KEY"] = "not-a-key-generator-placeholder"
    ENV["GENERATOR_USER_KEY"] = "not-a-key-hmac-placeholder"

    @id = designs(:pending_design).id

    @previous = ActiveRecord::Base.strict_loading_by_default
    ActiveRecord::Base.strict_loading_by_default = true
  end

  teardown do
    ActiveRecord::Base.strict_loading_by_default = @previous
    %w[ GENERATOR_URL GENERATOR_API_KEY GENERATOR_USER_KEY ].each { |k| ENV.delete(k) }
  end

  # Comme Solid Queue le rend : par son identifiant, et rien d'autre.
  def design = Design.find(@id)

  test "a generation goes out with strict loading on, as development runs it" do
    stub_request(:post, GENERATE).to_return(
      body: { job_id: "job-42", status: "queued", position: 1, refinements_left: 3 }.to_json
    )

    GenerateDesignJob.perform_now(design)

    assert_predicate design, :generating?
  end

  # Le chemin du refus compte autant : il rembourse le quota et diffuse
  # l'échec — deux occasions de plus de sauter vers le compte.
  test "a refusal is recorded with strict loading on" do
    stub_request(:post, GENERATE).to_return(
      status: 422, body: { detail: "Cette demande contient une marque non autorisée." }.to_json
    )

    GenerateDesignJob.perform_now(design)

    assert_predicate design, :failed?
  end

  test "a poll asks after the design with strict loading on" do
    prepare_generating
    stub_request(:get, %r{#{JOB}}).to_return(
      body: { status: "running", position: 2 }.to_json
    )

    PollDesignJob.perform_now(design)

    assert_predicate design, :generating?
  end

  # Le plus long des chemins : téléchargement, examen du SVG, attachement,
  # relevé du résultat et diffusion.
  test "a finished generation is brought home with strict loading on" do
    prepare_generating
    stub_request(:get, %r{#{JOB}(\?|$)}).to_return(body: {
      status: "done", refinements_left: 2,
      result: { print_file: "design.svg", palette: [ { hex: "#1F5F7A" } ], inks: 1,
                stats: { paths: 12 }, warnings: [], prompt_used: "screen print, a mountain", seed: 7 }
    }.to_json)
    stub_request(:get, %r{/jobs/job-42/design\.svg}).to_return(body: svg)
    stub_request(:get, %r{/jobs/job-42/source\.png}).to_return(status: 404, body: "{}")

    PollDesignJob.perform_now(design)

    assert_predicate design, :ready?
  end

  private
    def prepare_generating
      ActiveRecord::Base.strict_loading_by_default = false
      d = Design.find(@id)
      d.update!(generator_job_id: "job-42")
      d.start!
      d.save!
      ActiveRecord::Base.strict_loading_by_default = true
    end

    def svg
      <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <path d="M0 0h10v10H0z" fill="#1F5F7A"/>
        </svg>
      SVG
    end
end
