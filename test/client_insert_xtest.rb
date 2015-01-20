require 'rubygems'
require 'minitest/autorun'
require 'yaml'
#require 'pry'

$:.unshift File.expand_path('../../lib', __FILE__)
require 'romniture'

class ClientInsertTest < Minitest::Test

  def setup
    config = YAML::load(File.open("test/config.yml"))
    @config = config["omniture"]
    @ids = config['data_insert']

    @client = ROmniture::Client.new(
      @config["username"],
      @config["shared_secret"],
      @config["environment"],
      :verify_mode => @config['verify_mode'],
      :wait_time => @config["wait_time"]
    )

  end

  def test_insert_good
    @ids['good'].each do |record|
      response = @client.insert_request(record)
      assert_instance_of Hash, response, "Returned object is not a hash."
      assert(response.has_key?("status"), "Returned hash does not contain status.")
    end
  end

end