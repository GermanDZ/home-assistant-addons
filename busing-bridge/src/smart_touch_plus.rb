require_relative "busing"

class SmartTouchPlus
  def initialize(busing:)
    @busing = busing
  end

  def decode(packet)
    info = {}
    if packet.command == Busing::WRITE_MEM
      if packet.data1 == 0
        if packet.data2 == 139 || packet.data2 == 140
          info[:action] = "set"
          info[:entity] = "presence"
          info[:state] = packet.data2 == 140 ? "ON" : "OFF"
        end
      end
    end
    info
  end
end