module ROmniture

  # Report response class.
  #
  # This class is responsible for downloading a Report Request,
  # splitting the json into records, and mapping each recordset
  # through the provided map function. 
  
  class ReportResponse


    def initialize(request=nil, map_function=nil)
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO
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
      if !request.nil?
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
      if response[:totalPages] < @page_count
        data = response[:response][:report][:data]
        metrics = response[:response][:report][:metrics]
        breakdowns = response[:response][:report][:elements]
        unless @csv_header.present?
          @csv_header << "Hour"
          breakdowns.each do |breakdown|
            #TODO ignore breakdown=inside your site for internal references
            @csv_header << breakdown[:name]
          end
          metrics.each do |metric|
            matches = /(event[0-9]+)/.match(metric[:id]) #custom event similar to csv
            if matches and matches.length
              @csv_header << "(#{matches[1]})"
            else
              @csv_header << metric[:name]
            end
          end
          @csv_rows << @csv_header.join(",")
        end
        data.each  do |chunk|
          datetime = chunk[:name]
          value = [datetime]
          if chunk.key?(:breakdown)
              value = value + (chunk[:name])
              value = value + parse_breakdown(chunk[:breakdown],value)
          end
          if chunk.key?(:breakdown)
              value = value + chunk[:counts]
          end
          @csv_rows << value.join(",")
        end
      end
    end


    private

    # Initiates the download
    def download
      response = HTTPI.post(@request)

      if response.code >= 400
        @logger.error("Request failed and returned with response code: #{response.code}\n\n#{response.body}")
        raise "Request failed and returned with response code: #{response.code}\n\n#{response.body}" 
      end

      @logger.info("Server responded with response code #{response.code}.")

      process_chunk(JSON.parse(response.body))
      @page_count += 1
      if response[:totalPages] > @page_count
        @request.body = {:reportID => body[:reportID],:page => @page_count+1}
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