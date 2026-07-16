"""Busing protocol constants shared by the bridge modules."""

# Busing command codes
READ_MEM = 3
WRITE_MEM = 4
READ_EEPROM = 5
READ_ADDRESS = 7
READ_DEV_TYPE = 9

# Known device types, keyed by the type id reported by READ_DEV_TYPE
DEV_TYPES = {
    23: "KCTR_KA",
    24: "2E2S",
    6: "SMART_TOUCH",
}

UNKNOWN_DEVICE_TYPE = "UNKNOWN"
