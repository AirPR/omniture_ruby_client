module ROmniture

  # DataWarehouse response class.
  #
  # This class is responsible for downloading a DataWarehouse Request, 
  # splitting the response into records, and mapping each distinct record
  # through the provided map function. 
  

  class DWResponse

    DEFAULT_MAP_FUNCTION = lambda do |records|
      @logger.info("[recordset]")
      records.each do |record|
        @logger.info(record)
      end
      @logger.info("[/recordset]")
    end

    # param request. HTTPI request object. Fully configured request to download
    #     the prepared report.
    # param map_function. function. The function to apply to each record.

    def initialize(request, map_function=DEFAULT_MAP_FUNCTION)
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO
      @request = request
      @map_function = map_function

      @chunk_count = 0
      @buffer = ''
      @header = false
      @modulo_factor = 1
      
      @request.on_body do |chunk|
        @chunk_count += 1
        last_new_line = chunk.rindex(/\r?\n/) || -1
        @buffer << chunk[0..last_new_line]
        if should_process
          process_buffer
          @buffer = chunk[last_new_line..-1]
        end
      end

      download
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

      final_processing
    end

    # Group chunks together for more efficient processing.
    def should_process
      return @chunk_count % @modulo_factor == 0
    end

    def final_processing
      #Process remaining records in the buffer and clear
      process_buffer
      @buffer = ''
    end

    # Processes the buffer into distinct records and maps them.
    # 
    # @buffer must not contain partial records when called.
    # @map_function is called once for each distinct record.
    def process_buffer
      if @buffer != ''
        @buffer = @buffer.force_encoding("UTF-8").gsub(/\xEF\xBB\xBF/, "")
        to_parse = @buffer
        if not @header
          start_point = @buffer.index(/\r?\n/)
          if start_point
            @header = @buffer[0..start_point]
            to_parse = @buffer[start_point..-1]
          end
        end

        if @header
          data = CSV.parse(@header + to_parse, :headers => true)
          @map_function.call(data)
        end
      end
    end

  end
end