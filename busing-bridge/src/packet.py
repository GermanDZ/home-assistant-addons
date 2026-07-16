"""Busing wire protocol: fixed-size 9-byte datagrams.

Byte layout of a received packet:

    0-1: frame type marker (254,254 = reception; 255,255 = command; 254,255 = response)
    2:   command code
    3-4: destination address (big endian)
    5-6: source address (big endian)
    7:   data1
    8:   data2

Packets are sent on the wire as 7 bytes (see ``as_command``).
"""


class Packet:
    SIZE = 9

    def __init__(self, data=None):
        self._bytes = list(data) if data is not None else [0] * self.SIZE

    @classmethod
    def for_command(cls, command_code):
        packet = cls([255, 255, 0, 0, 0, 0, 0, 0, 0])
        packet.command = command_code
        return packet

    def is_reception(self):
        return self._bytes[0] == 254 and self._bytes[1] == 254

    def is_command(self):
        return self._bytes[0] == 255 and self._bytes[1] == 255

    def is_response(self):
        return self._bytes[0] == 254 and self._bytes[1] == 255

    def is_none(self):
        return set(self._bytes) == {0}

    def is_valid(self):
        return self.is_reception() or self.is_command() or self.is_response()

    @property
    def type(self):
        if self.is_reception() and self.command == 1:
            return "ACK"
        if self.is_reception():
            return "RCV"
        if self.is_command():
            return "CMD"
        if self.is_response():
            return "RSP"
        if self.is_none():
            return "NONE"
        return "UNKNOWN"

    @property
    def command(self):
        return self._bytes[2]

    @command.setter
    def command(self, value):
        self._bytes[2] = value

    @property
    def address_to(self):
        return self._bytes[3] * 256 + self._bytes[4]

    @address_to.setter
    def address_to(self, address):
        self._bytes[3] = address // 256
        self._bytes[4] = address % 256

    @property
    def address_from(self):
        if self.is_response():
            return self.address_to
        if self.is_command():
            return "N/A"
        return self._bytes[5] * 256 + self._bytes[6]

    @address_from.setter
    def address_from(self, address):
        self._bytes[5] = address // 256
        self._bytes[6] = address % 256

    @property
    def data1(self):
        return self._bytes[7]

    @data1.setter
    def data1(self, value):
        self._bytes[7] = value

    @property
    def data2(self):
        return self._bytes[8]

    @data2.setter
    def data2(self, value):
        self._bytes[8] = value

    def as_command(self):
        """Serialize as the 7-byte on-wire command frame."""
        self._bytes[0] = 255
        self._bytes[1] = 255
        self._bytes[5] = 0
        self._bytes[6] = 0
        return bytes([
            self._bytes[0],
            self._bytes[1],
            self._bytes[3],
            self._bytes[4],
            self._bytes[2],
            self._bytes[7],
            self._bytes[8],
        ])

    def describe(self):
        return {
            "type": self.type,
            "from": self.address_from,
            "to": self.address_to,
            "command": self.command,
            "command_as_bit": format(self.command, "08b"),
            "data1": self.data1,
            "data1_as_bit": format(self.data1, "08b"),
            "data2": self.data2,
            "data2_as_bit": format(self.data2, "08b"),
            "data_as_16_bit": self.data2 * 256 + self.data1,
            "bytes": self._bytes,
        }

    def __repr__(self):
        return f"Packet({self.describe()})"
