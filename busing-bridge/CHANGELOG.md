# Changelog

## Unreleased

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
