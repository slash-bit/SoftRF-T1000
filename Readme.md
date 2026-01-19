# SoftRF T1000E Dual Protocol (FLARM + FANET) Implementation

![SoftRF](https://img.shields.io/badge/SoftRF-1.7.1-blue)
![Status](https://img.shields.io/badge/Status-Development-orange)
![License](https://img.shields.io/badge/License-GPL--3.0-green)

A dual-protocol aircraft detection and traffic awareness system for pilots using **Seeed T1000E** hardware with **LR1110 radio chip**. Simultaneously supports **FLARM (Legacy)** and **FANET** protocols with GPS PPS-synchronized time-slicing.

## 🎯 Overview

This project extends [SoftRF](https://github.com/lyusupov/SoftRF) with simultaneous FLARM and FANET protocol support, enabling a single device to detect and transmit position data in two incompatible RF formats without collision or interference.

### Key Features

- **Dual Protocol Support**: FLARM (FSK @ 868.2 MHz) + FANET (LoRa @ 868.2 MHz)
- **GPS PPS Synchronization**: Microsecond-level timing accuracy via GPS pulse-per-second signal
- **Fast Protocol Switching**: ~5-6ms radio reconfiguration between FSK and LoRa modes
- **LR1110 Optimized**: Fast standby mode transitions, minimal SPI overhead
- **Traffic Awareness**: Real-time aircraft detection and collision alerts
- **Multi-Format Export**: NMEA, GDL90, D1090, JSON, MAVLink output
