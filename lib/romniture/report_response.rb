module ROmniture

  # Report response class.
  #
  # This class is responsible for downloading a Report Request,
  # splitting the json into records, and mapping each recordset
  # through the provided map function. 
  
  class ReportResponse


    def initialize(shared_secret=nil, user_name=nil, request=nil,map_function=nil)
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO
      @shared_secret = shared_secret
      @username = user_name
      @request = request
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
      @metric_types=[]
      if !@request.nil?
        download
        process_buffer
      end
    end

    def parse_breakdown(chunk,value)
      value = value + [chunk["name"]]
      breakdowns =  chunk["breakdown"]
      counts = chunk["counts"]
      if counts.present?
        metric_counts = counts.each_with_index.map do |count, index|
          @logger.info("MEtric count Type : #{@metric_types[index]["type"]} for #{count}")
          if @metric_types[index]["type"]=="number" || @metric_types[index]["type"]=="currency"
            if @metric_types[index]["decimals"]==0 ? count.to_i : count.to_f
          else
            count
          end
          end
        end
        @logger.info("MEtric counts  : #{metric_counts}")
        s = value.join(",") +","+ metric_counts.join(",")
        @csv_rows << s
        value.pop
        return
      end
      if breakdowns.present?
        breakdowns.each do |breakdown|
          parse_breakdown(breakdown,value)
        end
      end
    end

    def process_chunk(response)
      @logger.info("Server responded with response total pages #{response["totalPages"]}.")
      data = response["data"]
      metrics = response["metrics"]
      breakdowns = response["elements"]
      @logger.info("Header rows : #{@csv_header}")
      @logger.info("CSV rows : #{@csv_rows}")
      unless @csv_header.present?
        @csv_header << "Hour"
        if breakdowns.present?
          breakdowns.each do |breakdown|
            #TODO ignore breakdown=inside your site for internal references
            @csv_header << breakdown["name"]
          end
        end
        if metrics.present?
          metrics.each do |metric|
            matches = /(event[0-9]+)/.match(metric["id"]) #custom event similar to csv
            if matches and matches.length
              @csv_header << "#{metric["name"]}(#{matches[1]})"
            else
              @csv_header << metric["name"]
            end
            @metric_types << {"type": metric["type"], "decimal": metric["decimal"]}
          end
        end
        @csv_rows << @csv_header.join(",")
      end
      @logger.info("Header rows : #{@csv_header}")
      @logger.info("CSV Header rows : #{@csv_rows}")
      value = []
      if data.present?
        data.each  do |chunk|
          parse_breakdown(chunk,value)
        end
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

    def request_headers
      {
          "X-WSSE" => "UsernameToken Username=\"#{@username}\", PasswordDigest=\"#{@password}\", Nonce=\"#{@nonce}\", Created=\"#{@created}\"",
          'Content-Type' => 'application/json'   #Added by ROB on 2013-08-22 because the Adobe Social API seems to require this be set
      }
    end

    private

    # Initiates the download
    def download
      generate_nonce
      @request.headers = request_headers
      response = HTTPI.post(@request)
      body = JSON.parse(@request.body)
      @logger.info("report download for #{body} #{response.code}")
      if response.code >= 400
        @logger.error("Request failed and returned with response code: #{response.code}\n\n#{response.body}")
        raise "Request failed and returned with response code: #{response.code}\n\n#{response.body}" 
      end

      result = JSON.parse(response.body)["report"]
      process_chunk(result)
      if @page_count <= result["totalPages"]
        @logger.info("reportID: #{body["reportID"]} count: #{@page_count}")
        @request.body = {"reportID" => body["reportID"],"page" => @page_count}.to_json
        download
      end
    end


    def process_buffer
      success = false
      if !@csv_rows.empty?
        data = CSV.parse(@csv_rows.join("\n"), :headers => true, skip_blanks: true) #TODO try to remove CSV parse and provide direct dicts
        if !data.empty?
          @map_function.call(data)
        end
        success = true
      end
      success
    end

  end
end