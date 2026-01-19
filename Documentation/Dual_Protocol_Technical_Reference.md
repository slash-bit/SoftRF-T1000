# Dual Protocol (FLARM/FANET) Technical Reference
## Comprehensive Implementation Guide for SoftRF T1000E

**Document Version**: 1.0
**Last Updated**: 2026-01-19
**Target Hardware**: Seeed T1000E with LR1110 radio
**Firmware Version**: SoftRF 1.7.1-vb008
**Implementation**: Based on Moshe Braner's RF Time Slicing Design

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Architecture](#system-architecture)
3. [GPS PPS Timing Synchronization](#gps-pps-timing-synchronization)
4. [FANET TX Scheduling Algorithm](#fanet-tx-scheduling-algorithm)
5. [Protocol Switching Flow](#protocol-switching-flow)
6. [LR1110 Radio Chip Interaction](#lr1110-radio-chip-interaction)
7. [Implementation Details](#implementation-details)
8. [Testing & Verification](#testing--verification)
9. [Troubleshooting](#troubleshooting)
10. [References](#references)

---

## Executive Summary

This document describes the dual protocol time-slicing implementation for simultaneous FLARM and FANET operation on SoftRF T1000E. The design uses GPS PPS (Pulse Per Second) signal to synchronize transmission timing across two incompatible RF protocols:

- **FLARM (Legacy)**: FSK modulation @ 868.2 MHz, 6ms air time per packet
- **FANET**: LoRa modulation @ 868.2 MHz, 36ms air time per packet

**Key Innovation**: Time-based slot allocation prevents protocol conflicts while maintaining ~5 second average transmission interval for FANET.

### Critical Requirement

**GPS PPS signal is mandatory for dual protocol operation.** Without valid GPS fix or PPS, the system reverts to single-protocol mode and prevents transmission to avoid timing collisions.

---

## System Architecture

### 2.1 Operational Modes

#### Single Protocol Mode (Default)
```
FLARM/FANET selection via settings->rf_protocol
Both Slot 0 and Slot 1 available for transmission
Frequency hopping every 4 seconds (per FLARM standard)
No protocol switching overhead
```

#### Dual Protocol Mode (With GPS PPS)
```
FLARM (Legacy): Restricted to Slot 0 only (400-800ms)
FANET: Uses extended Slot 1 (800-1365ms)
Radio chip switches between FSK and LoRa modes
Transmission intervals: FLARM 600-1400ms random, FANET ~5000ms average
```

### 2.2 Hardware Requirements

**GPS Receiver**:
- Supports PPS output (TTL/CMOS)
- Connected to SoC->get_PPS_TimeMarker() function
- Accuracy: ±100µs typical

**LR1110 Radio**:
- Supports both FSK and LoRa packet types
- Fast mode switching: 5-6ms typical
- SPI interface for control
- Standalone RC oscillator mode (standby mode optimization)

**Power Supply**:
- Stable 3.3V for optimal radio performance
- TCXO voltage: 1.6V for Seeed T1000E

### 2.3 Global State Variables

These variables maintain the current protocol state and are updated every time slot boundaries are crossed:

```cpp
static uint32_t RF_time = 0;              // GPS seconds since epoch
static uint8_t  RF_current_slot = 0;      // 0=Slot 0, 1=Slot 1
static uint32_t RF_OK_from = 0;           // Slot start in milliseconds
static uint32_t RF_OK_until = 0;          // Slot end in milliseconds
static uint32_t FANETTimeMarker = 0;      // Next FANET TX time (persistent)
static uint8_t  dual_protocol = RF_FLR_NONE;  // Dual protocol mode identifier
static uint32_t TxEndMarker = 0;          // Must finish TX before this time
static uint32_t TxTimeMarker = 0;         // Random TX window marker
```

---

## GPS PPS Timing Synchronization

### 3.1 PPS Signal Overview

The GPS PPS output provides a precise 1-second pulse synchronized to UTC time. This pulse is the reference point for all slot calculations.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    1-SECOND GPS PPS CYCLE                                │
│                   (Repeats every UTC second)                             │
└─────────────────────────────────────────────────────────────────────────┘

     0ms      1000ms (next PPS)
     │         │
     ▼         │
    [PPS]      │
     │         │
     │ ┌───────┴────┐
     │ │            │
     ▼ ▼            ▼
  ┌─────┬────┬──────┬────┐
  │     │ S0 │ S1  │ │  │
  └─────┴────┴──────┴────┘
     0    400  800 1365 2000ms

  S0: Slot 0 (FLARM: 400-800ms)
  S1: Slot 1 (FANET: 800-1365ms)
```

### 3.2 Time Since PPS Calculation

```cpp
// In RF_SetChannel():
unsigned long pps_btime_ms = SoC->get_PPS_TimeMarker();
unsigned long now_ms = millis();
unsigned long ms_since_pps = now_ms - pps_btime_ms;

// Handle rollover (PPS marker stale after 2 seconds)
if (ms_since_pps > 2000) {
  ms_since_pps = 0;
}
```

### 3.3 Time Reference Alignment

The system adjusts the GPS time (`RF_time`) and reference milliseconds (`ref_time_ms`) to handle edge cases:

**Case 1: Normal Operation** (ms_since_pps 0-1000)
- Use current PPS marker as reference
- `slot_base_ms = ref_time_ms`

**Case 2: PPS Rollover** (ms_since_pps >= 1000)
- Increment RF_time
- Adjust ref_time_ms forward
- Recalculate ms_since_pps

**Case 3: Mid-Slot 1 Rollover** (ms_since_pps < 300 at slot boundary)
- Decrement RF_time back to previous second
- Keep channel stable across PPS boundary
- Prevents receiver frequency glitches

```cpp
// Handle edge case: PPS rollover in middle of Slot 1
if (ms_since_pps < 300) {
  --RF_time;
  slot_base_ms -= 1000;
  ms_since_pps += 1000;
}
```

### 3.4 Slot Detection State Machine

```
      ms_since_pps
         │
         ├─ 0-380ms: Guard period (no transmission)
         │
         ├─ 380-800ms: SLOT 0 SETUP ──┐
         │   └─ Setup FLARM (FSK)      │
         │   └─ Random TX: 405-795ms   │
         │                             │
         ├─ 800-1200ms: SLOT 1 SETUP ──┤
         │   └─ Setup FANET (LoRa)     │
         │   └─ TX scheduled 4-7s      │
         │                             │
         ├─ 1200-1380ms: Extended Slot 1 ─┘
         │   └─ RX only (extended window)
         │
         └─ 1380-2000ms: Guard period
            └─ Next PPS coming
```

---

## FANET TX Scheduling Algorithm

### 4.1 The Algorithm (Moshe's Design)

When entering Slot 1 (approximately every second), the system selects the next FANET transmission time using a probabilistic algorithm:

```cpp
// Input: Current slot_base_ms (reference time for current PPS)
// Output: FANETTimeMarker (when to transmit FANET next)

uint32_t when = SoC->random(0, (565+565));  // Random in range [0, 1130)

if (when < 565) {
    when += 1000;         // 50% probability: TX 3-4 seconds in future
}
else if (when > 848) {
    when -= 565;          // 25% probability: TX ~5 seconds (2nd half of slot)
}
else {
    when += (2000 - 565); // 25% probability: TX 6-7 seconds (1st half of slot)
}

FANETTimeMarker = slot_base_ms + 4805 + when;
```

### 4.2 Distribution Analysis

**Visual Distribution** (time relative to slot_base_ms):

```
Probability Density Function:
┌──────────────────────────────────────────────────────────────┐
│                  FANET TX Scheduling Distribution              │
├──────────────────────────────────────────────────────────────┤
│                                                                │
│    Probability                                                 │
│       ▲                                                         │
│       │     ┌─────────┐         ┌──────────┐                 │
│       │     │ 50%     │ (gap)   │ 25% each │                 │
│       │     │ [5088,  │         │ [5088]   │                 │
│       │     │  5570)  │         │ [6805]   │                 │
│       ├─────┼─────────┼─────────┼──────────┼─────────────────┤
│       0   5000      5500      6000      6500      7000 ms    │
│                                                                │
│  Result:                                                       │
│  • Minimum TX time: 5088ms (50% - 565ms = 4523ms from now)  │
│  • Maximum TX time: 7088ms (50% + 2283ms = 6283ms from now) │
│  • Average interval: ~5000ms (5 seconds)                      │
│  • Standard deviation: ~600ms                                 │
│  • No TX in Slot 0 windows (avoids conflicts)                │
└──────────────────────────────────────────────────────────────┘
```

### 4.3 Key Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Base offset | 4805ms | Ensures TX occurs 4-7 seconds in future |
| Random window | 1130ms | Combination of 565ms (Slot 1 duration) + 565ms |
| Slot 1 duration | 565ms | 800-1365ms window |
| 50% case offset | +1000ms | Full slot 1, 3-4 seconds ahead |
| 25% case 1 | -565ms | Second half, ~5 seconds (2nd half of future slot 1) |
| 25% case 2 | +1435ms | First half, 6-7 seconds (1st half of future slot 1) |
| Average interval | 5000ms | Matches FANET standard (2500-3500ms is legacy) |

### 4.4 Persistence Across Protocol Switches

**Critical Behavior**: `FANETTimeMarker` persists across protocol switches. It is NOT reset when switching to FLARM.

```cpp
// After FANET TX completes:
if (dual_protocol == RF_FLR_FANET) {
    if (current_RF_protocol == RF_PROTOCOL_FANET) {
        // Schedule next FANET TX in 5 seconds
        FANETTimeMarker = RF_OK_until + 5000;
    } else {
        // FLARM TX: don't transmit again this slot
        TxTimeMarker = RF_OK_until;
    }
}
```

This ensures FANET transmissions continue at regular intervals even while alternating between FLARM and FANET protocols.

---

## Protocol Switching Flow

### 5.1 State Machine Overview

The protocol switching is controlled by GPS PPS timing, NOT elapsed time counters:

```
┌─────────────────────────────────────────────────────────────┐
│                  RF_SetChannel() Loop                         │
│            Called from RF_loop() every ~100ms                │
└─────────────────────────────────────────────────────────────┘
            │
            ├── [GPS PPS available?] ──NO──→ Use fallback timing
            │                                └─→ RF_TIMING_INTERVAL
            │
            └──YES──┐
                    │
                    ├─ Compute ms_since_pps
                    ├─ Adjust RF_time for rollover
                    ├─ Check: already in current slot?
                    │  └─→ YES: Return early (no update)
                    │  └─→ NO: Continue
                    │
                    ├─ Branch on ms_since_pps:
                    │
                    ├─ [380, 800): SLOT 0 SETUP ──┐
                    │   ├─ RF_current_slot = 0     │
                    │   ├─ Set RF_OK_from/until    │
                    │   ├─ Generate random TxTime  │
                    │   └─ Reconfigure to FSK      │
                    │                              │
                    ├─ [800, 1200): SLOT 1 SETUP ─┤
                    │   ├─ RF_current_slot = 1     │
                    │   ├─ Set RF_OK_from/until    │
                    │   ├─ Schedule FANET TX       │ ← Moshe's algorithm
                    │   └─ Reconfigure to LoRa     │
                    │                              │
                    └─ Apply RF frequency/channel ─┘
                       └─ rf_chip->channel()
```

### 5.2 Time Slot Setup (Slot 0)

**Trigger**: ms_since_pps enters range [380, 800)

```cpp
RF_current_slot = 0;
RF_OK_from      = slot_base_ms + 405;   // Earliest TX allowed
RF_OK_until     = slot_base_ms + 800;   // Next slot starts
TxEndMarker     = slot_base_ms + 795;   // Must finish TX by this time
TxTimeMarker    = slot_base_ms + 405 + SoC->random(0, 385);

// In dual mode: ensure FLARM protocol
if (settings->dual_protocol) {
    dual_protocol = RF_FLR_FANET;
    current_RF_protocol = RF_PROTOCOL_LEGACY;
    protocol_encode = &legacy_encode;
    protocol_decode = &legacy_decode;

    // Reconfigure radio to FSK mode
    if (rf_chip && rf_chip->type == RF_IC_LR1110) {
        lr11xx_reconfigure_protocol();  // ~5ms
    }
}
```

**Result**:
- Transmission window: 405-795ms (390ms window)
- Random TX time: Within 405-790ms
- Average TX interval: (600-1400)/2 = 1000ms
- Air time: 6ms (FSK Manchester encoded)

### 5.3 Time Slot Setup (Slot 1)

**Trigger**: ms_since_pps enters range [800, 1200)

```cpp
RF_current_slot = 1;
RF_OK_from      = slot_base_ms + 805;   // RX starts earlier than TX window
RF_OK_until     = slot_base_ms + 1380;  // EXTENDED (not 1200!)
TxEndMarker     = slot_base_ms + 1370;  // Leave 10ms margin for packet end

if (settings->dual_protocol && dual_protocol == RF_FLR_FANET) {
    // Apply Moshe's FANET TX scheduling algorithm
    uint32_t when = SoC->random(0, (565+565));

    if (when < 565)
        when += 1000;
    else if (when > 848)
        when -= 565;
    else
        when += (2000 - 565);

    FANETTimeMarker = slot_base_ms + 4805 + when;

    // Switch to FANET protocol
    current_RF_protocol = RF_PROTOCOL_FANET;
    protocol_encode = &fanet_encode;
    protocol_decode = &fanet_decode;

    // Reconfigure radio to LoRa mode
    if (rf_chip && rf_chip->type == RF_IC_LR1110) {
        lr11xx_reconfigure_protocol();  // ~6ms
    }
} else {
    // Single protocol mode: FLARM uses both slots
    TxEndMarker = slot_base_ms + 1195;
    TxTimeMarker = slot_base_ms + 805 + SoC->random(0, 385);
}
```

**Result**:
- RX window: 805-1365ms (560ms extended)
- Allows reception of extended FANET traffic
- FANET TX: Scheduled 4805ms into future
- Next FANET TX typically occurs 5-7 seconds later

---

## LR1110 Radio Chip Interaction

### 6.1 Protocol Reconfiguration Timing

The LR1110 radio chip must be reconfigured at each slot transition to switch between FSK (FLARM) and LoRa (FANET) packet types.

**Measured Performance**:
```
Current Implementation: 5-6ms total
├─ standby(RC) - 1ms
├─ setPacketType() - 1ms
├─ setBandwidth() - 0.5ms
├─ setSyncWord() - 0.5ms
├─ Other settings - 1.5ms
└─ Enter RX mode - 0.5ms
```

**Critical Path**:
1. Enter standby RC mode (fastest, uses internal oscillator)
2. Switch packet type (FSK ↔ LoRa)
3. Apply protocol-specific parameters
4. Return to RX mode

### 6.2 Current Implementation Issues

**Issue #1: Redundant Delays**
```cpp
// BEFORE (radiolib.cpp line 1375):
state = radio_semtech->standby(RADIOLIB_LR11X0_STANDBY_RC);
delay(1);  // ← RadioLib already waits internally!

state = radio_semtech->setPacketType(RADIOLIB_LR11X0_PACKET_TYPE_GFSK);
delay(1);  // ← RadioLib already waits internally!
```

RadioLib's SPI transaction functions internally wait for the BUSY pin, so explicit delays are redundant and waste 2ms per reconfiguration.

**Issue #2: Protocol Switching Frequency**
- Current design: Reconfigures on EVERY slot entry (every ~400-600ms)
- Problem: Unnecessary overhead during RX-only periods
- Solution: Reconfigure only at slot transitions when dual_protocol enabled

### 6.3 LR1110 FSK Parameters (FLARM)

```cpp
// From radiolib.cpp lr11xx_reconfigure_protocol(), FSK branch:

state = radio_semtech->setPacketType(RADIOLIB_LR11X0_PACKET_TYPE_GFSK);

// Bitrate: 38.4 kbps (FLARM standard)
state = radio_semtech->setBitRate(38.4);

// Frequency deviation: 10 kHz (FLARM standard)
state = radio_semtech->setFrequencyDeviation(10.0);

// RX Bandwidth: 156.2 kHz (supports 38.4 kbps ±10 kHz)
state = radio_semtech->setRxBandwidth(156.2);

// Preamble: 8 bytes Manchester encoded = 64 bits in data
state = radio_semtech->setPreambleLength(rl_protocol->preamble_size * 8);

// Packet length: Fixed (24 payload + 2 CRC + manchester = 52 bytes)
state = radio_semtech->fixedPacketLengthMode(pkt_size);

// Sync word: FLARM sync bytes (with preamble workaround)
state = radio_semtech->setSyncWord(sword, 4);

// Data shaping: Gaussian filter for FSK
state = radio_semtech->setDataShaping(RADIOLIB_SHAPING_0_5);
```

### 6.4 LR1110 LoRa Parameters (FANET)

```cpp
// From radiolib.cpp lr11xx_reconfigure_protocol(), LoRa branch:

state = radio_semtech->setPacketType(RADIOLIB_LR11X0_LORA_SYNC_WORD_PRIVATE);

// Bandwidth: 250 kHz (FANET Zone 1 standard)
state = radio_semtech->setBandwidth(250.0);

// Spreading Factor: 7 (balance between range and air time)
state = radio_semtech->setSpreadingFactor(7);

// Coding Rate: 5 (4/8 - 4 data bits per 8 transmitted bits)
state = radio_semtech->setCodingRate(5);

// Sync Word: FANET private sync word
state = radio_semtech->setSyncWord((uint8_t) rl_protocol->syncword[0]);

// Preamble: 8 symbols
state = radio_semtech->setPreambleLength(8);

// CRC: Enabled
state = radio_semtech->setCRC(true);

// Header: Explicit (size in packet)
state = radio_semtech->explicitHeader();
```

### 6.5 TCXO Voltage Configuration

The LR1110 TCXO (Temperature Compensated Crystal Oscillator) voltage varies by board variant:

| Model | TCXO Voltage | Notes |
|-------|--------------|-------|
| Seeed T1000E | 1.6V | Default for this project |
| HPDTeK HPD-16E | 3.0V | Standalone and Badge variants |
| Ebyte E80 | 1.8V | Academy variant |
| RadioMaster XR1 | 0.0V (XTAL) | Nano uses XTAL, not TCXO |

---

## Implementation Details

### 7.1 Global Variables Initialization

These variables should be declared static in RF.cpp:

```cpp
// Timing state
static uint32_t RF_time = 0;              // GPS seconds
static uint8_t  RF_current_slot = 0;      // 0 or 1
static uint32_t RF_OK_from = 0;           // Slot start (ms)
static uint32_t RF_OK_until = 0;          // Slot end (ms)
static uint32_t FANETTimeMarker = 0;      // Next FANET TX (ms)
static uint8_t  dual_protocol = RF_FLR_NONE;  // Mode flag

// Transmission timing (already exist)
extern uint32_t TxTimeMarker;             // Next TX time
extern uint32_t TxEndMarker;              // TX must finish by

// Radio state (already exist)
extern uint8_t  current_RF_protocol;      // Current protocol encoding
extern size_t (*protocol_encode)(void *, ufo_t *);
extern bool   (*protocol_decode)(void *, ufo_t *, ufo_t *);
```

### 7.2 RF_SetChannel() Pseudocode

```
function RF_SetChannel():
    pps_btime_ms = SoC->get_PPS_TimeMarker()

    if not pps_btime_ms:
        use fallback timing (RF_TIMING_INTERVAL)
        return

    now_ms = millis()
    ms_since_pps = (now_ms - pps_btime_ms) % 1000

    compute RF_time from GPS
    adjust for PPS rollover

    if now_ms < RF_OK_until:
        return early (still in current slot)

    if ms_since_pps in [380, 800):
        setup_slot_0()  // FLARM
    else if ms_since_pps in [800, 1200):
        setup_slot_1()  // FANET

    apply_rf_frequency_channel()
```

### 7.3 Helper Functions

```cpp
bool RF_Transmit_Happened()
{
    // Check if TX already happened this slot
    if (!TxEndMarker)
        return (TxTimeMarker > millis());

    if (FANETTimeMarker)
        return (FANETTimeMarker == RF_OK_until);

    return (TxTimeMarker >= RF_OK_until);
}

bool RF_Transmit_Ready(bool wait)
{
    // Check if it's time to transmit
    if (RF_Transmit_Happened())
        return false;

    uint32_t now_ms = millis();

    if (!TxEndMarker)
        return (now_ms > TxTimeMarker);

    uint32_t when = FANETTimeMarker ? FANETTimeMarker : TxTimeMarker;

    return (now_ms >= (wait ? when : RF_OK_from) && now_ms < when);
}
```

---

## Testing & Verification

### 8.1 Unit Tests

**Test 1: FANET TX Distribution**
```cpp
void test_fanet_scheduling_distribution()
{
    uint32_t slot4_count = 0, slot5_count = 0, slot6_count = 0;

    for (int i = 0; i < 10000; i++) {
        uint32_t when = SoC->random(0, 1130);

        if (when < 565)
            slot5_count++;  // 50%
        else if (when > 848)
            slot4_count++;  // 25%
        else
            slot6_count++;  // 25%
    }

    // Verify distribution is approximately 50/25/25
    assert(abs(slot5_count - 5000) < 200);
    assert(abs(slot4_count - 2500) < 200);
    assert(abs(slot6_count - 2500) < 200);
}
```

**Test 2: Slot Timing Calculations**
```cpp
void test_slot_timing()
{
    uint32_t pps_time = 1000;
    uint32_t test_times[] = {405, 500, 800, 805, 1000, 1365};

    for (uint32_t test_ms : test_times) {
        uint32_t ms_since_pps = test_ms;

        // Slot 0: [380, 800)
        if (ms_since_pps >= 380 && ms_since_pps < 800) {
            assert(RF_current_slot == 0);
        }
        // Slot 1: [800, 1200)
        else if (ms_since_pps >= 800 && ms_since_pps < 1200) {
            assert(RF_current_slot == 1);
        }
    }
}
```

### 8.2 Serial Monitor Validation

**Expected Output**:
```
[INFO] Dual protocol mode enabled
[RF] GPS PPS acquired at 1234567ms
[RF] Entering Slot 0 (FLARM) at PPS+405ms
[RF] Current protocol: LEGACY (0)
[RF] TX scheduled for PPS+612ms
[LR11XX] Reconfiguring for FSK mode (FLARM)
[LR11XX] → StandBy RC mode (1ms)
[LR11XX] → Set packet to FSK mode (1ms)
[LR11XX] → Set bitrate 38.4 kbps
[LR11XX] → Set bandwidth 156.2 kHz
[LR11XX] Protocol reconfiguration complete in 5ms

... (395ms later) ...

[RF] Entering Slot 1 (FANET) at PPS+805ms
[RF] Current protocol: FANET (6)
[LR11XX] Reconfiguring for LoRa mode (FANET)
[LR11XX] → StandBy RC mode (1ms)
[LR11XX] → Set packet to LoRa mode (1ms)
[LR11XX] → Set bandwidth 250 kHz
[LR11XX] → Set SF=7, CR=5
[LR11XX] Protocol reconfiguration complete in 6ms
[RF] FANET TX scheduled for PPS+5643ms (5.6s from now)

... (5.6 seconds later) ...

[RF] FANET TX Ready at PPS+843ms (in future second's Slot 1)
[RF] Transmitting FANET packet
[TX] Counter: 42
[RF] Next FANET TX scheduled in 5000ms
```

### 8.3 Spectrum Analyzer Verification

**Setup**:
- **Center Frequency**: 868.2 MHz
- **Span**: 2 MHz (868-870 MHz)
- **RBW (Resolution Bandwidth)**: 1 kHz
- **Detector**: Peak hold
- **Time**: 15 seconds continuous
- **Trigger**: GPS PPS (if available)

**Expected Pattern**:

```
TIME     S0 FLARM    S1 (Guard)    S1 FANET        S0 FLARM    ...
────     ─────────   ───────────   ────────────    ─────────────
0ms      ╱───────╲
100ms    ╱───────╲   (peak decay)
400ms    ╱───────╲
500ms    ╱───────╲   (peak decay)
600ms    ╱───────╲   (peak decay)
700ms    ╱───────╲   (peak decay)
800ms            ──  QUIET (transition)
805ms                ╱╲╱╲╱╲ (LoRa chirps)
836ms                ╱╲╱╲╱╲
1000ms               ╱╲╱╲╱╲ (LoRa chirps - FANET)
1365ms          ── QUIET (end of slot 1)
1380ms          ──  (guard/transition)
5000ms          ──                   ╱───────╲ (next FLARM)
5088ms                        ╱╲╱╲╱╲ (FANET in next)

Legend:
╱───────╲ = FSK burst (FLARM, ~6ms duration, 100 kHz BW)
╱╲╱╲╱╲   = LoRa chirps (FANET, ~36ms duration, 250 kHz BW)
──       = Quiet (RX only or transition)
```

**Visual Characteristics**:

1. **FLARM (FSK)**:
   - Appears 400-800ms after PPS
   - Narrow ~100 kHz bandwidth
   - Sharp on/off edges
   - ~6ms duration
   - Power level: -10 to -5 dBm (typical)

2. **FANET (LoRa)**:
   - Appears 800-1365ms after PPS (and later slots)
   - Wide ~250 kHz bandwidth
   - Distinctive up/down chirp patterns
   - ~36ms duration
   - Power level: -15 to -10 dBm (typical)

3. **Timing**:
   - No overlap between FLARM and FANET
   - ~565ms between end of Slot 0 and end of Slot 1
   - Consistent 1-second cycle

### 8.4 Logic Analyzer Measurements

**Signals to Capture**:
1. GPS PPS (TTL input)
2. LR1110 BUSY pin
3. LR1110 IRQ (DIO) pin
4. UART TX debug output

**Measurements**:
- Protocol switch time: Measure from BUSY going low to IRQ ready (should be 5-6ms)
- Slot entry timing: Compare PPS edge to first protocol switch (should be ±10ms)
- TX timing: Measure from TX trigger to radio transmitting (should be <50ms)

---

## Troubleshooting

### 9.1 GPS PPS Not Acquired

**Symptom**: Serial output shows `[GPS] No PPS signal`

**Diagnosis**:
- Check GPS receiver is powered and has fix (LED blinking)
- Verify PPS output connected to correct GPIO pin
- Check `SoC->get_PPS_TimeMarker()` returns non-zero value

**Recovery**:
```cpp
// System falls back to:
RF_timing = RF_TIMING_INTERVAL;  // Standard timing, no PPS sync
settings->dual_protocol = 0;     // Disable dual mode
// Single protocol operation resumes
```

### 9.2 Protocol Switches Not Occurring

**Symptom**: Serial shows only FLARM packets, no FANET

**Diagnosis**:
- Verify `settings->dual_protocol == 1` in EEPROM
- Check GPS PPS is valid (above)
- Monitor `ms_since_pps` values - should see transitions at 800ms

**Debug Output**:
```cpp
// Add to RF_SetChannel():
if (settings->debug_flags & DEBUG_DEEPER) {
    Serial.print("ms_since_pps=");
    Serial.print(ms_since_pps);
    Serial.print(", slot=");
    Serial.print(RF_current_slot);
    Serial.print(", protocol=");
    Serial.println(current_RF_protocol);
}
```

### 9.3 FANET TX Not Occurring

**Symptom**: FLARM packets transmitted, but no FANET

**Diagnosis**:
- Check `FANETTimeMarker` is being set during Slot 1 setup
- Verify transmission is actually triggered (check TX counter)
- Monitor `RF_Transmit_Ready()` return value

**Debug Output**:
```cpp
// In RF_SetChannel() during Slot 1:
Serial.print("FANETTimeMarker=");
Serial.print(FANETTimeMarker);
Serial.print(", now=");
Serial.println(millis());
```

### 9.4 Timing Jitter

**Symptom**: Spectrum analyzer shows FANET bursts at inconsistent times

**Likely Cause**: GPS PPS jitter or system time base drift

**Analysis**:
- Measure PPS signal with oscilloscope (should be <100µs jitter)
- Compare GPS timestamp to actual slot entry time
- Check system clock is stable (no long delays in main loop)

**Mitigation**:
- Add PPS margin: `ms_since_pps <= 300` instead of `< 300`
- Use averaged GPS time over multiple PPS cycles
- Consider adding NTP sync if available

### 9.5 Memory Leaks During Protocol Switches

**Symptom**: Heap memory decreases over time

**Diagnosis**:
- Monitor heap in RF_loop():
  ```cpp
  static uint32_t last_heap = 0;
  uint32_t current_heap = SoC->getFreeHeap();
  if (current_heap < last_heap) {
      Serial.print("Heap leak: ");
      Serial.println(last_heap - current_heap);
  }
  last_heap = current_heap;
  ```

**Root Causes**:
- Protocol pointers not properly cleaned up
- Dynamic allocations in lr11xx_reconfigure_protocol()
- SPI transaction buffers not freed

**Fix**: Review radiolib.cpp memory allocations

---

## References

### A. Protocol Specifications

**FLARM (Legacy)**:
- Frequency: 868.2 MHz (868.0-868.4 MHz hopping)
- Modulation: 2-FSK, 50 kHz deviation (±25 kHz)
- Bitrate: 38.4 kbps
- Packet: 7-byte sync + 24-byte payload + 2-byte CRC
- Encoding: Manchester (doubles bit rate)
- Air Time: ~6ms per packet
- TX Interval: 600-1400ms random

**FANET**:
- Frequency: 868.2 MHz (Zone 1, Europe)
- Modulation: LoRa, 250 kHz bandwidth
- Spreading Factor: 7
- Coding Rate: 4/5
- Packet: 29 bytes (fixed header + variable payload)
- Air Time: ~36ms per packet
- TX Interval: 2500-3500ms (standard) or ~5000ms (dual mode)

### B. File References

| File | Purpose | Key Functions |
|------|---------|----------------|
| RF.cpp | Main RF loop | RF_SetChannel(), RF_loop(), RF_Transmit() |
| radiolib.cpp | LR1110 driver | lr11xx_reconfigure_protocol(), lr11xx_receive() |
| RF.h | RF definitions | Slot structures, constants |
| EEPROM.h | Settings | dual_protocol, rf_protocol flags |

### C. External Resources

- **LR1110 Datasheet**: Section 13 (Radio Control), Section 4 (SPI Timing)
- **FLARM Protocol**: IEEE 802.15.4-like manual encoding
- **FANET Protocol**: https://github.com/3s1d/fanet-stm32
- **Moshe Braner's Code**: RF_time_slicing.txt (this project)

### D. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-19 | Claude | Initial documentation from Moshe's algorithm |

---

**END OF TECHNICAL REFERENCE**

For questions or clarifications, refer to the plan document or CLAUDE.md architecture guide.
