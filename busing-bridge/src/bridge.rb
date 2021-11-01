require "logger"
require "socket"
require "date"
require "json"
require "mqtt"
require_relative "packet"
require_relative "busing"

options_path = ENV.fetch("OPTIONS_FILE", "/data/options.json")
options = JSON.parse(File.read(options_path))

bridge_enabled = options.fetch("bridge_enabled", false)

busing_host = options.fetch("busing_host")
busing_entities = options.fetch("busing_entities")
busing_device_configurations = options.fetch("busing_device_configuration")
devices_installed = options.fetch("busing_devices_installed", 12)
forward_all_events = options.fetch("forward_all_events", false)

mqtt_options = ENV.fetch("MQTT_HOST", false) ? ENV : options.fetch("mqtt_config")

mqtt_host = mqtt_options.fetch("MQTT_HOST")
mqtt_port = mqtt_options.fetch("MQTT_PORT")
mqtt_ssl = mqtt_options.fetch("MQTT_SSL", true)
mqtt_username = mqtt_options.fetch("MQTT_USERNAME")
mqtt_password = mqtt_options.fetch("MQTT_PASSWORD")
mqtt_protocol = mqtt_ssl ? "mqtts" : "mqtt"

mqtt_topic = options.fetch("mqtt_topic", "busing/events")

log_level = options.fetch("log_level", Logger::WARN)

busing = Busing.connect(
  host: busing_host,
  max_devices_to_found:
  devices_installed,
  log_level: log_level
)
logger = busing.logger

mqtt_connection_url = "#{mqtt_protocol}://#{mqtt_username}:#{mqtt_password}@#{mqtt_host}"

mqtt = if bridge_enabled
  MQTT::Client.connect(mqtt_connection_url, port: mqtt_port, ssl: mqtt_ssl).tap do |mqtt|
    mqtt.subscribe("#")
  end
end

def publish_entity_state(mqtt, logger, entity, state, raw = nil)
  return logger.debug("No entity to publish to mqtt") if entity.to_s == ""
  message = {
    Time: DateTime.now.iso8601,
    Source: "busing",
    Event: "state_changed",
    State: state,
    Raw: raw
  }
  mqtt.publish("busing/#{entity}/status", message.to_json)
end

busing_entities.each do |entity|
  state = busing.output_state_by(name: entity)
  publish_entity_state(mqtt, logger, entity, state) if bridge_enabled
  logger.info("Busing #{entity} are '#{state}'")  
end

def do_other_things(mqtt, logger)
  logger.debug("No busing events")
  Timeout::timeout(WAITING_TIME_FOR_MQTT) do
    loop do
      topic, message = mqtt.get
      logger.debug("MQTT, topic: '#{topic}', value: '#{message.inspect}'")  
    end
  end
rescue Timeout::Error
  logger.debug("MQTT: no new messages")
  sleep WAITING_TIME_FOR_MQTT
end

busing_device_configurations.each do |options|
  logger.info("Configuring '#{options["type"]}' with '#{options.inspect}'")
  busing.configure_device(
    options["type"],
    outputs: options["outputs"],
    inputs: options["inputs"]
  )
end

WAITING_TIME_FOR_MQTT = 0.1

busing.listen do |busing_event|
  if busing_event == :no_event
    do_other_things(mqtt, logger) if bridge_enabled
    next
  end

  packet = busing_event[:packet]

  message = {
    Time: DateTime.now.iso8601,
    Source: packet.address_from,
    Dest: packet.address_to,
    Event: "state_changed",
    DeviceType: "io",
    Value_1: packet.data1,
    Value_2: packet.data2,
    Raw: busing_event.inspect
  }
  mqtt.publish(mqtt_topic, message.to_json) if forward_all_events && bridge_enabled

  if busing_event[:action] == "set"
    publish_entity_state(
      mqtt,
      logger,
      busing_event[:entity],
      busing_event[:state],
      busing_event
    ) if bridge_enabled
    logger.debug("Event detected: #{busing_event}")
  end
end
