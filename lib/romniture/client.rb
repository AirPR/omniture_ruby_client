

module ROmniture
  
  class Client

    DEFAULT_REPORT_WAIT_TIME = 0.25
    DEFAULT_API_VERSION = "1.3"
    REPORT_ID = "reportID"

    V4_API_VERSION = "1.4"
    
    def initialize(username, shared_secret, environment, options={})
      @username       = username
      @shared_secret  = shared_secret
      @api_version    = options[:api_version] ? options[:api_version] : DEFAULT_API_VERSION
      @environment    = environment.is_a?(Symbol) ? environments[environment] : environment.to_s
      @wait_time      = options[:wait_time] ? options[:wait_time] : DEFAULT_REPORT_WAIT_TIME
      @log            = options[:log] ? options[:log] : false
      @verify_mode    = options[:verify_mode] ? options[:verify_mode] : false
      #@insert_url     = "https://airpr.d1.sc.omtrdc.net/b/ss/airprptnrdev/6/"
      @insert_url     = ''
      HTTPI.log       = true
    end

    def environments
      {
        :san_jose       => "https://api.omniture.com/admin/#{@api_version}/rest/",
        :dallas         => "https://api2.omniture.com/admin/#{@api_version}/rest/",
        :london         => "https://api3.omniture.com/admin/#{@api_version}/rest/",
        :san_jose_beta  => "https://beta-api.omniture.com/admin/#{@api_version}/rest/",
        :dallas_beta    => "https://beta-api2.omniture.com/admin/#{@api_version}/rest/",
        :sandbox        => "https://api-sbx1.omniture.com/admin/#{@api_version}/rest/"
      }
    end

    def request(method, parameters = {})
      response = send_request(method, parameters)

      begin
        log(Logger::INFO, "request method #{method} #{response} ")
        JSON.parse(response.body)
      rescue JSON::ParserError => pe
        log(Logger::ERROR, pe)
        response.body
      rescue Exception => e
        log(Logger::ERROR, e)
        log(Logger::ERROR, "Error in request response:\n#{response.body}")
        raise "Error in request response:\n#{response.body}"
      end
    end
    # insert_request: Inserts data to Catalyst.
    #
    # data. dict. The field values to insert. See 
    #   https://marketing.adobe.com/developer/en_US/documentation/data-insertion/r-supported-tags
    #
    # returns dict. The server response.

    def insert_request(data)
      # Validate the visitorID and convert to hex if necessary 
      data['visitorID'] = ROmniture::VisitorID.new(data['visitorID']).dec
      response = send_insert_request(data)

      begin
        parsed = ActiveSupport::XmlMini::parse(response.body)
        status = parsed['status']['__content__']
      rescue Exception => e
        parsed = {}
        log(Logger::ERROR, "Error in request response:\n#{response.body}")
        log(Logger::ERROR, e.to_s)
      end

      log(Logger::INFO, "Successfully inserted for #{data['visitorID']} - #{data['timestamp']}")

      if status != "SUCCESS"
        raise "Insert did not succeed."
      end

      parsed
    end

    def get_report(method, report_description)      
      response = send_request(method, report_description)
      
      json = JSON.parse response.body
      if json["status"] == "queued"
        log(Logger::INFO, "Report with ID (" + json["reportID"].to_s + ") queued.  Now fetching report...")
        return get_queued_report json["reportID"]
      else
        log(Logger::ERROR, "Could not queue report.  Omniture returned with error:\n#{response.body}")
        raise "Could not queue report.  Omniture returned with error:\n#{response.body}"
      end
    end

    # Gets and processes CSV result from Data Warehouse.
    # 
    # Designed to be used in a block. 
    # Returns a set of records for each iteratively processed chunk of body.
    # 
    # Example:
    #
    # client.get_dw_result(data_url) do |records|
    #   @logger.info("[recordset]")
    #   records.each do |record|
    #      @logger.info(record)
    #   end
    #   @logger.info("[/recordset]")
    # end

    def get_dw_result(url, &block)
      generate_nonce
      
      log(Logger::INFO, "get_dw_result Created new nonce: #{@password} for #{url} : #{@api_version}")
      
      request = HTTPI::Request.new

      request.headers = request_headers

      if @verify_mode
        request.auth.ssl.verify_mode = @verify_mode
      end

      if @api_version != V4_API_VERSION
        request.url = url
        ROmniture::DWResponse.new(request, block)
      else
        log(Logger::INFO,@environment + "?method=Report.Get")
        request.url = @environment + "?method=Report.Get"
        log(Logger::INFO, request.url)
        request.body = {REPORT_ID => url['reportID'],:page => 1}.to_json
        log(Logger::INFO,"RRRespomse #{request.body}")
        ROmniture::ReportResponse.new(@shared_secret, @username, request, block)
      end
    end

    def get_result_as_gzip_str(url, &block)
      generate_nonce
      log(Logger::INFO, "get_result_as_gzip_str Created new nonce: #{@password} for #{url}: #{@api_version}")
      request = HTTPI::Request.new
      if @api_version != V4_API_VERSION
        request.url = url
      else
        request.url = @environment + "?method=Report.Get"
        log(Logger::INFO, request.url)
        request.body = {REPORT_ID => url['reportID'],:page => 1}.to_json
      end
      request.headers = request_headers
      if @verify_mode
        request.auth.ssl.verify_mode = @verify_mode
      end
      if V4_API_VERSION == @api_version
        response = ROmniture::ReportResponse.new(@shared_secret, @username, request, block, true)
        response.get_gzip_data
      else
          wio = StringIO.new("w:bom|utf-8")
          begin
            w_gz = Zlib::GzipWriter.new(wio)
            request.on_body do |chunk|
              if chunk
                chunk
                log(Logger::INFO, "get_result_as_gzip_str w_gz.write(chunk) #{chunk}")
              end
            end
            response = HTTPI.post(request)
            log(Logger::INFO, "get_result_as_gzip_str #{response.code} #{response.body}")
            if response.code >= 400
              logger.error("Request failed and returned with response code: #{response.code}\n\n#{response.body}")
              w_gz.close
              raise "Request failed and returned with response code: #{response.code}\n\n#{response.body}"
            end
          ensure
            w_gz.close
          end
          wio.string
        end
    end
    
    attr_writer :log
    
    def log?
      @log != false
    end
    
    def logger
      @logger ||= ::Logger.new(STDOUT)
    end
    
    def log_level
      @log_level ||= ::Logger::INFO
    end
    
    def log(*args)
      level = args.first.is_a?(Numeric) || args.first.is_a?(Symbol) ? args.shift : log_level
      logger.log(level, args.join(" ")) if log?
    end

    # For Trended or Overtime reports, the response from Omniture's API is often deeply nested and difficult to traverse.
    # This function basically denormalizes/flattens the hierarchical structure into a simple array of hashes.
    # So for example, if the top level element is browser, and the second level is page, and the third level is datetime, 
    #   this function produces an array of hashes that each have a "browser", "page", and "datetime" keys along with a 
    #   key for each metric.
    def flatten_response(resp)
      @flattened = []
      report = resp["report"]
      elements = report["elements"].map{|e| e["id"]}
      metrics = report["metrics"].map{|e| e["id"]}

      #For some reason OMTR doesn't list the datetime in the elements list if it is the top-level element, so add it in.
      datetime_index = elements.index{|e| e == "datetime"}
      elements.unshift("datetime") if datetime_index.nil?
      
      flatten_report(report['data'], elements, metrics) 
      @flattened
    end
        
    private
    def flatten_report( data, elements, metrics, current_level = 1, result_row = nil)
      data.each do |current_node|
        if current_level == 1 then result_row = Hash.new else result_row = result_row.clone end
       
        #Get the element at this level and store it in our result row, so this will end up with something like
        # { "browser" => "Google Chrome 25.0" } or { "datetime" => "Fri. 1 Mar. 2013" }
        element_name = elements[current_level-1]
        result_row[element_name] = current_node["name"]

        #If there are still more breakdown levels to work our way down, continue recursively working down them.
        #If not, then we are at the bottom level, so take our result row and save it in the @flattened array.
        if current_node.has_key?("breakdown")
          flatten_report( current_node["breakdown"], elements, metrics, current_level + 1, result_row)
        else
          metrics.each_with_index { |metric, i| result_row[metric] = current_node['counts'][i].to_i }
          @flattened <<  result_row
        end

      end
    end

    ##
    # Converts Adobe "csv" response into a correctly decoded unicode CSV.
    #
    def self.clean_dw_response(body)
      body.force_encoding("UTF-8").gsub(/\xEF\xBB\xBF/, "")
    end

    ##
    # Parses the Data Warehouse CSV file into a list.
    # 
    # param: csv. str. Properly formatted CSV as a string.
    # returns: array.
    #
    def self.parse_dw_csv(csv)
      CSV.parse(csv)

      # ### Alternative parsing method below:
      # if parsed.length > 2
      #   headers = parsed.shift
      #   parsed.each do |row|
      #     record = {}
      #     row.each_with_index do |field_num, field_value|
      #       field_name = headers[field_num]
      #       record[field_name] = field_value
      #     end
      #     yield row
      #   end
      # end
      # parsed
    end

    def send_insert_request(data)
      generate_nonce
      
      log(Logger::INFO, "Created new nonce: #{@password}")
      
      request = HTTPI::Request.new

      data['scXmlVer'] = "1.0"

      xml = data.to_xml(:root => 'request')

      request.url = @insert_url
      request.headers = request_headers
      request.headers['Content-Length'] = xml.length.to_s
      request.body = xml

      if @verify_mode
        request.auth.ssl.verify_mode = @verify_mode
      end

      response = HTTPI.post(request)

      if response.code >= 400
        log(Logger::ERROR, "Request failed and returned with response code: #{response.code}\n\n#{response.body}")
        raise "Request failed and returned with response code: #{response.code}\n\n#{response.body}" 
      end

      log(Logger::INFO, "Server responded with response code #{response.code}.")

      response
    end
    
    def send_request(method, data)
      log(Logger::INFO, "Requesting #{method}...")
      generate_nonce
      
      log(Logger::INFO, "Created new nonce: #{@password}")
      
      request = HTTPI::Request.new

      if @verify_mode
        request.auth.ssl.verify_mode = @verify_mode
      end

      request.url = @environment + "?method=#{method}"
      request.headers = request_headers
      request.body = data.to_json

      response = HTTPI.post(request)
      
      if response.code >= 400 and @version=='1.3'
        log(Logger::ERROR, "Request failed and returned with response code: #{response.code}\n\n#{response.body}")
        raise "Request failed and returned with response code: #{response.code}\n\n#{response.body}" 
      end
      if response.code >= 400
        log(Logger::INFO, "Request failed and responded with response code #{response.code}\n#{response.body}")
      end
      log(Logger::INFO, "Server responded with response code #{response.code}")
      response

    end
    
    def generate_nonce
      @nonce          = Digest::MD5.new.hexdigest(rand().to_s)
      case @api_version
      when "1.3"
        @created        = Time.now.strftime("%Y-%m-%d %H:%M:%SZ")
      when "1.4"
        tz_aware_local_date = Time.zone.now
        utc_date            = tz_aware_local_date.utc
        @created            = utc_date.strftime("%Y-%m-%dT%H:%M:%SZ")
      end
      combined_string = @nonce + @created + @shared_secret
      sha1_string     = Digest::SHA1.new.hexdigest(combined_string)
      @password       = Base64.encode64(sha1_string).to_s.chomp("\n")
    end    

    def request_headers 
      {
        "X-WSSE" => "UsernameToken Username=\"#{@username}\", PasswordDigest=\"#{@password}\", Nonce=\"#{@nonce}\", Created=\"#{@created}\"",
        'Content-Type' => 'application/json'   #Added by ROB on 2013-08-22 because the Adobe Social API seems to require this be set
      }
    end
    
    def get_queued_report(report_id)
      done = false
      error = false
      status = nil
      start_time = Time.now
      end_time = nil

      begin
        response = send_request("Report.GetStatus", {"reportID" => "#{report_id}"})
        log(Logger::INFO, "Checking on status of report #{report_id}...")
        
        json = JSON.parse(response.body)
        status = json["status"]
        
        if status == "done"
          done = true
        elsif status == "failed"
          error = true
        end
        
        sleep @wait_time if !done && !error
      end while !done && !error
      
      if error
        msg = "Unable to get data for report #{report_id}.  Status: #{status}.  Error Code: #{json["error_code"]}.  #{json["error_msg"]}."
        log(Logger::ERROR, msg)
        raise ROmniture::Exceptions::OmnitureReportException.new(json), msg
      end
            
      response = send_request("Report.GetReport", {"reportID" => "#{report_id}"})

      end_time = Time.now
      log(Logger::INFO, "Report with ID #{report_id} has finished processing in #{((end_time - start_time)*1000).to_i} ms")
      
      JSON.parse(response.body)
    end
  end
end
