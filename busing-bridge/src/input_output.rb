require_relative "busing"

class InputOutput
  DEFAULT_OUTPUT_NAMES = {
    "2E2S" => %w(Z1 Z2),
    "4E4S" => %w(Z1 Z2 Z3 Z4),
    "6E6S" => %w(Z1 Z2 Z3 Z4 Z5 Z6)
  }

  DEFAULT_INPUT_NAMES = {
    "2E2S" => %w(E1 E2),
    "4E4S" => %w(E1 E2 E3 E4),
    "6E6S" => %w(E1 E2 E3 E4 E5 E6)
  }

  MAX_OUTPUTS = 6
  MAX_INPUTS = 6
  ON_OFF_BIT = 8
  SET_OUTPUT = 2

  def initialize(busing:, device_type:, type:)
    @busing = busing
    @device_type = device_type
    @type = type
  end

  def input_names=(names)
    @input_names = names
  end

  def input_names
    @input_names ||= DEFAULT_INPUT_NAMES[@type]
  end

  def output_names=(names)
    @output_names = names
  end

  def output_names
    @output_names ||= DEFAULT_OUTPUT_NAMES[@type]
  end

  def busing
    @busing
  end

  def device_type
    @device_type
  end

  def type
    @type
  end

  def output_state_by(name:)
    response = busing.send_command(Busing::READ_MEM, device_type, 1, 0)
    bit_value = 2 ** (output_names.index(name) + MAX_OUTPUTS - output_names.size)
    (response.data1 & bit_value) == bit_value ? "ON" : "OFF"
  end

  def set_state_by(name:, value:)
    output_index = output_names.index(name)
    bit_mode = value == "ON" ? 0 : 1
    bit_value = MAX_OUTPUTS - output_names.size + output_index + 8 * bit_mode
    data1 = 2
    busing.send_command(Busing::WRITE_MEM, device_type, data1, bit_value)
  end

  def input_state_by(name:)
    response = busing.send_command(Busing::READ_MEM, device_type, 0, 0)
    bit_value = 2 ** (input_names.index(name) + MAX_INPUTS - input_names.size + 2)
    (response.data1 & bit_value) == bit_value ? "ON" : "OFF"
  end

  def decode(packet)
    info = {}
    if packet.command == Busing::WRITE_MEM && packet.data1 == SET_OUTPUT
      
      output_number = (packet.data2 & (ON_OFF_BIT - 1)) - (MAX_OUTPUTS - output_names.size)
      state_name = (packet.data2 & ON_OFF_BIT) == 0 ? "ON" : "OFF"
      output_name = output_names[output_number]
      
      info[:action] = "set"
      info[:entity] = output_name
      info[:state] = state_name
    end
    info
  end
end
