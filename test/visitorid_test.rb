require 'rubygems'
require 'minitest/autorun'
require 'yaml'

$:.unshift File.expand_path('../../lib', __FILE__)
require 'romniture'

class VisitorIDTest < Minitest::Test

  def setup
    config = YAML::load(File.open("test/config.yml"))
    @ids = config["visitor_id"]
    
  end

  def test_GoodVisitorID
    @ids['good'].each do |id|
      vid = ROmniture::VisitorID.new(id['dec'])
      assert_equal(id['dec'], vid.dec)
      assert_equal(id['hex'], vid.hex)

      vid = ROmniture::VisitorID.new(id['hex'])
      assert_equal(id['dec'], vid.dec)
      assert_equal(id['hex'], vid.hex)
    end
  end
  def test_MismatchedVisitorID
    @ids['mismatch'].each do |id|
      vid = ROmniture::VisitorID.new(id['dec'])
      assert_not_equal(id['hex'], vid.hex)

      vid = ROmniture::VisitorID.new(id['hex'])
      assert_not_equal(id['dec'], vid.dec)
    end
  end
  def test_MalformedVisitorID
    @ids['bad'].each do |id|
      assert_raise(ROmniture::Exceptions::OmnitureVisitorIDException) do
        ROmniture::VisitorID.new(id['dec'])
      end
      assert_raise(ROmniture::Exceptions::OmnitureVisitorIDException) do
        ROmniture::VisitorID.new(id['hex'])
      end
    end
  end

end