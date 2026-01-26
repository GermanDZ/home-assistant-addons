require_relative "packet"
require "timeout"

require_relative "input_output"
require_relative "kctr"
require_relative "smart_touch_plus"

class Busing
  READ_MEM = 3
  WRITE_MEM = 4
  READ_EEPROM = 5
  READ_DEV_TYPE = 9
  READ_ADDRESS = 7

  DEV_TYPES = {
    23 => "KCTR_KA",
    24 => "2E2S",
    6 => "SMART_TOUCH"
  }

  UNKNOWN_DEVICE_TYPE = "UNKNOWN"
  MAX_DEVICE_ID = 255 # without routing this is the max id

  PACKET_READING_TIMEOUT = 0.1
  WAIT_WHEN_NO_PACKETS = 0.1
  WAITING_TIME_BEFORE_RECONNECT = 2

  class << self
    def connect(host:, port: 12347, max_devices_to_found: 255, log_level: Logger::WARN)
      logger = Logger.new(STDOUT)
      logger.level = log_level
      logger.info("Busing connecting")
      new(host: host, port: port, logger: logger).tap do |instance|
        t0 = Time.now
        instance.discover_devices(max_devices_to_found: max_devices_to_found)
        logger.info("Busing ready in #{Time.now - t0}!")
      end
    end
  end

  def initialize(host:, port:, logger:)
    @host = host
    @port = port
    @device = []
    @socket = nil
    @logger = logger
  end

  def reconnect!
    socket(reconnect: true)
  end

  def socket(reconnect: false)
    raise "Busing not configured" if @host.nil?
    if reconnect
      @socket.close unless @socket.nil?
      @socket = nil
      logger.info("Reconnecting to busing...")
    end
    @socket ||= TCPSocket.new(@host, @port)
  end

  def logger
    @logger
  end

  def next_datagram
    Timeout::timeout(PACKET_READING_TIMEOUT) do
      readed = socket.read(Packet::SIZE)
      return Packet::NIL_PACKET if readed.nil?
      
      readed.bytes
    end
  end

  def next_packet(&block)
    Packet.response(next_datagram)
  rescue Timeout::Error
    block.call if block_given?
    sleep WAIT_WHEN_NO_PACKETS
    :no_packet
  end

  def discover_devices(max_devices_to_found: 255)
    (0..MAX_DEVICE_ID).map do |dir|
      packet = Packet.command(Busing::READ_DEV_TYPE)
      packet.address_to = dir
      packet.data1 = 0
      packet.data2 = 0
      socket.write(packet.as_command.pack("C*"))
    end
  
    @devices = []
    responses = []
    received = 0 
    while received < MAX_DEVICE_ID && responses.count < max_devices_to_found do
      packet = next_packet
      next if packet == :no_packet
      if packet.address_to == 65278
        received += 1
        responses << packet if packet.command == 1
        logger.debug("New device found")
      end
    end
    responses.map do |response|
      device_id = response.address_from
      response = send_command_to_address(Busing::READ_DEV_TYPE, device_id, 0, 0)
      dev_type = DEV_TYPES[response.data1] || UNKNOWN_DEVICE_TYPE
      devices << {
        device_id: device_id,
        node_type: dev_type,
        controller: new_controller_for(dev_type)
      }
    end
    logger.info("#{devices.count} found.")
  end

  def output_state_by(name:)
    # Buscar en outputs normales
    device = devices.find { |device| device[:controller].output_names.include?(name) }
    return device[:controller].output_state_by(name: name) if device
    
    # Buscar en registros
    device = devices.find do |device| 
      device[:controller].respond_to?(:registers_config) && 
      device[:controller].registers_config.any? { |reg| reg["entity_name"] == name }
    end
    return nil if device.nil?
    
    # Para registros, devolver estado por defecto (se actualizará cuando lleguen eventos)
    "OFF"
  end

  def set_state_by(name:, value:)
    # Buscar en outputs normales
    device = devices.find { |device| device[:controller].output_names.include?(name) }
    return device[:controller].set_state_by(name: name, value: value) if device
    
    # Los registros normalmente son de solo lectura (sensores)
    # pero podríamos agregar soporte si es necesario
    logger.warn("Cannot set state for register entity '#{name}' - registers are typically read-only")
    nil
  end

  def input_state_by(name:)
    device = devices.find { |device| device[:controller].input_names.include?(name) }
    return nil if device.nil?
    device[:controller].input_state_by(name: name)
  end

  def configure_device(device_type, outputs:, inputs:, registers:)
    device = devices.find { |d| d[:node_type] == device_type }
    logger.info("Configuring '#{device_type}'")
    logger.debug("Configuration for '#{device[:controller].class.name}': '#{outputs}'")
    device[:controller].output_names = outputs
    device[:controller].input_names = inputs
    if registers
      device[:controller].registers_config = registers.map do |register_config|
        id, entity_name = register_config.split(":")
        { "id" => id, "entity_name" => entity_name}
      end
    end
  end

  def devices
    @devices
  end

  def new_controller_for(type)
    case type
    when "KCTR_KA"
      KCtr.new(busing: self)
    when "2E2S"
      InputOutput.new(busing: self, device_type: "2E2S", type: "2E2S")
    when "SMART_TOUCH"
      SmartTouchPlus.new(busing: self)
    end
  end

  def send_command(cmd, device_type, data1, data2)
    device = devices.find { |d| d[:node_type] == device_type }
    raise "device '#{device_type}' not found!" if device.nil?
    send_command_to_address(cmd, device[:device_id], data1, data2)
  end

  def send_command_to_address(cmd, to, data1, data2)
    packet = Packet.command(cmd)
    packet.address_to = to
    packet.data1 = data1
    packet.data2 = data2
    cmd = packet.as_command
    socket.write(cmd.pack("C*"))
    packet = next_packet
    while packet == :no_packet || packet.address_to != 65278 || packet.address_from != to do
      packet = next_packet
    end
    packet
  end

  def decode(packet)
    info = { action: "noop", packet: packet }

    device = devices.find { |d| d[:device_id] == packet.address_to }

    return info if device.nil? # unknown device

    decoded_packet = device[:controller].decode(packet)

    info.merge(decoded_packet, packet: nil).compact
  end

  def listen(&block)
    loop do
      while packet = next_packet(&method(:not_packet)) do
        if packet != :no_packet && !packet.valid?
          invalid_packet(packet)
          reconnect!
          next
        end

        info = if packet == :no_packet
                 :no_event
               else
                 decode(packet)
               end
          
        block.call(info, packet)
      end
      logger.info("No more packets, reconnecting...")
      sleep(WAITING_TIME_BEFORE_RECONNECT)
      reconnect!    
    end
  end

  def invalid_packet(packet)
    logger.warn("Invalid Packet: #{packet.inspect}")
  end

  def not_packet
    logger.debug("No packets received...")
  end
end
