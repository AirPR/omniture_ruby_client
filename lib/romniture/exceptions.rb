module ROmniture
  module Exceptions
    
    class OmnitureReportException < StandardError
      attr_reader :data
      def initialize(data)
        @data = data
        super
      end
    end

    class OmnitureVisitorIDException < StandardError
      attr_reader :data
      def initialize(data)
        @data = data
        super
      end
    end
    
  end
end