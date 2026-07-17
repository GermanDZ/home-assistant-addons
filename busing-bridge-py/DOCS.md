# Busing <-> MQTT bridge

Bridges an Ingenium/Fermax **Busing** installation to MQTT: it discovers the
devices on the bus, publishes their output states, and lets you switch outputs
by publishing MQTT commands.

## Requirements

- A Busing installation reachable over TCP (Ingenium ethernet gateway).
- An MQTT broker. The [Mosquitto broker add-on](https://github.com/home-assistant/addons/tree/master/mosquitto)
  is auto-detected via the Supervisor's service discovery; alternatively fill
  in the `mqtt_config` option to use an external broker.

## Configuration

| Option | Description |
| --- | --- |
| `bridge_enabled` | Enable publishing to (and receiving commands from) MQTT. When disabled the add-on only logs the states it reads. |
| `forward_all_events` | Also publish every decoded bus event to `<mqtt_topic>/events`. |
| `busing_host` | Hostname/IP of the Busing TCP gateway. **Required.** |
| `busing_port` | TCP port of the gateway (default `12347`). |
| `full_resync_every` | Seconds between full state re-publications (default `60`). |
| `busing_entities` | Names of the outputs to track and publish. |
| `busing_devices_installed` | Number of devices in the installation; discovery stops as soon as this many are found. Set it to the real device count: if it is higher than the number of devices that actually answer, discovery waits for the bus to go quiet (up to a 30&nbsp;s cap) before continuing. |
| `busing_device_configuration` | Per-device-type configuration, see below. |
| `mqtt_config` | Manual MQTT broker settings; leave `MQTT_HOST` empty to use the Supervisor's MQTT service. |
| `mqtt_topic` | MQTT topic prefix (default `busing`). |
| `mqtt_discovery` | Publish Home Assistant MQTT Discovery so entities appear automatically (default `true`). |
| `mqtt_discovery_prefix` | Discovery topic prefix (default `homeassistant`; match your MQTT integration if you changed it). |
| `log_level` | One of `debug`, `info`, `warning`, `error`. |

### Device configuration

Each entry in `busing_device_configuration` names the outputs (and optionally
memory registers) of one device type:

```yaml
busing_device_configuration:
  - type: KCTR_KA
    outputs:
      - z1
      - heating
      - z3
      - z4
    registers:
      - "17:boiler_demand"   # register id : entity name
  - type: 2E2S
    outputs:
      - air_conditioner
      - main_lights
```

Supported device types: `KCTR_KA`, `2E2S`, `SMART_TOUCH`.

## Home Assistant MQTT Discovery

With `mqtt_discovery` enabled (the default), each entity in `busing_entities`
is announced to Home Assistant automatically — no manual YAML needed. They are
grouped under a single **Busing bridge** device:

- Switchable outputs become **switch** entities (with command + state).
- Read-only entities — memory registers and the Smart Touch presence detector —
  become **binary_sensor** entities.

Discovery configs are published retained and re-announced whenever the bridge
reconnects to the broker, so entities survive a broker restart. If you remove
an entity from the config, clear its retained discovery topic (or delete the
device in Home Assistant) to make it disappear.

The manual `mqtt` YAML below is only needed if you set `mqtt_discovery: false`.

## MQTT topics

| Topic | Direction | Payload |
| --- | --- | --- |
| `<mqtt_topic>/<entity>/status` | published | JSON with `State` (`ON`/`OFF`), `Time`, `Source`, `Event`, `Raw` |
| `<mqtt_topic>/<entity>/set` | subscribed | `ON` or `OFF` to switch an output (bare `<mqtt_topic>/<entity>` is also accepted) |
| `<mqtt_topic>/bridge/availability` | published (retained) | `online` / `offline` (MQTT last will) |
| `<mqtt_topic>/events` | published | every decoded bus event (only when `forward_all_events` is on) |

### Example Home Assistant MQTT switch (only if `mqtt_discovery: false`)

```yaml
mqtt:
  switch:
    - name: Main lights
      command_topic: busing/main_lights/set
      state_topic: busing/main_lights/status
      value_template: "{{ value_json.State }}"
      availability_topic: busing/bridge/availability
```
