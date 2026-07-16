"""Controllers that know how to talk to each Busing device type."""

import logging

from const import READ_MEM, WRITE_MEM

_LOGGER = logging.getLogger(__name__)


class BaseController:
    """Default controller: no outputs, no inputs, decodes nothing.

    Used for unknown device types so the rest of the bridge never has to
    special-case them.
    """

    def __init__(self, busing):
        self.busing = busing
        self.output_names = []
        self.input_names = []
        self.registers_config = []

    def decode(self, packet):
        return {}


class InputOutput(BaseController):
    """Generic nEnS relay/input module (2E2S, 4E4S, 6E6S)."""

    DEFAULT_OUTPUT_NAMES = {
        "2E2S": ["Z1", "Z2"],
        "4E4S": ["Z1", "Z2", "Z3", "Z4"],
        "6E6S": ["Z1", "Z2", "Z3", "Z4", "Z5", "Z6"],
    }

    DEFAULT_INPUT_NAMES = {
        "2E2S": ["E1", "E2"],
        "4E4S": ["E1", "E2", "E3", "E4"],
        "6E6S": ["E1", "E2", "E3", "E4", "E5", "E6"],
    }

    MAX_OUTPUTS = 6
    MAX_INPUTS = 6
    ON_OFF_BIT = 8
    SET_OUTPUT = 2

    def __init__(self, busing, device_type, module_type):
        super().__init__(busing)
        self.device_type = device_type
        self.module_type = module_type
        self.output_names = list(self.DEFAULT_OUTPUT_NAMES.get(module_type, []))
        self.input_names = list(self.DEFAULT_INPUT_NAMES.get(module_type, []))

    def output_state_by(self, name):
        response = self.busing.send_command(READ_MEM, self.device_type, 1, 0)
        bit_value = 2 ** (self.output_names.index(name) + self.MAX_OUTPUTS - len(self.output_names))
        return "ON" if response.data1 & bit_value == bit_value else "OFF"

    def set_state_by(self, name, value):
        output_index = self.output_names.index(name)
        bit_mode = 0 if value == "ON" else 1
        bit_value = self.MAX_OUTPUTS - len(self.output_names) + output_index + 8 * bit_mode
        return self.busing.send_command(WRITE_MEM, self.device_type, self.SET_OUTPUT, bit_value)

    def input_state_by(self, name):
        response = self.busing.send_command(READ_MEM, self.device_type, 0, 0)
        bit_value = 2 ** (self.input_names.index(name) + self.MAX_INPUTS - len(self.input_names) + 2)
        return "ON" if response.data1 & bit_value == bit_value else "OFF"

    def decode(self, packet):
        if packet.command == WRITE_MEM and packet.data1 == self.SET_OUTPUT:
            output_number = (packet.data2 & (self.ON_OFF_BIT - 1)) - (self.MAX_OUTPUTS - len(self.output_names))
            state = "ON" if packet.data2 & self.ON_OFF_BIT == 0 else "OFF"
            if 0 <= output_number < len(self.output_names):
                return {
                    "action": "set",
                    "entity": self.output_names[output_number],
                    "state": state,
                }
            _LOGGER.debug("Output number %s out of range for %s", output_number, self.device_type)
        return {}


class KCtr(BaseController):
    """KCTR/KA climate controller: a 4E4S module plus memory registers."""

    DEVICE_TYPE = "KCTR_KA"
    SET_OUTPUT = 2

    def __init__(self, busing):
        super().__init__(busing)
        self._io = InputOutput(busing, device_type=self.DEVICE_TYPE, module_type="4E4S")

    @property
    def output_names(self):
        return self._io.output_names

    @output_names.setter
    def output_names(self, names):
        # Called from BaseController.__init__ before _io exists; that default
        # is already applied by InputOutput itself.
        if hasattr(self, "_io"):
            self._io.output_names = names

    @property
    def input_names(self):
        return self._io.input_names

    @input_names.setter
    def input_names(self, names):
        if hasattr(self, "_io"):
            self._io.input_names = names

    def output_state_by(self, name):
        return self._io.output_state_by(name)

    def set_state_by(self, name, value):
        return self._io.set_state_by(name, value)

    def input_state_by(self, name):
        return self._io.input_state_by(name)

    def decode(self, packet):
        if packet.command == WRITE_MEM and packet.data1 == self.SET_OUTPUT:
            for register in self.registers_config:
                if register["id"] == str(packet.data2):
                    return {
                        "action": "set",
                        "entity": register["entity_name"],
                        "state": "ON",
                    }
        return self._io.decode(packet)


class SmartTouchPlus(BaseController):
    """Smart Touch Plus panel: exposes its presence detector."""

    PRESENCE_OFF = 139
    PRESENCE_ON = 140

    def decode(self, packet):
        if packet.command == WRITE_MEM and packet.data1 == 0:
            if packet.data2 in (self.PRESENCE_OFF, self.PRESENCE_ON):
                return {
                    "action": "set",
                    "entity": "presence",
                    "state": "ON" if packet.data2 == self.PRESENCE_ON else "OFF",
                }
        return {}
