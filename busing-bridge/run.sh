#!/usr/bin/with-contenv bashio

if ! bashio::services.available "mqtt"; then
    bashio::log.error "No internal MQTT service found. Please install Mosquitto broker"
    exit -1
else
    bashio::log.info "MQTT service found, fetching server detail ..."
    bashio::log.info "MQTT server not found, auto-discovering ..."
    MQTT_HOST=$(bashio::services mqtt "host")
    MQTT_PORT=$(bashio::services mqtt "port")
    MQTT_SSL=$(bashio::services mqtt "ssl")
    MQTT_USERNAME=$(bashio::services mqtt "username")
    MQTT_PASSWORD=$(bashio::services mqtt "password")
    bashio::log.info "Received user: '$MQTT_USER' for MQTT at '$MQTT_HOST:$MQTT_PORT'!"
    fi
fi

ruby bridge.rb
