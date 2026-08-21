# Troubleshooting

## HA switch shows state but pressing it does nothing (commands ignored)

**Status:** RESOLVED — verified working end-to-end on 2026-07-24 with add-on
0.1.5.

Live test via `switch.turn_on`/`turn_off` on `switch.house_heating`:

- The switch publishes to `busing/heating/switch` (not `/set`), which the
  0.1.4+ subtree subscription accepts: the add-on logged
  `MQTT command, topic: 'busing/heating/switch', value: 'ON'`.
- The next 60 s resync read the relay back from the KCTR device: `heating`
  went `OFF → ON → OFF` matching the commands. Both directions work.

Remaining gotchas found during the same session:

- **Hourly restart automation.** `automation.restart_busing_add_on` restarts
  the Python add-on every hour at minute 59 (`time_pattern`). During each
  restart (MQTT reconnect + bus discovery) switch presses are silently lost
  and entities go unavailable. This was a workaround for the Ruby add-on and
  is likely unnecessary now; a press near :59 "does nothing" and can look
  like a regression. Consider disabling it.
- `automation.restart_ingenium_bridge` (restarts the *Ruby* add-on hourly)
  exists but is disabled since 2026-07-16. Keep it disabled — re-enabling it
  resurrects the Ruby bridge and causes the two-bridges bus fight below.
- Of the three `busing_entities`, only `heating` and `air_conditioner` have
  HA switch entities (`switch.house_heating` / `switch.house_air_conditioner`,
  MQTT platform, unique_ids `heating` / `air_conditioner`). There is **no HA
  entity** with unique_id `main_lights` — commands for it cannot be sent from
  HA until one is created.
- The 2E2S write path (`air_conditioner`, `main_lights`) was not live-tested
  (to avoid short-cycling the AC compressor), but it shares the exact
  `InputOutput` code path verified with `heating`, and READ_MEM resyncs to
  the 2E2S work.

The original (now outdated) diagnosis is kept below for reference.

### Symptom

- Reading works: changing an output from the physical Busing panel updates the
  entity in Home Assistant.
- Writing does **not**: pressing the switch in Home Assistant never actuates the
  Busing output.

### Root cause: entity-name / topic mismatch

The add-on identifies each output by the name given in `busing_entities` and in
the device's `outputs` list. For this install the heating output is named
**`heating`**:

```yaml
busing_entities:
  - main_lights
  - air_conditioner
  - heating
busing_device_configuration:
  - type: KCTR_KA
    outputs: [z1, heating, z3, z4]   # <- output is "heating"
```

So the add-on:

- publishes status to `busing/heating/status`
- listens for commands on the `busing/heating` subtree (`busing/heating/set` or
  bare `busing/heating`)

The Home Assistant switch entity is **`house_heating`**. Its `state_topic`
points at `busing/heating/status` (which is why status displays correctly), but
its `command_topic` does **not** match `busing/heating`. So when the switch is
pressed, either:

- nothing is published (no `command_topic` configured), or
- the command goes to `busing/house_heating/...`, which the add-on receives but
  ignores because `house_heating` is not in `busing_entities` (debug log would
  show `Ignoring command for unknown entity 'house_heating'`).

### Evidence gathered

- With `log_level: debug`, the add-on log showed passive `Event detected: ...`
  lines (bus observations) but **never** a `MQTT command, topic: '...'` line —
  the log the add-on emits when it actually receives an MQTT command. So the
  command was not reaching the add-on.
- Listening to `#` in the HA MQTT integration and pressing the switch produced
  **no message** — the switch is not publishing to a topic the add-on watches.
- The entity is named `house_heating`, while the add-on's output is `heating`.

> Note: earlier this appeared to "work" only because the old Ruby add-on was
> running in parallel and doing the switching. With only the Python add-on
> running, the command path is broken. The command path likely never worked from
> HA — status display and physical-panel control masked it.

### Fix (pick one)

**Option A — match the HA switch to the add-on (smaller change, recommended).**
Keep the entity named `house_heating`; just point its topics at `heating`:

```yaml
mqtt:
  switch:
    - name: House Heating          # entity stays switch.house_heating
      command_topic: busing/heating/set
      state_topic: busing/heating/status
      value_template: "{{ value_json.State }}"
      payload_on: "ON"
      payload_off: "OFF"
      availability_topic: busing/bridge/availability
```

The key line is `command_topic: busing/heating/set`. Restart HA (or reload MQTT
entities) after editing `configuration.yaml`.

**Option B — rename the output in the add-on to `house_heating`.**
Change `busing_entities: heating -> house_heating` and the `KCTR_KA` output
`heating -> house_heating`. This also moves the status topic to
`busing/house_heating/status`, so the switch's `state_topic` must change to
match. Larger change; only do this if you prefer the `house_heating` name on the
bus side.

### Verify

1. MQTT integration → **Listen to a topic** → `busing/heating/set` → Start.
2. Press the House Heating switch.
3. Expect `ON`/`OFF` to appear on that topic, the add-on debug log to show
   `MQTT command, topic: 'busing/heating/set', value: 'ON'`, and the relay to
   move.

Apply the same pattern to the other entities (`main_lights`, `air_conditioner`)
if they have the same mismatch.

### Related gotchas seen during diagnosis

- **Only run one add-on.** Running the Ruby `busing-bridge` and the Python
  `busing-bridge-py` at the same time makes both write to the bus and republish
  status, causing an ON/OFF/ON "flicker" and masking which one is really working.
- **Emptying `mqtt_config`.** To fall back to the Supervisor's MQTT service,
  leave the broker fields blank — but keep it a dict. In YAML mode use
  `mqtt_config: {}` (with braces) or clear the individual fields; setting the
  whole option to `null` fails with `Invalid dict for option 'mqtt_config'`.
  (For this install `mqtt_config` was not actually the problem — leave it at the
  working `MQTT_HOST: core-mosquitto` value.)
