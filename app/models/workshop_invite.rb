# A numbered client sheet: one QR code, one client, once (decided on
# 09/10/2026). Unlike the poster, which admits anyone who has never been the
# shop's client, a sheet is the shop handing its agreement to one person — so
# it admits a former client too, and then it is spent.
class WorkshopInvite < ApplicationRecord
  BATCH_MAX = 50

  belongs_to :printer
  belongs_to :used_by, class_name: "User", optional: true

  scope :usable, -> { where(used_at: nil, revoked_at: nil) }
  scope :in_order, -> { order(:number) }

  def self.new_code = SecureRandom.alphanumeric(12).downcase

  # A batch of `count` sheets, numbered after the shop's last one.
  def self.issue!(printer, count)
    count = count.to_i.clamp(1, BATCH_MAX)

    transaction do
      printer.lock!
      last = where(printer: printer).maximum(:number).to_i
      batch = where(printer: printer).maximum(:batch).to_i + 1
      rows = Array.new(count) do |index|
        { printer_id: printer.id, batch: batch, number: last + index + 1, code: new_code,
          created_at: Time.current, updated_at: Time.current }
      end
      insert_all!(rows)
      batch
    end
  end

  def used? = used_at.present?
  def revoked? = revoked_at.present?
  def usable? = !used? && !revoked?

  # Spent by `client`. True only for the one call that spent it: two sign-ups
  # racing on the same sheet cannot both get in.
  def consume!(client)
    self.class.usable.where(id: id)
        .update_all(used_by_id: client.id, used_at: Time.current, updated_at: Time.current) == 1
  end

  def revoke! = update!(revoked_at: Time.current)
end
