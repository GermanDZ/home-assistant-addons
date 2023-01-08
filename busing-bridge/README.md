# Busing (Fermax/Ingenium) bridge to MQTT

Alpha mode!

## Local Debug

Create a config file `busing-bridge/tmp/local.json` like:

```json
{
  "bridge_enabled": true,
  "busing_host": "192.168.1.5",
  "busing_port": 12347,
  "busing_entities": [
    "main_lights",
    "air_conditioner",
    "heating"
  ],
  "busing_devices_installed": 3,
  "busing_device_configuration": [
    {
      "type": "KCTR_KA",
      "outputs": [
        "z1",
        "heating",
        "z3",
        "z4"
      ]
    },
    {
      "type": "2E2S",
      "outputs": [
        "air_conditioner",
        "main_lights"
      ]
    }
  ],
  "mqtt_config": {
    "MQTT_HOST": "192.168.1.2",
    "MQTT_PORT": 8883,
    "MQTT_SSL": false,
    "MQTT_USERNAME": "some-user",
    "MQTT_PASSWORD": "my-super-secret-pass"
  },
  "mqtt_topic": "busing",
  "log_level": "INFO"
}
```

Move to directory `busing-bridge/src` and run locally with:

    OPTIONS_FILE=../tmp/local.json bundle exec ruby bridge.rb

