module ROmniture
  # VisitorID handles Omniture VisitorID representations.
  # 
  # Example:
  #   vid = ROmniture::VisitorID.new("5C2EEC31F9C9517E-36D0A36E5479E9DA")
  #   vid.dec  # => "6642506199806333310_3949836567462930906"
  #   vid2 = ROmniture::VisitorID.new("6642506199806333310_3949836567462930906")
  #   vid2.hex # => "5C2EEC31F9C9517E-36D0A36E5479E9DA"
  #   vid.dec == vid2.dec # => true
  #   vid.hex == vid2.hex # => true

  class VisitorID
    def initialize(raw_input)
      input = raw_input.to_s
      validate(input)
      if input.include? "-"
        @hex = input
        @dec = from_hex(input)
      else
        @hex = from_dec(input)
        @dec = input
      end
      @hex.upcase!
    end
    def validate(input)
      if not (/^[0-9A-F]{1,100}\-[0-9A-F]{1,100}$/i.match(input) or 
        /^[0-9]{1,100}\_[0-9]{1,100}$/i.match(input))
        msg = "VisitorID is malformed: #{input}"
        raise ROmniture::Exceptions::OmnitureVisitorIDException.new(input), msg
      end
    end
    def hex
      @hex
    end
    def dec
      @dec
    end
    def from_hex(hex)
      parts = hex.split('-')
      "#{parts[0].hex}_#{parts[1].hex}"
    end
    def from_dec(dec)
      parts = dec.split('_')
      parts[0].to_i.to_s(16) + '-' + parts[1].to_i.to_s(16)
    end
  end
end
