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

  def decode(packet)
    return @input_out_puts.decode(packet) if packet.data1 == SET_OUTPUT

    {}
  end
end
