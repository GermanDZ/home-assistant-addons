"""TCP connection to the Busing installation: discovery, commands, event stream."""

import logging
import socket
import time
from dataclasses import dataclass, field

from const import DEV_TYPES, READ_DEV_TYPE, UNKNOWN_DEVICE_TYPE
from controllers import BaseController, InputOutput, KCtr, SmartTouchPlus
from packet import Packet


@dataclass
class Device:
    device_id: int
    node_type: str
    controller: BaseController = field(repr=False)


class Busing:
    # Replies from devices are addressed to the TCP gateway at this address
    BRIDGE_ADDRESS = 65278
    MAX_DEVICE_ID = 255  # without routing this is the max id

    PACKET_READ_TIMEOUT = 0.1  # seconds
    RECONNECT_DELAY = 2  # seconds
    DISCOVERY_TIMEOUT = 30  # seconds
    COMMAND_TIMEOUT = 5  # seconds

    @classmethod
    def connect(cls, host, port=12347, max_devices=255, logger=None):
        logger = logger or logging.getLogger("busing")
        logger.info("Busing connecting")
        instance = cls(host=host, port=port, logger=logger)
        started = time.monotonic()
        instance.discover_devices(max_devices=max_devices)
        logger.info("Busing ready in %.1fs!", time.monotonic() - started)
        return instance

    def __init__(self, host, port, logger):
        if not host:
            raise ValueError("busing_host is required")
        self.host = host
        self.port = port
        self.logger = logger
        self.devices = []
        self._sock = None
        self._buffer = b""

    def _socket(self):
        if self._sock is None:
            self.logger.info("Connecting to busing at %s:%s", self.host, self.port)
            self._sock = socket.create_connection((self.host, self.port))
            self._sock.settimeout(self.PACKET_READ_TIMEOUT)
            self._buffer = b""
        return self._sock

    def reconnect(self):
        if self._sock is not None:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None
        self.logger.info("Reconnecting to busing...")
        return self._socket()

    def next_packet(self):
        """Return the next packet, or None if nothing arrived within the read timeout.

        Partial reads are buffered, so a slow sender never desynchronizes the
        9-byte framing.
        """
        sock = self._socket()
        while len(self._buffer) < Packet.SIZE:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                return None
            if not chunk:
                raise ConnectionError("Busing closed the connection")
            self._buffer += chunk
        data, self._buffer = self._buffer[: Packet.SIZE], self._buffer[Packet.SIZE:]
        return Packet(data)

    def discover_devices(self, max_devices=255):
        sock = self._socket()
        for address in range(self.MAX_DEVICE_ID + 1):
            packet = Packet.for_command(READ_DEV_TYPE)
            packet.address_to = address
            sock.sendall(packet.as_command())

        addresses = []
        received = 0
        deadline = time.monotonic() + self.DISCOVERY_TIMEOUT
        while received < self.MAX_DEVICE_ID and len(addresses) < max_devices:
            if time.monotonic() > deadline:
                self.logger.warning(
                    "Device discovery timed out after %ss with %s device(s) found "
                    "(check 'busing_devices_installed')",
                    self.DISCOVERY_TIMEOUT,
                    len(addresses),
                )
                break
            packet = self.next_packet()
            if packet is None:
                continue
            if packet.address_to != self.BRIDGE_ADDRESS:
                continue
            received += 1
            if packet.command == 1:
                addresses.append(packet.address_from)
                self.logger.debug("New device found at address %s", packet.address_from)

        self.devices = []
        for device_id in addresses:
            response = self.send_command_to_address(READ_DEV_TYPE, device_id, 0, 0)
            node_type = DEV_TYPES.get(response.data1, UNKNOWN_DEVICE_TYPE)
            self.devices.append(
                Device(
                    device_id=device_id,
                    node_type=node_type,
                    controller=self._new_controller(node_type),
                )
            )
        self.logger.info("%s device(s) found.", len(self.devices))

    def _new_controller(self, node_type):
        if node_type == "KCTR_KA":
            return KCtr(busing=self)
        if node_type == "2E2S":
            return InputOutput(busing=self, device_type="2E2S", module_type="2E2S")
        if node_type == "SMART_TOUCH":
            return SmartTouchPlus(busing=self)
        return BaseController(busing=self)

    def configure_device(self, device_type, outputs=None, inputs=None, registers=None):
        device = next((d for d in self.devices if d.node_type == device_type), None)
        if device is None:
            self.logger.warning("Cannot configure '%s': no such device discovered", device_type)
            return
        self.logger.info("Configuring '%s'", device_type)
        if outputs is not None:
            device.controller.output_names = outputs
        if inputs is not None:
            device.controller.input_names = inputs
        if registers:
            device.controller.registers_config = [
                dict(zip(("id", "entity_name"), register.split(":", 1)))
                for register in registers
            ]

    def output_state_by(self, name):
        device = next(
            (d for d in self.devices if name in d.controller.output_names), None
        )
        if device is not None:
            return device.controller.output_state_by(name)

        # Register entities report a default state until events arrive
        device = next(
            (
                d
                for d in self.devices
                if any(reg["entity_name"] == name for reg in d.controller.registers_config)
            ),
            None,
        )
        if device is None:
            return None
        return "OFF"

    def set_state_by(self, name, value):
        device = next(
            (d for d in self.devices if name in d.controller.output_names), None
        )
        if device is not None:
            return device.controller.set_state_by(name, value)
        self.logger.warning(
            "Cannot set state for register entity '%s' - registers are typically read-only",
            name,
        )
        return None

    def input_state_by(self, name):
        device = next(
            (d for d in self.devices if name in d.controller.input_names), None
        )
        if device is None:
            return None
        return device.controller.input_state_by(name)

    def send_command(self, cmd, device_type, data1, data2):
        device = next((d for d in self.devices if d.node_type == device_type), None)
        if device is None:
            raise LookupError(f"device '{device_type}' not found!")
        return self.send_command_to_address(cmd, device.device_id, data1, data2)

    def send_command_to_address(self, cmd, to, data1, data2):
        packet = Packet.for_command(cmd)
        packet.address_to = to
        packet.data1 = data1
        packet.data2 = data2
        self._socket().sendall(packet.as_command())

        deadline = time.monotonic() + self.COMMAND_TIMEOUT
        while time.monotonic() < deadline:
            response = self.next_packet()
            if response is None:
                continue
            if response.address_to == self.BRIDGE_ADDRESS and response.address_from == to:
                return response
        raise TimeoutError(f"No response from device {to} to command {cmd}")

    def decode(self, packet):
        info = {"action": "noop"}
        device = next(
            (d for d in self.devices if d.device_id == packet.address_to), None
        )
        if device is None:  # unknown device
            return info
        info.update(device.controller.decode(packet))
        return info

    def listen(self):
        """Yield (event, packet) tuples forever, reconnecting as needed.

        Yields (None, None) when no packet arrived within the read timeout so
        the caller can run periodic work (resync, MQTT commands).
        """
        while True:
            try:
                packet = self.next_packet()
            except (ConnectionError, OSError) as err:
                self.logger.warning("Busing connection lost (%s), reconnecting...", err)
                time.sleep(self.RECONNECT_DELAY)
                try:
                    self.reconnect()
                except OSError as reconnect_err:
                    self.logger.error("Reconnect failed: %s", reconnect_err)
                continue

            if packet is None:
                yield None, None
                continue

            if not packet.is_valid():
                self.logger.warning("Invalid packet: %s", packet.describe())
                self.reconnect()
                continue

            yield self.decode(packet), packet
