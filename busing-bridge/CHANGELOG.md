# Changelog

## Unreleased

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
