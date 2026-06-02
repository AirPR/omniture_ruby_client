module ROmniture
  class Client
    class V2
      DEFAULT_API_BASE_URL = "https://analytics.adobe.io/api/"

      def initialize(base_client, options = {})
        raise ArgumentError, "base_client is required for V2 client" if base_client.nil?

        @base = base_client
        @verify_mode = options[:verify_mode] ? options[:verify_mode] : false
        @api_key = options[:api_key]
        @scope = options[:scope]
        @iss = options[:iss]
        @sub = options[:sub]
        @global_company_id = options[:global_company_id]
        @api_base_url = options[:api_base_url] || DEFAULT_API_BASE_URL
      end

      def request(endpoint, parameters = {})
        response = send_request(endpoint, parameters)

        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => pe
          @base.send(:log, Logger::ERROR, pe)
          response.body
        end
      end

      def request_get(endpoint, parameters = {})
        response = send_get_request(endpoint, parameters)

        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => pe
          @base.send(:log, Logger::ERROR, pe)
          response.body
        end
      end

      def request_put(endpoint, parameters = {})
        response = send_put_request(endpoint, parameters)

        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => pe
          @base.send(:log, Logger::ERROR, pe)
          response.body
        end
      end

      def get_report(endpoint, parameters = {})
        if endpoint.to_s.start_with?("Report.")
          raise NotImplementedError, "V2 client does not support Report.Queue* flow. Use #request with 2.0 endpoints."
        end

        request(endpoint, parameters)
      end

      # Supports:
      #   get_reports(payload_hash)
      #   get_reports("/{globalCompanyId}/reports", payload_hash)
      def get_reports(endpoint_or_payload, parameters = nil)
        if endpoint_or_payload.is_a?(Hash) && parameters.nil?
          endpoint = default_reports_endpoint
          payload = endpoint_or_payload
        else
          endpoint = endpoint_or_payload
          payload = parameters || {}
        end

        get_report(endpoint, payload)
      end

      # Data Warehouse v2 helpers.
      def create_data_warehouse_scheduled_request(payload)
        request(default_data_warehouse_scheduled_endpoint, payload)
      end

      def get_data_warehouse_scheduled_requests(parameters = {})
        request_get(default_data_warehouse_scheduled_endpoint, parameters)
      end

      def get_data_warehouse_scheduled_request(uuid)
        request_get("#{default_data_warehouse_scheduled_endpoint}/#{uuid}", {})
      end

      def update_data_warehouse_scheduled_request(uuid, payload)
        request_put("#{default_data_warehouse_scheduled_endpoint}/#{uuid}", payload)
      end

      def get_data_warehouse_reports(parameters = {})
        request_get(default_data_warehouse_report_endpoint, parameters)
      end

      def get_data_warehouse_report(report_uuid)
        request_get("#{default_data_warehouse_report_endpoint}/#{report_uuid}", {})
      end

      def update_data_warehouse_report(report_uuid, payload)
        request_put("#{default_data_warehouse_report_endpoint}/#{report_uuid}", payload)
      end

      # Keep method surface compatible for callers switching by flags.
      def get_dw_result(url, &block)
        @base.get_dw_result(url, &block)
      end

      def get_result_as_gzip_str(url, ignore_header, &block)
        @base.get_result_as_gzip_str(url, ignore_header, &block)
      end

      def request_partitioned_data(method, parameters = {}, is_partitioned = false, partition = 0, total_partitions = 24)
        @base.request_partitioned_data(method, parameters, is_partitioned, partition, total_partitions)
      end

      def insert_request(data)
        @base.insert_request(data)
      end

      def flatten_response(resp)
        @base.flatten_response(resp)
      end

      private

      def send_request(endpoint, data)
        validate_report_breakdown_filters!(endpoint, data)

        @base.send(:log, Logger::INFO, "[v2] Requesting #{endpoint} for #{data}...")

        request = HTTPI::Request.new
        request.read_timeout = 300
        request.auth.ssl.verify_mode = @verify_mode if @verify_mode

        request.url = normalized_v2_url(endpoint)
        request.headers = request_headers
        request.body = data.to_json
        response = HTTPI.post(request)

        if response.code >= 400
          @base.send(:log, Logger::ERROR, "[v2] Request failed with response code #{response.code} #{response.body}")
          raise "[v2] Request failed with response code #{response.code} #{response.body}"
        end

        @base.send(:log, Logger::INFO, "[v2] Server responded with response code #{response.code}")
        response
      end

      def send_get_request(endpoint, params)
        @base.send(:log, Logger::INFO, "[v2] GET #{endpoint} with #{params}...")

        request = HTTPI::Request.new
        request.read_timeout = 300
        request.auth.ssl.verify_mode = @verify_mode if @verify_mode

        request.url = normalized_v2_url(endpoint)
        request.headers = request_headers
        request.query = params if params.respond_to?(:empty?) ? !params.empty? : params

        response = HTTPI.get(request)

        if response.code >= 400
          @base.send(:log, Logger::ERROR, "[v2] GET failed with response code #{response.code} #{response.body}")
          raise "[v2] GET failed with response code #{response.code} #{response.body}"
        end

        @base.send(:log, Logger::INFO, "[v2] Server responded with response code #{response.code}")
        response
      end

      def send_put_request(endpoint, data)
        @base.send(:log, Logger::INFO, "[v2] PUT #{endpoint} for #{data}...")

        request = HTTPI::Request.new
        request.read_timeout = 300
        request.auth.ssl.verify_mode = @verify_mode if @verify_mode

        request.url = normalized_v2_url(endpoint)
        request.headers = request_headers
        request.body = data.to_json
        response = HTTPI.put(request)

        if response.code >= 400
          @base.send(:log, Logger::ERROR, "[v2] PUT failed with response code #{response.code} #{response.body}")
          raise "[v2] PUT failed with response code #{response.code} #{response.body}"
        end

        @base.send(:log, Logger::INFO, "[v2] Server responded with response code #{response.code}")
        response
      end

      def validate_report_breakdown_filters!(endpoint, data)
        return unless endpoint.to_s.end_with?("/reports") || endpoint.to_s.end_with?("reports")
        return unless data.is_a?(Hash)

        metric_filters = data.dig("metricContainer", "metricFilters") || data.dig(:metricContainer, :metricFilters)
        return unless metric_filters.is_a?(Array)

        invalid_filter = metric_filters.find do |filter|
          type = filter["type"] || filter[:type]
          next false unless type.to_s == "breakdown"

          item_id = filter["itemId"] || filter[:itemId]
          item_id.to_s.strip.empty?
        end

        return unless invalid_filter

        filter_id = invalid_filter["id"] || invalid_filter[:id]
        dimension = invalid_filter["dimension"] || invalid_filter[:dimension]
        raise ArgumentError,
              "Invalid v2 report payload: breakdown metricFilter id=#{filter_id} dimension=#{dimension} is missing itemId. " \
              "Adobe v2 requires itemId for each breakdown filter. Fetch parent rows first, then pass the selected row itemId."
      end

      def normalized_v2_url(endpoint)
        normalized = endpoint.to_s.sub(%r{\A/+}, '')

        if @global_company_id.to_s.strip != '' && !normalized.start_with?("#{@global_company_id}/")
          normalized = "#{@global_company_id}/#{normalized}"
        end

        normalized = "/#{normalized}"
        "#{@api_base_url.chomp('/')}#{normalized}"
      end

      def request_headers
        token = v2_access_token

        headers = {
          "Authorization" => "Bearer #{token}",
          "Content-Type" => "application/json",
          "x-api-key" => @api_key
        }

        headers["x-proxy-global-company-id"] = @global_company_id if @global_company_id
        headers
      end

      def v2_access_token
        return @base.send(:request_bearer_token) if @iss.present? && @sub.present?
        return @base.send(:request_bearer_token_oauth) if @scope.present?

        raise ArgumentError, "V2 client requires OAuth scope or JWT credentials (iss/sub)."
      end

      def default_reports_endpoint
        raise ArgumentError, "global_company_id is required for V2 get_reports(payload)." if @global_company_id.to_s.strip.empty?

        "/#{@global_company_id}/reports"
      end

      def default_data_warehouse_scheduled_endpoint
        raise ArgumentError, "global_company_id is required for V2 Data Warehouse endpoints." if @global_company_id.to_s.strip.empty?

        "/#{@global_company_id}/data_warehouse/scheduled"
      end

      def default_data_warehouse_report_endpoint
        raise ArgumentError, "global_company_id is required for V2 Data Warehouse endpoints." if @global_company_id.to_s.strip.empty?

        "/#{@global_company_id}/data_warehouse/report"
      end
    end
  end
end