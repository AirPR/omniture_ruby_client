module ROmniture

  # DataWarehouse response class.
  #
  # This class is responsible for downloading a DataWarehouse Request, 
  # splitting the response into records, and mapping each recordset
  # through the provided map function. 
  
  class DWResponse
    # The maximum allowable number of consecutive malformed chunks.
    # Basically, if chunks never complete into valid CSV, we want to give up.
    MAX_CONSECUTIVE_MALFORMED = 100

    # param request. HTTPI request object. Fully configured request to download
    #     the prepared report.
    # param map_function. function. The function to apply to each record.

    class MaxConsecutiveMalformedCSVExceeded < StandardError; end

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

      @chunk_count = 0
      @buffer = ''
      @header = false
      @modulo_factor = 10

      @consecutive_malformed = 0
      
      if !request.nil?

        @request.on_body do |chunk|
          process_chunk(chunk)
        end

        download
      end
    end

    def process_chunk(chunk)
      if !@header
        # Keep adding to the buffer until we find a header
        @buffer << chunk
        first_new_line = @buffer.index(/\r?\n/) || -1
        if first_new_line > -1
          # Now strip the header off and save it as header
          @header = @buffer[0..(first_new_line)]
          @buffer = @buffer[(first_new_line+1)..-1]
        end
      else
        # Now that we have a header, try to find if the chunk completes
        last_new_line = chunk.rindex(/\r?\n/) || -1
        if last_new_line > -1
          # Add up until the completed portion
          @buffer << chunk[0..(last_new_line-1)]
          # Try to process the buffer.
          if should_process and process_buffer
            #If the processing succeeds, empty the buffer
            @buffer = ''
          else
            #Otherwise, keep adding to the buffer (since it wasnt truly complete)
          end
          # Always add the remaining part of the chunk at the end.
          @buffer << chunk[(last_new_line)..-1]
        else
          @buffer << chunk
        end
      end
      @chunk_count += 1
    end

    # This is used for testing only
    def process_chunks(chunks, modulo_factor=1)
      @modulo_factor = modulo_factor
      chunks.each do |chunk|
        process_chunk(chunk)
      end
      # Process remaining data in the buffer
      final_processing
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
      if @header
        process_buffer
      end
      @buffer = ''
      @header = false
    end

    # Processes the buffer into distinct records and maps them.
    # 
    # @buffer must not contain partial records when called.
    # @map_function is called once for each set of records.
    def process_buffer
      success = false
      if !@buffer.empty?
        to_parse = @header.clone.force_encoding("UTF-8").gsub(/\xEF\xBB\xBF/, "")
        to_parse += @buffer.clone.force_encoding("UTF-8").gsub(/\xEF\xBB\xBF/, "")
        begin
          data = CSV.parse(to_parse, :headers => true, skip_blanks: true)
          if !data.empty?
            @map_function.call(data)
          end
          @consecutive_malformed = 0
          success = true
        rescue CSV::MalformedCSVError
          @consecutive_malformed += 1
          success = false
          if @consecutive_malformed > MAX_CONSECUTIVE_MALFORMED
            raise MaxConsecutiveMalformedCSVExceeded
          end
        end
      end
      success
    end

  end
end