#!/usr/bin/with-contenv bashio

if bashio::services.available "mqtt"; then
    bashio::log.info "MQTT service found, fetching server detail ..."
    export MQTT_HOST=$(bashio::services mqtt "host")
    export MQTT_PORT=$(bashio::services mqtt "port")
    export MQTT_SSL=$(bashio::services mqtt "ssl")
    export MQTT_USERNAME=$(bashio::services mqtt "username")
    export MQTT_PASSWORD=$(bashio::services mqtt "password")
    bashio::log.info "Received MQTT credentials for '${MQTT_HOST}:${MQTT_PORT}'"
else
    bashio::log.warning "No internal MQTT service found. Falling back to the 'mqtt_config' option."
fi

exec python3 /bridge/bridge.py
