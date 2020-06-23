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
          @logger.info("[recordset]")
          records.each do |record|
            @logger.info(record.to_hash)
          end
          @logger.info("[/recordset]")
        end
      else
        @map_function = map_function
      end

      @page_count = 1
      @header = false
      @csv_header = []
      @csv_rows = []
      if !@request.nil?
        download
        process_buffer
      end
    end

    def parse_breakdown(breakdown,value)
      breakdown.each do |chunk|
        value = value + (chunk[:name])
        if chunk.key?(:breakdown)
          value = value + append(parse_breakdown(chunk[:breakdown],value))
        end
      end
      value
    end

    def process_chunk(response)
      @logger.info("Server responded with response total pages #{response["totalPages"]}.")
      if response["totalPages"] < @page_count
        data = response["data"]
        metrics = response["metrics"]
        breakdowns = response["elements"]
        unless @csv_header.present?
          @csv_header << "Hour"
          breakdowns.each do |breakdown|
            #TODO ignore breakdown=inside your site for internal references
            @csv_header << breakdown["name"]
          end
          metrics.each do |metric|
            matches = /(event[0-9]+)/.match(metric["id"]) #custom event similar to csv
            if matches and matches.length
              @csv_header << "(#{matches[1]})"
            else
              @csv_header << metric["name"]
            end
          end
          @csv_rows << @csv_header.join(",")
        end
        data.each  do |chunk|
          datetime = chunk["name"]
          value = [datetime]
          if chunk.key?("breakdown")
              value = value + (chunk["name"])
              value = value + parse_breakdown(chunk["breakdown"],value)
          end
          if chunk.key?("breakdown")
              value = value + chunk["counts"]
          end
          @csv_rows << value.join(",")
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

      @logger.info("report download for #{@request.body} #{response.code}")
      if response.code >= 400
        @logger.error("Request failed and returned with response code: #{response.code}\n\n#{response.body}")
        raise "Request failed and returned with response code: #{response.code}\n\n#{response.body}" 
      end

      result = JSON.parse(response.body)["report"]
      process_chunk(result)
      if result["totalPages"] > @page_count
        @request.body = {:reportID => @request.body[:reportID],:page => @page_count+1}
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