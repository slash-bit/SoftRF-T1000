# SoftRF T1000E Dual Protocol (FLARM + FANET) Implementation

![SoftRF](https://img.shields.io/badge/SoftRF-MB177-blue)
![Status](https://img.shields.io/badge/Status-Development-orange)
![License](https://img.shields.io/badge/License-GPL--3.0-green)

A dual-protocol aircraft detection and traffic awareness system for pilots using **Seeed T1000E** hardware with **LR1110 radio chip**. Simultaneously supports **FLARM (Legacy)** and **FANET** protocols with GPS PPS-synchronized time-slicing.

##  Overview

This project extends Moshe Braner's fork of [SoftRF](https://github.com/moshe-braner/SoftRF/tree/master) to SenseCap T1000E-Card device with simultaneous FLARM and FANET protocol support, enabling a single device to detect and transmit position data in two incompatible RF formats without collision or interference.

### Key Features

- **Dual Protocol Support**: FLARM (FSK @ 868.2 MHz) + FANET (LoRa @ 868.2 MHz)
- **GPS PPS Synchronization**: Microsecond-level timing accuracy via GPS pulse-per-second signal
- **Fast Protocol Switching**: ~5-6ms radio reconfiguration between FSK and LoRa modes
- **LR1110 Optimized**: Fast standby mode transitions, minimal SPI overhead
- **Traffic Awareness**: Real-time aircraft detection and collision alerts
- **Multi-Format Export**: NMEA, GDL90, D1090, JSON, MAVLink output
- **SenseCap T1000E Card
<img width="391" height="317" alt="SenseCap_T1000E" src="https://github.com/user-attachments/assets/3e919131-ca08-4444-bbb6-4e658738db44" />

