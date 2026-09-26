require "test_helper"

class StoreGeneratedDesignTest < ActiveSupport::TestCase
  setup do
    ENV["GENERATOR_URL"] = "http://generator.test"
    ENV["GENERATOR_API_KEY"] = "not-a-key-generator-placeholder"
    ENV["GENERATOR_USER_KEY"] = "not-a-key-hmac-placeholder"

    @design = designs(:pending_design)
    @design.update!(generator_job_id: "job-42")
    @design.start!
    @design.save!
  end

  teardown do
    %w[ GENERATOR_URL GENERATOR_API_KEY GENERATOR_USER_KEY ].each { |k| ENV.delete(k) }
  end

  test "a vector result is attached, counted in inks, and turns ready" do
    stub_file("design.svg", svg)
    stub_file("source.png", png)

    StoreGeneratedDesign.call(design: @design, answer: vector_answer)
    @design.reload

    assert_predicate @design, :ready?
    assert_predicate @design.print_file, :attached?
    assert_predicate @design.source_png, :attached?
    assert_equal "design.svg", @design.print_file.filename.to_s
    assert_equal "image/svg+xml", @design.print_file.content_type
    assert_equal "svg", @design.print_format
    assert_predicate @design, :vector?
    assert_equal 12, @design.paths_count
  end

  # The file name comes from the service; the application never guesses an
  # extension from the technique.
  test "a raster result is fetched under the name the service gave" do
    stub_file("print.png", png)
    stub_file("source.png", png)

    StoreGeneratedDesign.call(design: @design, answer: raster_answer)
    @design.reload

    assert_equal "print.png", @design.print_file.filename.to_s
    assert_equal "image/png", @design.print_file.content_type
    assert_equal "png", @design.print_format
    assert_predicate @design, :raster?
    assert_requested :get, %r{/jobs/job-42/print\.png}
  end

  # Le chemin qui a bloque une generation entiere en production. Le service
  # renvoie un nombre de couleurs pour toutes les techniques : huit pour le DTF,
  # qui imprime en quadrichromie. L'ecrire dans `colors_requested`, valide entre
  # 1 et 6, rendait l'enregistrement invalide — `succeed!` levait, la
  # transaction etait annulee, et le design restait « en cours » pour toujours.
  #
  # Le design de ce cas est un vrai design DTF, pas un design de serigraphie a
  # qui l'on sert une reponse matricielle : c'est precisement ce melange qui
  # faisait passer les cas precedents a cote du defaut.
  test "a raster technique keeps its empty ink budget and turns ready" do
    dtf = designs(:fox_dtf)
    dtf.update!(generator_job_id: "job-42", status: "generating", colors_requested: nil)
    stub_file("print.png", png)
    stub_file("source.png", png)

    StoreGeneratedDesign.call(
      design: dtf, answer: raster_answer.deep_merge("result" => { "colors" => 8 })
    )
    dtf.reload

    assert_predicate dtf, :ready?
    assert_nil dtf.colors_requested, "une machine sans plafond d'encres n'en compte pas"
    assert_predicate dtf.print_file, :attached?
  end

  # Et l'inverse : la ou les encres se comptent, le chiffre du service fait foi.
  test "a vector technique records the ink budget the service settled on" do
    stub_file("design.svg", svg)
    stub_file("source.png", png)

    StoreGeneratedDesign.call(
      design: @design, answer: vector_answer.deep_merge("result" => { "colors" => 2 })
    )

    assert_equal 2, @design.reload.colors_requested
  end

  # Le catalogue en entier, technique par technique.
  #
  # Le defaut du DTF n'avait rien de propre au DTF : le service renvoie le meme
  # nombre de couleurs par defaut pour les trois techniques matricielles, et les
  # trois auraient bloque de la meme facon. Plutot que d'ajouter un cas par
  # technique, ce cas les parcourt toutes — une technique ajoutee au catalogue
  # est couverte sans qu'on ecrive une ligne de plus.
  #
  # La reponse simulee est celle que le service envoie vraiment : son fichier a
  # lui (`file_name`), et le nombre de couleurs qu'il calcule lui-meme, qui vaut
  # `default_colors` quand le client n'a rien impose — 3 en serigraphie, 8 en
  # DTF.
  test "every technique in the catalogue is brought home and turns ready" do
    stub_file("design.svg", svg)
    stub_file("print.png", png)
    stub_file("source.png", png)

    PrintTechniques.all.each do |entry|
      design = generating_design_for(entry)

      StoreGeneratedDesign.call(design: design, answer: answer_for(entry))
      design.reload

      assert_predicate design, :ready?, "#{entry.key} : le design n'est pas passe pret"
      assert_equal entry.native_format, design.print_format, "#{entry.key} : mauvais format"
      assert_equal entry.file_name, design.print_file.filename.to_s, "#{entry.key} : mauvais fichier"

      if entry.limited_colors?
        assert_equal entry.default_colors, design.colors_requested,
                     "#{entry.key} : le budget d'encres du service n'a pas ete repris"
        assert_not_nil design.inks_count, "#{entry.key} : une sortie vectorielle compte ses encres"
      else
        assert_nil design.colors_requested,
                   "#{entry.key} : une machine sans plafond d'encres n'en compte pas"
        assert_nil design.paths_count, "#{entry.key} : une sortie matricielle n'a pas de chemins"
      end

      # Et le fichier se rasterise : c'est la seule image que le client verra,
      # et elle passe par librsvg pour les unes, par libvips seul pour les
      # autres. Un apercu muet vaut un design invisible.
      assert_not_nil DesignPreview.call(design), "#{entry.key} : pas d'apercu"
    end
  end

  # Screens are counted on vector output and meaningless on raster output.
  test "inks and paths are recorded for a vector file and left empty for a raster one" do
    stub_file("print.png", png)
    stub_file("source.png", png)

    StoreGeneratedDesign.call(design: @design, answer: raster_answer)
    @design.reload

    assert_nil @design.inks_count
    assert_nil @design.paths_count
    assert_equal 300, @design.stats["dpi"]
  end

  # The inspector counts what the file actually contains; the service's own
  # figure is only a fallback. The workshop mounts screens from this number.
  test "the ink count comes from the file, not from the service's word for it" do
    stub_file("design.svg", two_colour_svg)
    stub_file("source.png", png)

    StoreGeneratedDesign.call(
      design: @design, answer: vector_answer.deep_merge("result" => { "inks" => 5 })
    )

    assert_equal 2, @design.reload.inks_count
  end

  test "the refinement budget is taken from the service and never recomputed" do
    stub_file("design.svg", svg)
    stub_file("source.png", png)

    StoreGeneratedDesign.call(design: @design, answer: vector_answer.merge("refinements_left" => 1))

    assert_equal 1, @design.reload.refinements_left
  end

  test "a refused svg is neither attached nor made ready" do
    stub_file("design.svg", %(<svg xmlns="http://www.w3.org/2000/svg" onload="steal()"></svg>))

    assert_raises(StoreGeneratedDesign::UnusableFile) do
      StoreGeneratedDesign.call(design: @design, answer: vector_answer)
    end

    @design.reload

    assert_not_predicate @design.print_file, :attached?
    assert_predicate @design, :generating?, "the state machine has not moved"
  end

  # The original image is a nicety, not the deliverable.
  test "a missing source image does not hold back the print file" do
    stub_file("design.svg", svg)
    stub_request(:get, %r{/jobs/job-42/source\.png}).to_return(status: 404, body: "{}")

    StoreGeneratedDesign.call(design: @design, answer: vector_answer)
    @design.reload

    assert_predicate @design, :ready?
    assert_predicate @design.print_file, :attached?
    assert_not_predicate @design.source_png, :attached?
  end

  private
    # Un design par technique, dans l'etat ou le travail de fond le trouve :
    # le budget d'encres est renseigne la ou il existe, et vide ailleurs — c'est
    # exactement ce que fait BoundedGenerationRequest au moment du formulaire.
    def generating_design_for(entry)
      design = Design.create!(
        user: users(:client), prompt: "une montagne au lever du soleil",
        style: "illustration", technique: entry.key, print_width_cm: 25,
        colors_requested: (entry.default_colors if entry.limited_colors?),
        generator_job_id: "job-42"
      )
      design.start!
      design.save!
      design
    end

    def answer_for(entry)
      {
        "status" => "done", "refinements_left" => 3,
        "result" => {
          "print_file" => entry.file_name, "colors" => entry.default_colors,
          "inks" => 1, "palette" => [ { "hex" => "#1F5F7A" } ], "warnings" => [],
          "stats" => { "paths" => 12, "dpi" => entry.dpi },
          "prompt_used" => "a mountain at sunrise", "subject" => "a mountain", "seed" => 7
        }
      }
    end

    def stub_file(name, body)
      stub_request(:get, %r{/jobs/job-42/#{Regexp.escape(name)}}).to_return(body: body)
    end

    def vector_answer
      {
        "status" => "done", "refinements_left" => 3,
        "result" => {
          "print_file" => "design.svg", "inks" => 1,
          "palette" => [ { "hex" => "#1F5F7A" } ], "warnings" => [],
          "stats" => { "paths" => 12, "opaque_share" => 0.4 },
          "prompt_used" => "screen print separation artwork, a mountain",
          "subject" => "a mountain", "seed" => 7
        }
      }
    end

    def raster_answer
      {
        "status" => "done", "refinements_left" => 3,
        "result" => {
          "print_file" => "print.png", "palette" => [], "warnings" => [],
          "stats" => { "width_px" => 2835, "dpi" => 300, "net_width_cm" => 13 },
          "prompt_used" => "detailed illustration, a mountain", "seed" => 8
        }
      }
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end

    def two_colour_svg
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">) +
        %(<path d="M0 0h5v10H0z" fill="#1F5F7A"/><path d="M5 0h5v10H5z" fill="#E4572E"/></svg>)
    end

    # The smallest valid PNG: one transparent pixel.
    def png
      Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )
    end
end
