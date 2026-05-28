require "rubygems"
require "minitest/autorun"

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "romniture"

class ClientFactoryTest < Minitest::Test
  def test_builds_v2_client_for_v2_aliases
    ["v2", "2", "2.0"].each do |version|
      client = ROmniture::ClientFactory.build("u", "s", :san_jose, client_version: version)
      assert_instance_of ROmniture::Client::V2, client
    end
  end

  def test_builds_legacy_client_by_default
    client = ROmniture::ClientFactory.build("u", "s", :san_jose, {})
    assert_instance_of ROmniture::Client, client
    refute_instance_of ROmniture::Client::V2, client
  end

  def test_unknown_version_raises
    error = assert_raises(ArgumentError) do
      ROmniture::ClientFactory.build("u", "s", :san_jose, client_version: "v3")
    end

    assert_match("Unknown client version", error.message)
  end
end
