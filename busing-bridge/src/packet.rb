class Packet
  SIZE = 9
  NIL_PACKET = [0] * SIZE

  def initialize(bytes = NIL_PACKET)
    @bytes = bytes
  end

  def self.command(command_code)
    Packet.new(bytes = [255, 255, 0, 0, 0, 0, 0, 0, 0]).tap do |packet|
      packet.command = command_code
    end
  end

  def self.response(bytes)
    Packet.new(bytes)
  end

  def reception?
    @bytes[0] == 254 && @bytes[1] == 254
  end

  def command?
    @bytes[0] == 255 && @bytes[1] == 255
  end

  def response?
    @bytes[0] == 254 && @bytes[1] == 255
  end

  def none?
    @bytes.uniq == [0]
  end

  def type
    return "ACK" if reception? && command == 1
    return "RCV" if reception?
    return "CMD" if command?
    return "RSP" if response?
    return "NONE" if none?
    
    "UNKNOWN"
  end

  def valid?
    reception? || command? || response?
  end

  def address_to
    @bytes[3] * 256 + @bytes[4]
  end

  def address_to=(address)
    @bytes[3] = address / 256
    @bytes[4] = address % 256
  end

  def address_from
    return address_to if response?
    return "N/A" if command?

    @bytes[5] * 256 + @bytes[6]
  end

  def address_from=(address)
    @bytes[5] = address / 256
    @bytes[6] = address % 256
  end

  def command
    @bytes[2]
  end

  def command=(command)
    @bytes[2] = command
  end

  def data1
    @bytes[7]
  end

  def data1=(data)
    @bytes[7] = (data)
  end

  def data2
    @bytes[8]
  end

  def data2=(data)
    @bytes[8] = (data)
  end

  def as_command
    @bytes[0] = 255
    @bytes[1] = 255
    @bytes[5] = 0
    @bytes[6] = 0
    [
      @bytes[0],
      @bytes[1],
      @bytes[3],
      @bytes[4],
      @bytes[2],
      @bytes[7],
      @bytes[8]
    ]
  end

  def inspect
    {
      type: type,
      from: address_from,
      to: address_to,
      command: command,
      command_as_bit: command.chr.unpack('B*'),
      data1: data1,
      data1_as_bit: data1.chr.unpack('B*'),
      data2: data2,
      data2_as_bit: data2.chr.unpack('B*'),
      data_as_16_bit: data2 * 256 + data1,
      bytes: @bytes
    }
  end
end
