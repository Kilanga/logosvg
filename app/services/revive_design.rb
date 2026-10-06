# Gives a ready design a job on the generation machine again.
#
# The machine keeps a design for an hour, and only until it is switched off —
# which, since the GPU is started by hand, happens every day. A client coming
# back tomorrow to retouch yesterday's design found the service had forgotten
# it, and the reprise failed. The application kept the original image and the
# description: it hands them back, and stores the new job id on the design.
class ReviveDesign
  # Nothing to hand back: a design stored before the original image was kept.
  Unrecoverable = Class.new(StandardError)

  def self.call(design) = new(design).call

  def initialize(design)
    @design = design
  end

  def call
    raise Unrecoverable, "no source image kept for #{@design.token}" unless @design.source_png.attached?

    answer = GeneratorClient.new.restore(@design, used_refinements: @design.refinements_used)
    @design.update!(generator_job_id: answer.fetch("job_id"))
    @design
  end
end
