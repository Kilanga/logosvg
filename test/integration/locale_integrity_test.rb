require "test_helper"

# A duplicate key in fr.yml is silent: YAML keeps the last one and drops the
# first, and the screen shows the wrong text — or a whole block vanishes. It
# has happened twice on this project, once at the top level and once nested
# three deep, so it is checked rather than remembered.
class LocaleIntegrityTest < ActiveSupport::TestCase
  PATH = Rails.root.join("config/locales/fr.yml")

  test "no key is written twice at any depth" do
    duplicates = []

    walk(parse_tree) { |path, keys| duplicates.concat(repeated(keys).map { |k| (path + [ k ]).join(".") }) }

    assert_empty duplicates,
                 "clés en double dans fr.yml (la seconde écrase la première) : #{duplicates.join(", ")}"
  end

  private
    # Psych's safe loader silently keeps the last duplicate, so the raw node
    # tree is read instead — it is the only place both keys still exist.
    def parse_tree = Psych.parse(File.read(PATH))

    def walk(node, path = [], &block)
      mapping = find_mapping(node)
      return if mapping.nil?

      keys = mapping.children.each_slice(2).map { |key, _| key.value }
      yield(path, keys)

      mapping.children.each_slice(2) do |key, value|
        walk(value, path + [ key.value ], &block)
      end
    end

    def find_mapping(node)
      return node if node.is_a?(Psych::Nodes::Mapping)
      return find_mapping(node.children.first) if node.respond_to?(:children) && node.children&.any?

      nil
    end

    def repeated(keys) = keys.tally.select { |_, count| count > 1 }.keys
end
