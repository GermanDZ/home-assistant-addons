# Changelog

## 0.1.5

* Make `MQTT_HOST` in `mqtt_config` optional (`str?`) so the whole block can be
  left empty. The DOCS already said an empty host falls back to the Supervisor's
  MQTT service, but the schema rejected it ("Invalid dict for option
  'mqtt_config'"). The runtime already handles an empty/omitted host.

## 0.1.4

* Accept MQTT commands on the whole `<mqtt_topic>` subtree, matching the Ruby
  add-on. Previously only `<mqtt_topic>/<entity>/set` was honoured, so a Home
  Assistant entity whose `command_topic` was the bare `<mqtt_topic>/<entity>`
  (or any other suffix) was silently ignored — reads worked but commands did
  nothing. The bridge's own published topics (`/status`, `/events`,
  `/bridge/*`) are filtered out so they can't be mistaken for commands.

## 0.1.3

* Relax the `log_level` option schema from a fixed lowercase list to a free
  string, matching the Ruby add-on so an existing config (e.g. `log_level:
  INFO`) can be pasted in as-is. The runtime already upper-cases the value and
  falls back to `warning` for anything unrecognised.

## 0.1.2

* Add the missing `build.yaml` so the Supervisor passes a base image into the
  Dockerfile's `BUILD_FROM` arg. Without it the build failed with
  `base name ($BUILD_FROM) should not be blank`. Base images are pinned to the
  official Home Assistant Alpine 3.21 images for every supported architecture.

## 0.1.1

Robustness fixes from an adversarial review of the rewrite:

* The event loop no longer crashes if reconnecting fails after an invalid
  packet is received (the reconnect is now guarded like the connection-lost
  path).
* Queued MQTT commands keep being processed while the Busing bus is
  unreachable, instead of stalling until it comes back.
* Device discovery stops as soon as the bus goes quiet (3&nbsp;s) instead of
  always waiting for the full count/timeout, so an over-estimated
  `busing_devices_installed` no longer causes a long startup stall.
* Leftover discovery ACKs are drained before the per-device type queries, so a
  stale ACK can't be misread as a device type.
* Drop the unused `inputs` field from the device-configuration handling so the
  code matches the add-on schema (which does not expose `inputs`).

## 0.1.0

Rewrite of the bridge in Python (paho-mqtt), replacing the Ruby implementation.

Behaviour fixes and improvements:

* **Breaking:** commands are now received on `<mqtt_topic>/<entity>/set` (Home
  Assistant `command_topic` convention) instead of any topic starting with
  `busing/<entity>`. This also stops the bridge from consuming its own
  `status` messages.
* Add-on configuration migrated from `config.json` to `config.yaml` (current
  Home Assistant format); `log_level` is now a select of
  `debug|info|warning|error`.
* MQTT credentials are no longer written to the add-on log.
* The `busing_port` option is now actually used (it was previously ignored and
  the port was always 12347).
* Trailing `/` in `mqtt_topic` is stripped, avoiding double slashes in topics.
* The bridge publishes `online`/`offline` (retained, with MQTT last will) to
  `<mqtt_topic>/bridge/availability`.
* Device discovery and command responses now time out instead of hanging
  forever when a device does not answer.
* Manual `mqtt_config` is only used when `MQTT_HOST` is set, otherwise the
  Supervisor's MQTT service is used; the add-on no longer exits when the
  Mosquitto service is missing but `mqtt_config` is provided.
* Unknown device types get a no-op controller instead of crashing the add-on.
* Partial TCP reads no longer desynchronize the 9-byte packet framing.

---

History below is inherited from the original Ruby `busing-bridge` add-on.

## 0.0.33

* Add support for register entities in output_state_by and set_state_by methods
* Register entities now appear in MQTT with default "OFF" state until events are received

## 0.0.32

* Remove 'inputs' field from busing_device_configuration schema - only 'outputs' and 'registers' are supported

## 0.0.31

* Fix schema syntax for optional 'inputs' and 'registers' fields in busing_device_configuration

## 0.0.30

* Make 'registers' and 'inputs' fields optional in busing_device_configuration schema

## 0.0.29

* Add support for 'registers' field in busing_device_configuration schema

## 0.0.28

* Fix NoMethodError when entities are not found in configured devices - now shows warning and continues
* Add null checks in busing.rb methods to prevent crashes with missing entities

## 0.0.27

* Fix MQTT configuration priority - custom mqtt_config now takes precedence over environment variables

## 0.0.26

* Extend config schema to include MQTT configuration options
* Update Dockerfile to use ruby-json-parser

## 0.0.25

Emit events when registers are updated in KCTR module.

## 0.0.24

Use bundle exec in `run.sh` to ensure gems are available

## 0.0.23

Add missing `git` package to docker image

## 0.0.22

* Use [mqtt](https://github.com/njh/ruby-mqtt) gem from main branch on github for Ruby 3.0 compat.

## 0.0.21

* Make the addon compatible with Ruby 3.0

## 0.0.20

* Add `init: false` to config

## 0.0.19

* MQTT configuration removed in favour of auto-discovery offered by services.

## 0.0.18

* Working version, reading the output states and republishing changes to mqtt
