require 'rubygems'
require 'minitest/autorun'
require 'yaml'

$:.unshift File.expand_path('../../lib', __FILE__)
require 'romniture'

class ClientTest < Minitest::Test

  def setup
    config = YAML::load(File.open("test/config.yml"))
    @config = config["omniture"]

    @client = ROmniture::Client.new(
      @config["username"],
      @config["shared_secret"],
      @config["environment"],
      :verify_mode => @config['verify_mode'],
      :wait_time => @config["wait_time"]
    )
  end

  def test_simple_request
    response = @client.request('Company.GetReportSuites')

    assert_instance_of Hash, response, "Returned object is not a hash."
    assert(response.has_key?("report_suites"), "Returned hash does not contain any report suites.")
  end

  def test_report_request
    response = @client.get_report "Report.QueueOvertime", {
      "reportDescription" => {
        "reportSuiteID" => "#{@config["report_suite_id"]}",
        "dateFrom" => "2014-10-30",
        "dateTo" => "2014-10-31",
        "metrics" => [{"id" => "pageviews"}]
        }
      }

    assert_instance_of Hash, response, "Returned object is not a hash."
    assert(response["report"].has_key?("data"), "Returned hash has no data!")
  end

  def test_a_bad_request
    # Bad request, mixing commerce and traffic variables
    assert_raise(ROmniture::Exceptions::OmnitureReportException) do
      response = @client.get_report("Report.QueueTrended", {
        "reportDescription" => {
          "reportSuiteID" => @config["report_suite_id"],
          "dateFrom" => "2014-10-30",
          "dateTo" => "2014-10-31",
          "metrics" => [{"id" => "pageviews"}, {"id" => "event11"}],
          "elements" => [{"id" => "siteSection"}]
        }
      })
    end
  end

  def test_return_response_body_on_parse_error
    non_json_response = @client.request('Company.GetTokenCount')
    assert_instance_of String, non_json_response, "Company.GetTokenCount returned #{non_json_response}."
  end
end
