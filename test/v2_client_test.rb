require "rubygems"
require "minitest/autorun"
require "ostruct"

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "romniture"

class V2ClientTest < Minitest::Test
  class FakeBase
    attr_reader :oauth_calls, :jwt_calls

    def initialize
      @oauth_calls = 0
      @jwt_calls = 0
    end

    def request_bearer_token_oauth
      @oauth_calls += 1
      "oauth-token"
    end

    def request_bearer_token
      @jwt_calls += 1
      "jwt-token"
    end

    def log(*_args)
      nil
    end

    def get_dw_result(*_args)
      :ok
    end

    def get_result_as_gzip_str(*_args)
      :ok
    end

    def request_partitioned_data(*_args)
      :ok
    end

    def insert_request(*_args)
      :ok
    end

    def flatten_response(*_args)
      :ok
    end
  end

  def setup
    @original_httpi_post = HTTPI.method(:post)
    @original_httpi_get = HTTPI.method(:get)
  end

  def teardown
    HTTPI.singleton_class.send(:define_method, :post, @original_httpi_post)
    HTTPI.singleton_class.send(:define_method, :get, @original_httpi_get)
  end

  def test_initialize_requires_base_client
    error = assert_raises(ArgumentError) do
      ROmniture::Client::V2.new(nil, {})
    end

    assert_match("base_client is required", error.message)
  end

  def test_get_report_rejects_legacy_report_queue_methods
    client = ROmniture::Client::V2.new(FakeBase.new, scope: "scope")

    error = assert_raises(NotImplementedError) do
      client.get_report("Report.QueueOvertime", {})
    end

    assert_match("does not support Report.Queue", error.message)
  end

  def test_get_reports_without_endpoint_uses_default_company_reports_url
    fake_base = FakeBase.new
    captured = {}

    HTTPI.singleton_class.send(:define_method, :post) do |request|
      captured[:url] = request.url
      captured[:headers] = request.headers
      captured[:body] = request.body
      OpenStruct.new(code: 200, body: '{"ok":true}')
    end

    client = ROmniture::Client::V2.new(
      fake_base,
      scope: "analytics_bulk_ingest",
      api_key: "test-key",
      global_company_id: "myCompany"
    )

    response = client.get_reports({"rsid" => "suite"})
    headers_dump = captured[:headers].inspect

    assert_equal true, response["ok"]
    assert_equal "https://analytics.adobe.io/api/myCompany/reports", captured[:url].to_s
    assert_includes headers_dump, "Authorization"
    assert_includes headers_dump, "Bearer oauth-token"
    assert_includes headers_dump, "x-api-key"
    assert_includes headers_dump, "test-key"
    assert_includes headers_dump, "x-proxy-global-company-id"
    assert_includes headers_dump, "myCompany"
    assert_equal "{\"rsid\":\"suite\"}", captured[:body]
    assert_equal 1, fake_base.oauth_calls
    assert_equal 0, fake_base.jwt_calls
  end

  def test_get_reports_requires_global_company_id_when_payload_only
    client = ROmniture::Client::V2.new(FakeBase.new, scope: "scope")

    error = assert_raises(ArgumentError) do
      client.get_reports({"rsid" => "suite"})
    end

    assert_match("global_company_id is required", error.message)
  end

  def test_request_requires_auth_configuration
    fake_base = FakeBase.new

    HTTPI.singleton_class.send(:define_method, :post) do |_request|
      OpenStruct.new(code: 200, body: '{"ok":true}')
    end

    client = ROmniture::Client::V2.new(fake_base, global_company_id: "myCompany")

    error = assert_raises(ArgumentError) do
      client.request("/myCompany/reports", {})
    end

    assert_match("requires OAuth scope or JWT credentials", error.message)
  end

  def test_breakdown_filter_requires_item_id
    fake_base = FakeBase.new

    HTTPI.singleton_class.send(:define_method, :post) do |_request|
      flunk("HTTPI.post should not be called when payload validation fails")
    end

    client = ROmniture::Client::V2.new(
      fake_base,
      scope: "analytics_bulk_ingest",
      api_key: "test-key",
      global_company_id: "myCompany"
    )

    payload = {
      "metricContainer" => {
        "metricFilters" => [
          {
            "id" => "0",
            "type" => "breakdown",
            "dimension" => "variables/evar1"
          }
        ]
      }
    }

    error = assert_raises(ArgumentError) do
      client.get_reports(payload)
    end

    assert_match("missing itemId", error.message)
  end

  def test_request_get_uses_query_parameters
    fake_base = FakeBase.new
    captured = {}

    HTTPI.singleton_class.send(:define_method, :get) do |request|
      captured[:url] = request.url
      captured[:query] = request.query
      captured[:headers] = request.headers
      OpenStruct.new(code: 200, body: '[{"id":"metrics/event1","name":"Event 1"}]')
    end

    client = ROmniture::Client::V2.new(
      fake_base,
      scope: "analytics_bulk_ingest",
      api_key: "test-key",
      global_company_id: "myCompany"
    )

    response = client.request_get("metrics", {"rsid" => "suite"})

    assert_equal "https://analytics.adobe.io/api/myCompany/metrics?rsid=suite", captured[:url].to_s
    assert_equal "metrics/event1", response.first["id"]
  end
end
