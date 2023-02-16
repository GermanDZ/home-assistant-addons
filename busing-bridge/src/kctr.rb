require_relative "busing"
require_relative "input_output"

class KCtr
  DEVICE_TYPE = "KCTR_KA"

  DEFAULT_OUTPUT_NAMES = %w(Z1 Z2 Z3 Z4)

  SET_OUTPUT = 2

  def initialize(busing:)
    @busing = busing
    @input_out_puts = InputOutput.new(busing: busing, device_type: DEVICE_TYPE, type: "4E4S")
  end

  def output_names=(names)
    @input_out_puts.output_names = names
  end

  def output_names
    @input_out_puts.output_names
  end

  def output_state_by(name:)
    @input_out_puts.output_state_by(name: name)
  end

  def set_state_by(name:, value:)
    @input_out_puts.set_state_by(name: name, value: value)
  end

  def input_names=(names)
    @input_out_puts.input_names = names
  end

  def input_names
    @input_out_puts.input_names
  end

  def input_state_by(name:)
    @input_out_puts.input_state_by(name: name)
  end

  def registers_config=(names)
    @registers_config = names
  end

  def registers_config
    @registers_config ||= {}
  end

  def decode(packet)
    info = {}

    if packet.command == Busing::WRITE_MEM && packet.data1 == SET_OUTPUT
      if (register_config = registers_names.find { |config| config["id"] == packet.data2 })
        info[:action] = "set"
        info[:entity] = register_config["entity_name"]
        info[:state] = "ON"
      end
    end

    return @input_out_puts.decode(packet) if info == {}

    info
  end
end
