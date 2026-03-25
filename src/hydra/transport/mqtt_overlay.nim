## mqtt_overlay.nim -- SP patterns over MQTT topics.
##
## Maps SP patterns to MQTT topic conventions.
## Requires an external MQTT 5.0 broker.

{.experimental: "strict_funcs".}

import ../wire

# =====================================================================================================================
# Topic mapping
# =====================================================================================================================

type
  MqttOverlayConfig* = object
    broker_host*: string
    broker_port*: int
    topic_prefix*: string

  PatternMapping* = object
    publish_topic*: string
    subscribe_topic*: string
    response_topic*: string  ## For REQREP/SURVEY

proc default_mqtt_config*(host: string = "localhost", port: int = 1883,
                          prefix: string = "sp"): MqttOverlayConfig =
  MqttOverlayConfig(broker_host: host, broker_port: port, topic_prefix: prefix)

proc map_pubsub*(config: MqttOverlayConfig, channel: string): PatternMapping =
  ## PUBSUB: pub writes to topic, sub subscribes to topic.
  PatternMapping(
    publish_topic: config.topic_prefix & "/pubsub/" & channel,
    subscribe_topic: config.topic_prefix & "/pubsub/" & channel)

proc map_pipeline*(config: MqttOverlayConfig, queue: string): PatternMapping =
  ## PIPELINE: push writes to shared subscription topic.
  PatternMapping(
    publish_topic: config.topic_prefix & "/pipeline/" & queue,
    subscribe_topic: "$share/sp_pull/" & config.topic_prefix & "/pipeline/" & queue)

proc map_reqrep*(config: MqttOverlayConfig, service: string, request_id: string): PatternMapping =
  ## REQREP: req writes to service topic, rep subscribes; response via response topic.
  PatternMapping(
    publish_topic: config.topic_prefix & "/reqrep/" & service & "/request",
    subscribe_topic: config.topic_prefix & "/reqrep/" & service & "/request",
    response_topic: config.topic_prefix & "/reqrep/" & service & "/response/" & request_id)

proc map_survey*(config: MqttOverlayConfig, survey_id: string): PatternMapping =
  ## SURVEY: surveyor publishes question, respondents reply to response topic.
  PatternMapping(
    publish_topic: config.topic_prefix & "/survey/" & survey_id & "/question",
    subscribe_topic: config.topic_prefix & "/survey/" & survey_id & "/question",
    response_topic: config.topic_prefix & "/survey/" & survey_id & "/response")

proc map_bus*(config: MqttOverlayConfig, mesh: string): PatternMapping =
  ## BUS: all nodes subscribe and publish to same topic.
  PatternMapping(
    publish_topic: config.topic_prefix & "/bus/" & mesh,
    subscribe_topic: config.topic_prefix & "/bus/" & mesh)

# =====================================================================================================================
# Connection types (abstract -- actual MQTT I/O delegates to mqtt satellite)
# =====================================================================================================================

type
  MqttPublishFn* = proc(topic: string, payload: string) {.raises: [SpError].}
  MqttSubscribeFn* = proc(topic: string) {.raises: [SpError].}
  MqttRecvFn* = proc(): string {.raises: [SpError].}

  MqttOverlayConn* = ref object
    config*: MqttOverlayConfig
    mapping*: PatternMapping
    publish_fn*: MqttPublishFn
    subscribe_fn*: MqttSubscribeFn
    recv_fn*: MqttRecvFn

proc overlay_send*(conn: MqttOverlayConn, data: string) {.raises: [SpError].} =
  conn.publish_fn(conn.mapping.publish_topic, data)

proc overlay_recv*(conn: MqttOverlayConn): string {.raises: [SpError].} =
  conn.recv_fn()

proc close*(conn: MqttOverlayConn) {.raises: [].} =
  discard
