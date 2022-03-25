module ROmniture

  # Report response class.
  #
  # This class is responsible for downloading a Report Request,
  # splitting the json into records, and mapping each recordset
  # through the provided map function.

  class ReportResponse

    def initialize(shared_secret=nil, user_name=nil, iss=nil, sub=nil, api_key=nil, private_key=nil, client_id=nil, client_secret=nil, request=nil,map_function=nil,gzip_as_str=false,ignore_header=false)
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO
      @shared_secret = shared_secret
      @username = user_name
      @request = request
      @gzip_as_str = gzip_as_str
      @ignore_header = ignore_header
      @iss = iss
      @sub = sub
      @api_key = api_key
      @private_key = private_key
      @client_id = client_id
      @client_secret = client_secret

      @reportID = JSON.parse(@request.body)["reportID"]

      @logger.info("RResponse @gzip_as_str #{@gzip_as_str}")
      # Simply print records if mapping function not provided.
      if map_function.nil?
        @map_function = lambda do |records|
          @logger.info("[recordset] found")
        end
      else
        @map_function = map_function
      end

      @page_count = 1
      @header = false
      @csv_header = []
      @csv_rows = []
      @metric_types = []
      @retries = 20
      @wio = StringIO.new("w:bom|utf-8")
      if !@request.nil?
        download
        process_buffer
      end
    end

    def get_gzip_data
      @wio.string
    end

    def parse_breakdown(data_chunk)
      v = nil
      stack = [data_chunk]
      begin
        while not stack.empty?
          v = stack.pop
          chunk = v[0]
          value = v[1]
          breakdowns =  chunk["breakdown"]
          counts = chunk["counts"]
          value = value + ["\"#{chunk["name"]}\""]
          begin
            if counts.present?
              if @metric_types.length!=counts.length
                @logger.info("Invalid metric + count length for Report #{@reportID} page_count=#{@page_count} , metric-len = #{@metric_types.length}, count-len = #{counts.length} @metric_types = #{@metric_types}  counts = #{counts} ")
              else
                metric_counts = counts.each_with_index.map do |count, index|
                  if @metric_types[index][:type]=="number" || @metric_types[index][:type]=="currency"
                    @metric_types[index][:decimals]==0 ? count.to_i : count.to_f
                  else
                    count
                  end
                end
                s = value.join(",") +","+ metric_counts.join(",")
                @csv_rows << s
              end
              value.pop
            end
            if breakdowns.present?
              breakdowns.each do |breakdown|
                stack.append([breakdown,value])
              end
            end
          rescue Exception => ex
            stored_error = ex.backtrace.join("###")
            @logger.info("Exception V4 Report parse_breakdown for Report #{@reportID} @metric_types  #{@metric_types} counts #{counts} page_count=#{@page_count} error #{stored_error}  in breakdown #{breakdowns}")
            return
          end
        end
      rescue Exception => ex
        stored_error = ex.backtrace.join("###")
        @logger.info("Exception V4 Report parse_breakdown for Report #{@reportID} error #{stored_error} with value v=#{v} page_count=#{@page_count} ")
        return
      end
    end


    def process_chunk(response)
      data = response["data"]
      metrics = response["metrics"]
      breakdowns = response["elements"]
      if @csv_header.empty?
        @csv_header << "\"Hour\""
        if breakdowns.present?
          breakdowns.each do |breakdown|
            #TODO ignore breakdown=inside your site for internal references
            @csv_header << "\"#{breakdown["name"]}\""
          end
        end
        if metrics.present?
          metrics.each do |metric|
            matches = /event[0-9]+/.match(metric["id"])
            evar_matches = /evar[0-9]+/.match(metric["id"])
            if (matches and matches.length) || (evar_matches and evar_matches.length)
              @csv_header << "\"#{metric["name"]} (#{metric["id"]})\""
            else
              @csv_header << "\"#{metric["name"]}\""
            end
            @metric_types << {"type": metric["type"], "decimals": metric["decimals"], "name": metric["name"]}
          end
        end
        @logger.info("V4 Report Headers #{@csv_header} for Report #{@reportID} ignore_header #{@ignore_header}")
      end

      value = []
      if data.present?
        data.each  do |chunk|
          if @csv_rows.empty? and !@ignore_header
            if chunk["name"].include?("Hour") #Update granularity in header as response doesn't include the report's granularity level type
              @csv_header[0]= "\"Hour\""
            else
              @csv_header[0]= "\"Date\""
            end
            @csv_rows << @csv_header.join(",")
          end
          parse_breakdown([chunk,value])
        end
      end
      if @csv_rows.empty? and !@ignore_header #Just incase the records are empty, we default it to "Hour"
        @csv_header[0]= "\"Hour\""
        @csv_rows << @csv_header.join(",")
      end
      @page_count += 1
    end

    def generate_nonce
      @nonce          = Digest::MD5.new.hexdigest(rand().to_s)
      tz_aware_local_date = Time.zone.now
      utc_date            = tz_aware_local_date.utc
      @created            = utc_date.strftime("%Y-%m-%dT%H:%M:%SZ")
      @combined_string = @nonce + @created + @shared_secret
      @sha1_string     = Digest::SHA1.new.hexdigest(@combined_string)
      @password       = Base64.encode64(@sha1_string).to_s.chomp("\n")
    end

    def request_bearer_token
      payload = {"exp": (DateTime.now() + 1.minute).to_i,"iss": @iss,
                 "sub": @sub,
                 "https://ims-na1.adobelogin.com/s/ent_analytics_bulk_ingest_sdk":true,
                 "aud": "https://ims-na1.adobelogin.com/c/#{@api_key}"}

      jwt_token = JWT.encode payload, @private_key, 'RS256'
      url = "https://ims-na1.adobelogin.com/ims/exchange/jwt"
      request = HTTPI::Request.new
      request.read_timeout=300
      request.url = url
      request.content_type = 'application/x-www-form-urlencoded'
      request.set_form_data('client_id' => "#{@client_id}", "client_secret" => "#{@client_secret}", "jwt_token" => "#{jwt_token}")
      response = HTTPI.post(request)
      if response.code != 200
        log(Logger::ERROR, "JWT Request failed and returned with response code: #{response.code} #{response.body}")
      end
      response.body
    end

    def request_headers
      if @iss.present? and @sub.present?
        token = request_bearer_token
        {
          "Authorization" => "Bearer #{token}"
        }
      else
        {
            "X-WSSE" => "UsernameToken Username=\"#{@username}\", PasswordDigest=\"#{@password}\", Nonce=\"#{@nonce}\", Created=\"#{@created}\"",
            'Content-Type' => 'application/json'   #Added by ROB on 2013-08-22 because the Adobe Social API seems to require this be set
        }
      end
    end

    private

    # Initiates the download
    def download
      begin
          generate_nonce
          request = HTTPI::Request.new
          request.read_timeout=600 #Wait for 10 minutes for long adobe reports
          request.url = @request.url
          request.headers = request_headers
          request.body = @request.body
          response = HTTPI.post(request)

          @logger.info("V4 Report download for #{@reportID} with response code #{response.code} #{@ignore_header}")
          if response.code >= 400
            @logger.error("Request failed and returned with response code: #{response.code} => for #{@reportID} => #{response.body}")
            raise "Request failed and returned with response code: #{response.code} for #{@request.body} => #{response.body}"
          end

          result = JSON.parse(response.body)["report"]
          @logger.info("V4 Report downloaded for #{@reportID}, total pages : #{result["totalPages"]} currentPage: #{@page_count} ")

          process_chunk(result)

          @logger.info("V4 Report processed for #{@reportID} total pages : #{result["totalPages"]} currentPage: #{@page_count} ")
          if @page_count <= result["totalPages"]
            @request.body = {"reportID" => @reportID,"page" => @page_count}.to_json
            download
          end
      rescue Exception => ex
        stored_error = ex.backtrace.join("###")
        @logger.info("Exception V4 Report downloading for for Report #{@reportID}, Retrying #{@retries}, body= #{@request.body}, page_count=#{@page_count} error=#{stored_error}")
        if (@retries -= 1) >= 0
          sleep 10
          retry
        end
      end
    end


    def process_buffer
      if @gzip_as_str
        begin
          w_gz = Zlib::GzipWriter.new(@wio)
          w_gz.write(@csv_rows.join("\n"))
        ensure
          w_gz.close
        end
      else
        success = false
          if !@csv_rows.empty?
            data = CSV.parse(@csv_rows.join("\n"), :headers => !@ignore_header, skip_blanks: true) #TODO try to remove CSV parse and provide direct dicts
            if !data.empty?
              @map_function.call(data)
            end
            success = true
          end
        success
      end
    end

  end
end