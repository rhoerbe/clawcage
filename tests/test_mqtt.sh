#!/bin/bash
# MQTT broker connectivity tests (TCP only, no protocol test)

# Test TCP connectivity to MQTT brokers
test_mqtt_tcp() {
    local host=$1
    local name=$2

    # Use bash's /dev/tcp for TCP connectivity test
    if timeout 5 bash -c "echo >/dev/tcp/$host/1883" 2>/dev/null; then
        pass "MQTT TCP: $name ($host:1883) reachable"
        return 0
    else
        skip "MQTT TCP: $name ($host:1883) unreachable"
        return 1
    fi
}

# Test Home Assistant MQTT add-on
test_mqtt_tcp "10.4.4.10" "HA MQTT add-on"

# Test MQTT bridge (Mulberry)
test_mqtt_tcp "10.4.4.17" "MQTT bridge"
