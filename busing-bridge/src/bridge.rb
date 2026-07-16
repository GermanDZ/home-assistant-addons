require "logger"
require "socket"
require "date"
require "json"
require "mqtt"
require_relative "packet"
require_relative "busing"

options_path = ENV.fetch("OPTIONS_FILE", "/data/options.json")
options = JSON.parse(File.read(options_path))

Logger.new(STDOUT).info("opts path: #{options_path}")
Logger.new(STDOUT).info("opts content: #{options}")


bridge_enabled = options.fetch("bridge_enabled", false)

busing_host = options.fetch("busing_host")
busing_entities = options.fetch("busing_entities")
busing_device_configurations = options.fetch("busing_device_configuration")
devices_installed = options.fetch("busing_devices_installed", 12)
forward_all_events = options.fetch("forward_all_events", false)
full_resync_every = options.fetch("full_resync_every", 60)# seconds

mqtt_options = options.fetch("mqtt_config", {}).empty? ? ENV : options.fetch("mqtt_config")

mqtt_host = mqtt_options.fetch("MQTT_HOST")
mqtt_port = mqtt_options.fetch("MQTT_PORT")
mqtt_ssl = mqtt_options.fetch("MQTT_SSL", true)
mqtt_username = mqtt_options.fetch("MQTT_USERNAME")
mqtt_password = mqtt_options.fetch("MQTT_PASSWORD")
mqtt_protocol = mqtt_ssl ? "mqtts" : "mqtt"

mqtt_topic = options.fetch("mqtt_topic", "busing")

log_level = options.fetch("log_level", Logger::WARN)

mqtt_connection_url = "#{mqtt_protocol}://#{mqtt_username}:#{mqtt_password}@#{mqtt_host}"

Logger.new(STDOUT).info("opts #{options.inspect}")
Logger.new(STDOUT).info("mqtt #{mqtt_connection_url}")


busing = Busing.connect(
  host: busing_host,
  max_devices_to_found:
  devices_installed,
  log_level: log_level
)
logger = busing.logger

mqtt = if bridge_enabled

  MQTT::Client.connect(mqtt_connection_url, port: mqtt_port, ssl: mqtt_ssl).tap do |mqtt|
    mqtt.subscribe("#{mqtt_topic}/#")
  end
end

def publish_entity_state(mqtt, logger, entity, state, mqtt_topic:, raw_event: nil)
  return logger.debug("No entity to publish to mqtt") if entity.to_s == ""
  message = {
    Time: DateTime.now.iso8601,
    Source: "busing",
    Event: "state_changed",
    State: state,
    Raw: raw_event
  }
  mqtt.publish("#{mqtt_topic}/#{entity}/status", message.to_json)
end

def full_resync(busing_entities, busing:, mqtt:, logger:, mqtt_topic:, bridge_enabled: true)
  busing_entities.each do |entity|
    state = busing.output_state_by(name: entity)
    if state.nil?
      logger.warn("Entity '#{entity}' not found in any configured device")
      next
    end
    publish_entity_state(mqtt, logger, entity, state, mqtt_topic: mqtt_topic) if bridge_enabled
    logger.info("Busing #{entity} are '#{state}'")  
  end
end

def do_other_things(busing_entities, busing:, mqtt:, logger:, mqtt_topic:)
  logger.debug("No busing events")
  Timeout::timeout(WAITING_TIME_FOR_MQTT) do
    loop do
      topic, message = mqtt.get
      busing_entities.each do |entity|
        if topic.start_with? "busing/#{entity}"
          if %w(ON OFF).include?(message)
            busing.set_state_by(name: entity, value: message)
            publish_entity_state(mqtt, logger, entity, message, mqtt_topic: mqtt_topic)
          else
            logger.warn"Wrong message '#{message}' on topic '#{topic}'."
          end
        end
      end
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
    inputs: options["inputs"],
    registers: options["registers"]
  )
end

full_resync(busing_entities, busing: busing, mqtt: mqtt, logger: logger, mqtt_topic: mqtt_topic, bridge_enabled: bridge_enabled)

WAITING_TIME_FOR_MQTT = 0.1

last_full_resync = Time.now
busing.listen do |busing_event, packet|
  if busing_event == :no_event
    if (last_full_resync + full_resync_every) < Time.now
      full_resync(busing_entities, busing: busing,
                                   mqtt: mqtt,
                                   logger: logger,
                                   mqtt_topic: mqtt_topic,
                                   bridge_enabled: bridge_enabled)
      last_full_resync = Time.now
    end
    do_other_things(busing_entities, busing: busing, mqtt: mqtt, logger: logger, mqtt_topic: mqtt_topic) if bridge_enabled
    next
  end

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
  mqtt.publish("#{mqtt_topic}/events", message.to_json) if forward_all_events && bridge_enabled

  if busing_event[:action] == "set"
    publish_entity_state(
      mqtt,
      logger,
      busing_event[:entity],
      busing_event[:state],
      mqtt_topic: mqtt_topic,
      raw_event: busing_event
    ) if bridge_enabled
    logger.debug("Event detected: #{busing_event}")
  end
end
