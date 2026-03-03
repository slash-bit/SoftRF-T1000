# T1000E Debug Logging Guide

## Overview

This guide explains how to capture and analyse debug timing output from a T1000E SoftRF device for testing and performance analysis purposes. The device logs RX timing information that can be analysed to understand packet reception patterns across different protocols.

---

## Prerequisites

- **T1000E SoftRF Device** (or compatible device)
- **USB Cable** (USB-C or appropriate connector)
- **PC/Computer** with USB port
- **Web Browser** supporting Web Serial API (Chrome 89+, Edge 89+)
- **Internet Connection** to access the analyser

---

## Step-by-Step Instructions

### Step 1: Connect Device via USB

1. Connect the T1000E device to your PC using a USB cable
2. Wait for the device to be recognized by your operating system
3. A **Mass Storage window** should automatically open, displaying the device's storage contents
4. You should see a `settings.txt` file in the root directory

### Step 2: Configure Device Settings

#### Open settings.txt

1. In the Mass Storage window, locate and open `settings.txt` file
2. The file contains device configuration parameters
3. Look for the following lines (you may need to scroll to view all settings):

```
protocol,7          # Current Main Protocol (7=LATEST/FLARM)
altprotocol,0       # Alternate Protocol (0=disabled, 5=FANET, etc.)
```

#### Enable Timing Debug Output

1. Scroll to the **bottom** of the `settings.txt` file
2. Locate the `debug_flags` parameter
3. **Change the value to `000010`**

**Example:**
```
# At the bottom of settings.txt
debug_flags,000010
```

This enables "DEBUG DEEPER" in firmware which logs RX packet timing information in the format:
```
RX in prot X, time slot Y, sec Z(C) + M ms
```

### Step 3: Open the Log analyser

1. Open your web browser (Chrome or Edge recommended)
2. Navigate to: **https://ogn.helioho.st/log_analyser/**
3. The analyser interface will load with the serial console connection page

### Step 4: Connect Serial Port

1. Click the **"Connect Serial Port"** button
2. A browser dialog will appear: **"ogn.helioho.st wants to connect to a serial port"**
3. Select the appropriate port from the list:
   - Look for entries like "PCI Serial Port (COM10)" or "CP2104 USB to UART Bridge Controller (COM21)"
   - Choose the port corresponding to your device

**Example Port Selection:**
```
Available Ports:
- PCI Serial Port (COM10)
- CP2104 USB to UART Bridge Controller (COM21)  ← Select this
```

4. Click **"Connect"** to establish the serial connection
5. Confirm the connection by checking the status indicator in the interface

### Step 5: Verify GPS Fix

**Before collecting logs, ensure the device has achieved GPS lock:**

1. Look for GPS status indicators in the console output
2. Common indicators:
   - ✓ Green status: GPS Fix achieved
   - ✗ Red status: No GPS Fix yet

3. Wait until you see stable GPS data:
   ```
   GPS: Fix acquired
   Satellites: 12+
   HDOP: <2.0
   ```

**Important**: GPS timing synchronization is essential for accurate RX timing analysis. Do not proceed without a GPS fix.

### Step 6: Collect Debug Logs

1. Once GPS is locked, start collecting logs
2. **Let the device run for 5-10 minutes** to capture a sufficient number of RX packets
3. This duration allows:
   - Adequate packet sampling across all timing cycles (0-15)
   - Reliable interval statistics between packets
   - Clear pattern identification for analysis

4. The console will display incoming RX timing data:
   ```
   20:19:55.961  RX in prot 7, time slot 1, sec 1771964395(11) + 989 ms
   20:20:23.916  RX in prot 7, time slot 1, sec 1771964423(7) + 944 ms
   20:20:34.149  RX in prot 5, time slot 1, sec 1771964433(1) + 1177 ms
   ```

### Step 7: Submit the Log

1. After collecting 5-10 minutes of data, click the **"Submit Log"** button
2. A **"Submit Console Log"** dialog will appear
3. Fill in all required fields:

#### Device Information Section

- **RX Device (Serial Console):**
  - Enter the device model and identifier
  - Example: `T-Beam v1.1 SoftRF-MB176`

- **Main Protocol:**
  - Select the protocol used for this test
  - Options: LATEST (7), LEGACY (6), FANET (5), P3I (2)
  - Example: Select `LATEST` for protocol 7 tests

- **Alt. Protocol:**
  - Select if an alternate protocol was active
  - Options: NONE (--), LATEST (7), FANET (5), ADSL (8), P3I (2)
  - Leave as `NONE` for single-protocol tests

#### Nearby Transmitter Information Section

- **TX Device (Transmitter):**
  - Enter the transmitting device you're testing against
  - Example: `XC Tracer Maxx II R09`

- **Protocols Enabled:**
  - Check which protocols the transmitter is using
  - Options: FLARM, FANET, ADSL, PILOTAWARE
  - Example: For FLARM packets, check ☑ FLARM

4. Click **"Submit Log"** button
5. The system will:
   - Save the log to your computer (auto-download)
   - Upload to the server for analysis
   - Display confirmation with filename and timestamp

---

## Test Scenarios

Run the following test scenarios to characterize device performance across different protocol configurations:

### Scenario 1: LATEST Protocol Only
- **Main Protocol:** 7 (LATEST)
- **Alt. Protocol:** 0 (None)
- **Description:** Test baseline performance with FLARM/LATEST protocol
- **Expected Output:** RX packets with protocol 7, alternating between Slot 0 and Slot 1

### Scenario 2: FANET Protocol Only
- **Main Protocol:** 5 (FANET)
- **Alt. Protocol:** 0 (None)
- **Description:** Test pure FANET reception
- **Expected Output:** RX packets with protocol 5, free-timing (not slot-based)

### Scenario 3: Dual-Mode (LATEST + FANET)
- **Main Protocol:** 7 (LATEST)
- **Alt. Protocol:** 5 (FANET)
- **Description:** Test simultaneous reception of both protocols
- **Expected Output:** Mixed RX packets showing both protocol 7 and protocol 5 in same log

---

## Between Test Scenarios

**For each new test scenario:**

1. **Eject USB Device** safely from your computer
2. **Re-connect** the device via USB
3. **Update settings.txt** with new protocol configuration:
   ```
   protocol,7          # Change this for new protocol
   altprotocol,0       # Change this for dual-mode tests
   debug_flags,000010  # Keep this enabled
   ```
4. **Save the file** and eject the device
5. **Return to Step 3** (Open Log analyser) to collect new log

---

## Understanding the Log Output

### Timing Debug Format

Each captured RX packet appears in this format:
```
RX in prot X, time slot Y, sec Z(C) + M ms
```

**Components:**
- **prot X:** Protocol number (7=LATEST, 5=FANET, 1=OGNTP, 6=LEGACY, 8=ADSL, 2=P3I)
- **time slot Y:** Slot assignment (0 or 1 for slot-based protocols, ignored for FANET)
- **sec Z:** GPS seconds timestamp (epoch reference)
- **C:** Cycle number within 16-cycle pattern (0-15)
- **M ms:** Milliseconds offset from second boundary (0-1300ms)

**Example:**
```
RX in prot 7, time slot 1, sec 1771964395(11) + 989 ms
         ↓           ↓                    ↓      ↓    ↓
    Protocol 7   Slot 1          GPS second   Cycle 11   989ms offset
   (LATEST)    (Slot 1 RX)        reference    in cycle   from second
```

### Analysis Dashboard

The analyser provides:

1. **Statistics Cards:**
   - Total RX Packets received
   - Slot 0 vs Slot 1 packet distribution
   - FANET packet count
   - Interval statistics (min/max/avg seconds between packets)

2. **RX Timing Distribution Chart:**
   - 50ms histogram bins showing packet concentration
   - 0-1300ms time range covering both slots
   - Color-coded by protocol type
   - Identifies timing anomalies

3. **RX Cycle Distribution:**
   - Shows which cycles (0-15) received packets
   - Detects missing cycles indicating reception gaps
   - Compares slot-based vs FANET distribution

---

## Troubleshooting

### Device Not Recognized
- Ensure USB cable is properly connected
- Try a different USB port on your computer
- Check if drivers are installed (CP2102, CH340, etc.)
- Restart your computer if necessary

### No GPS Fix
- Ensure device has clear line of sight to sky
- Wait 2-5 minutes for initial acquisition
- Check if antenna is properly connected
- Verify GPS is enabled in settings.txt

### No RX Packets Appearing
- Confirm debug_flags is set to `000010`
- Verify transmitting device is powered on and in range
- Check that protocols match between TX and RX devices
- Try relocating closer to transmitter

### Serial Port Connection Failed
- Ensure browser has serial port permission
- Try refreshing the page and reconnecting
- Use Chrome or Edge (Firefox/Safari not supported)
- Check if another application is using the port

---

## Data Format Reference

### Protocol Numbers
| Value | Protocol | Type |
|-------|----------|------|
| 1 | OGNTP | Slot-based |
| 2 | P3I | Free-timing |
| 5 | FANET | Free-timing |
| 6 | LEGACY | Slot-based |
| 7 | LATEST | Slot-based |
| 8 | ADSL | Slot-based |

### Slot Timing Model (Slot-based protocols)
- **Slot 0:** 0-800ms from second boundary
- **Slot 1:** 800-1300ms from second boundary
- **Early packets:** 0-200ms indicates potential radio settling issues

### Cycle Distribution
- **Pattern:** 16 cycles (0-15) repeating
- **Ideal:** Packets distributed across all cycles
- **Anomaly:** Missing cycles suggest timing synchronization issues

---

## Next Steps

After collecting logs:

1. **analyse** the generated reports on the analyser dashboard
2. **Compare** different protocol scenarios to identify performance differences
3. **Identify** patterns in timing distribution and intervals
4. **Document** findings for optimization or debugging purposes

---

## Support & Resources

- **analyser URL:** https://ogn.helioho.st/log_analyser/

---

**Document Version:** 1.0
**Last Updated:** February 2026
