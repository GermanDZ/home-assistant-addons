#!/usr/bin/env python3
"""Busing <-> MQTT bridge: Home Assistant add-on entry point."""

import json
import logging
import os
import queue
import sys
import time
from datetime import datetime

import paho.mqtt.client as mqtt

from busing import Busing

_LOGGER = logging.getLogger("bridge")

MQTT_ENV_KEYS = ("MQTT_HOST", "MQTT_PORT", "MQTT_SSL", "MQTT_USERNAME", "MQTT_PASSWORD")


def load_options():
    options_path = os.environ.get("OPTIONS_FILE", "/data/options.json")
    with open(options_path, encoding="utf-8") as options_file:
        return json.load(options_file)


def configure_logging(log_level):
    level = getattr(logging, str(log_level).upper(), None)
    if not isinstance(level, int):
        level = logging.WARNING
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
        stream=sys.stdout,
    )


def mqtt_settings(options):
    """MQTT connection settings from options, falling back to the environment.

    The environment variables are exported by run.sh from the Supervisor's
    MQTT service discovery (Mosquitto broker add-on).
    """
    config = options.get("mqtt_config") or {}
    if not config.get("MQTT_HOST"):
        config = {key: os.environ.get(key) for key in MQTT_ENV_KEYS}
    host = config.get("MQTT_HOST")
    if not host:
        raise SystemExit(
            "No MQTT broker configured: install the Mosquitto broker add-on "
            "or fill in the 'mqtt_config' option"
        )
    return {
        "host": host,
        "port": int(config.get("MQTT_PORT") or 1883),
        "ssl": str(config.get("MQTT_SSL")).lower() in ("true", "1"),
        "username": config.get("MQTT_USERNAME"),
        "password": config.get("MQTT_PASSWORD"),
    }


def create_mqtt_client(settings, topic_prefix, command_queue):
    _LOGGER.info(
        "Connecting to MQTT broker at %s:%s (ssl=%s, user=%s)",
        settings["host"],
        settings["port"],
        settings["ssl"],
        settings["username"],
    )
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="busing-bridge")
    if settings["username"]:
        client.username_pw_set(settings["username"], settings["password"])
    if settings["ssl"]:
        client.tls_set()
    availability_topic = f"{topic_prefix}/bridge/availability"
    client.will_set(availability_topic, "offline", retain=True)

    def on_connect(client, userdata, flags, reason_code, properties=None):
        _LOGGER.info("Connected to MQTT broker (%s)", reason_code)
        client.subscribe(f"{topic_prefix}/+/set")
        client.publish(availability_topic, "online", retain=True)

    def on_message(client, userdata, message):
        entity = message.topic.split("/")[-2]
        payload = message.payload.decode(errors="replace")
        _LOGGER.debug("MQTT command, topic: '%s', value: '%s'", message.topic, payload)
        command_queue.put((entity, payload))

    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(settings["host"], settings["port"])
    client.loop_start()  # network I/O runs in a background thread
    return client


def publish_entity_state(mqtt_client, entity, state, topic_prefix, raw_event=None):
    if not entity:
        _LOGGER.debug("No entity to publish to mqtt")
        return
    message = {
        "Time": datetime.now().astimezone().isoformat(),
        "Source": "busing",
        "Event": "state_changed",
        "State": state,
        "Raw": raw_event,
    }
    mqtt_client.publish(f"{topic_prefix}/{entity}/status", json.dumps(message))


def full_resync(entities, busing, mqtt_client, topic_prefix, bridge_enabled):
    for entity in entities:
        state = busing.output_state_by(entity)
        if state is None:
            _LOGGER.warning("Entity '%s' not found in any configured device", entity)
            continue
        if bridge_enabled:
            publish_entity_state(mqtt_client, entity, state, topic_prefix)
        _LOGGER.info("Busing %s is '%s'", entity, state)


def process_commands(command_queue, entities, busing, mqtt_client, topic_prefix):
    """Apply MQTT commands (<topic_prefix>/<entity>/set) queued by the MQTT thread.

    Runs on the main thread so the Busing socket is never used concurrently.
    """
    while True:
        try:
            entity, payload = command_queue.get_nowait()
        except queue.Empty:
            return
        if entity not in entities:
            _LOGGER.warning("Ignoring command for unknown entity '%s'", entity)
            continue
        if payload not in ("ON", "OFF"):
            _LOGGER.warning("Wrong message '%s' for entity '%s'.", payload, entity)
            continue
        busing.set_state_by(entity, payload)
        publish_entity_state(mqtt_client, entity, payload, topic_prefix)


def main():
    options = load_options()
    configure_logging(options.get("log_level", "warning"))
    _LOGGER.info("Options loaded from %s", os.environ.get("OPTIONS_FILE", "/data/options.json"))

    bridge_enabled = options.get("bridge_enabled", False)
    forward_all_events = options.get("forward_all_events", False)
    full_resync_every = options.get("full_resync_every", 60)  # seconds
    entities = options.get("busing_entities", [])
    topic_prefix = options.get("mqtt_topic", "busing").rstrip("/")

    busing = Busing.connect(
        host=options["busing_host"],
        port=options.get("busing_port") or 12347,
        max_devices=options.get("busing_devices_installed", 12),
    )

    for device_config in options.get("busing_device_configuration", []):
        busing.configure_device(
            device_config["type"],
            outputs=device_config.get("outputs"),
            inputs=device_config.get("inputs"),
            registers=device_config.get("registers"),
        )

    command_queue = queue.Queue()
    mqtt_client = None
    if bridge_enabled:
        mqtt_client = create_mqtt_client(mqtt_settings(options), topic_prefix, command_queue)

    full_resync(entities, busing, mqtt_client, topic_prefix, bridge_enabled)
    last_resync = time.monotonic()

    for event, packet in busing.listen():
        try:
            if bridge_enabled:
                process_commands(command_queue, entities, busing, mqtt_client, topic_prefix)

            if event is None:
                if time.monotonic() - last_resync >= full_resync_every:
                    full_resync(entities, busing, mqtt_client, topic_prefix, bridge_enabled)
                    last_resync = time.monotonic()
                continue

            if forward_all_events and bridge_enabled:
                message = {
                    "Time": datetime.now().astimezone().isoformat(),
                    "Source": packet.address_from,
                    "Dest": packet.address_to,
                    "Event": "state_changed",
                    "DeviceType": "io",
                    "Value_1": packet.data1,
                    "Value_2": packet.data2,
                    "Raw": repr(event),
                }
                mqtt_client.publish(f"{topic_prefix}/events", json.dumps(message))

            if event.get("action") == "set":
                if bridge_enabled:
                    publish_entity_state(
                        mqtt_client,
                        event.get("entity"),
                        event.get("state"),
                        topic_prefix,
                        raw_event=event,
                    )
                _LOGGER.debug("Event detected: %s", event)
        except (ConnectionError, OSError, TimeoutError) as err:
            _LOGGER.warning("Busing communication error (%s), reconnecting...", err)
            time.sleep(Busing.RECONNECT_DELAY)
            busing.reconnect()


if __name__ == "__main__":
    main()
