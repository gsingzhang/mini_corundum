# Lightweight Ultrasonic DAQ Protocol (LUDP) Specification

## 1. Overview
The Lightweight Ultrasonic DAQ Protocol (LUDP) is a custom, UDP-based, NACK-oriented transport protocol. It is designed for high-throughput, reliable data streaming from an FPGA to a Host PC over a local Ethernet link (10G/25G/100G) with at most one switch.

Because local Ethernet drops are rare and reordering is practically non-existent, a full ACK-based protocol (like TCP) adds unnecessary complexity to the FPGA. LUDP uses a **Negative Acknowledgement (NACK)** mechanism: the FPGA continuously blasts data and stores a rolling window of recent packets in local memory (BRAM/URAM). If the Host detects a missing sequence number, it sends a NACK. The FPGA pauses live transmission briefly, retrieves the requested packet from the window, and resends it.

### Design Constraints & Features
*   **Transport**: UDP/IP
*   **Endianness**: Network Byte Order (Big-Endian)
*   **Alignment**: All headers are padded to exactly 16 bytes. This aligns perfectly with a 64-bit (8-byte) AXI-Stream data path, requiring exactly 2 clock cycles per header.
*   **MTU**: Assumes standard Ethernet (1500 bytes MTU). Max payload per packet is 1400 bytes to safely fit inside Ethernet/IP/UDP headers without IP fragmentation.
*   **Port**: Default UDP Port `1234` for both directions.

### 3.6. CREDIT Packet (Host -> FPGA)
Used for simple flow control. The host grants the FPGA "credits" to send packets. One credit = One DATA packet. This prevents the FPGA from overwhelming the host's socket buffer. To handle potential CREDIT packet loss, this protocol uses **Absolute Credits** (Total packets the FPGA is allowed to send since Start) rather than relative additions.

| Offset (Bytes) | Field | Size | Description |
| :--- | :--- | :--- | :--- |
| `0` | **Magic** | 16-bit | Fixed identifier `0xDA01`. |
| `2` | **Type** | 8-bit | Always `0x06` for CREDIT. |
| `3` | **Reserved** | 8-bit | `0x00` |
| `4` | **Abs_Credit** | 32-bit | The absolute sequence number the FPGA is allowed to reach. |
| `8` | **Reserved** | 64-bit | Pad to 16 bytes. |

---

## 2. Packet Types

| Type ID | Name | Direction | Description |
| :--- | :--- | :--- | :--- |
| `0x01` | **DATA** | FPGA -> Host | Contains ultrasonic ADC payload. |
| `0x02` | **CMD** | Host -> FPGA | Control commands (Start, Stop, Write Reg, Read Reg). |
| `0x03` | **NACK** | Host -> FPGA | Request retransmission of a lost packet. |
| `0x04` | **CMD_ACK** | FPGA -> Host | Acknowledge receipt of a Posted CMD (e.g., Write). |
| `0x05` | **CMD_CPL** | FPGA -> Host | Completion with Data for a Non-Posted CMD (e.g., Read). |
| `0x06` | **CREDIT**| Host -> FPGA | Flow control credit update to prevent host buffer overflow. |

---

## 3. Packet Header Formats

### 3.1. DATA Packet (FPGA -> Host)
Every data packet sent by the FPGA starts with a 16-byte header.

| Offset (Bytes) | Field | Size | Description |
| :--- | :--- | :--- | :--- |
| `0` | **Magic** | 16-bit | Fixed identifier `0xDA01` (Data Acq 01). |
| `2` | **Type** | 8-bit | Always `0x01` for DATA. |
| `3` | **Flags** | 8-bit | `0x00` = Normal, `0x01` = Retransmitted packet. |
| `4` | **Seq_Num** | 32-bit | Monotonically increasing packet index (0, 1, 2...). Wraps at 4B. |
| `8` | **Length** | 16-bit | Length of the payload in bytes (e.g., `1024`). |
| `10` | **Timestamp** | 32-bit | FPGA cycle counter, trigger ID, or absolute sample index. |
| `14` | **Reserved** | 16-bit | `0x0000` (Used for 64-bit alignment). |
| `16` | **Payload** | N bytes | The raw ultrasonic data. |

**AXI-Stream Mapping (64-bit / 8-byte bus):**
*   **Cycle 1 (tdata[63:0])**: `Magic(16) | Type(8) | Flags(8) | Seq_Num(32)`
*   **Cycle 2 (tdata[63:0])**: `Length(16) | Timestamp(32) | Reserved(16)`
*   **Cycle 3+ (tdata[63:0])**: `Payload`

### 3.2. CMD Packet (Host -> FPGA)
Used by the Host to control the DAQ state machine, read registers, or write configuration. Inspired by PCIe, commands are divided into **Posted** (requires only an ACK) and **Non-Posted** (requires a Completion with Data).

| Offset (Bytes) | Field | Size | Description |
| :--- | :--- | :--- | :--- |
| `0` | **Magic** | 16-bit | Fixed identifier `0xDA01`. |
| `2` | **Type** | 8-bit | Always `0x02` for CMD. |
| `3` | **Flags** | 8-bit | `0x00` = Posted (Write/Control), `0x01` = Non-Posted (Read). |
| `4` | **Cmd_ID** | 32-bit | Command transaction ID (echoed back in ACK or CPL). |
| `8` | **Opcode** | 16-bit | `0x0001` = Start, `0x0002` = Stop, `0x0010` = Read Reg, `0x0011` = Write Reg. |
| `10` | **Arg1** | 32-bit | Address for Read/Write, or Argument for Start/Stop. |
| `14` | **Arg2** | 16-bit | Data to write (if Posted Write), or `0x0000`. |

### 3.3. NACK Packet (Host -> FPGA)
When the host detects a missing sequence number, it sends this packet.

| Offset (Bytes) | Field | Size | Description |
| :--- | :--- | :--- | :--- |
| `0` | **Magic** | 16-bit | Fixed identifier `0xDA01`. |
| `2` | **Type** | 8-bit | Always `0x03` for NACK. |
| `3` | **Reserved** | 8-bit | `0x00` |
| `4` | **Miss_Seq** | 32-bit | The Sequence Number of the lost packet. |
| `8` | **Count** | 16-bit | Number of consecutive missing packets (usually `1`). |
| `10` | **Reserved** | 48-bit | Pad to 16 bytes. |

### 3.4. CMD_ACK Packet (FPGA -> Host)
Sent by the FPGA immediately after receiving and processing a **Posted** CMD packet (e.g., Start, Stop, Write).

| Offset (Bytes) | Field | Size | Description |
| :--- | :--- | :--- | :--- |
| `0` | **Magic** | 16-bit | Fixed identifier `0xDA01`. |
| `2` | **Type** | 8-bit | Always `0x04` for CMD_ACK. |
| `3` | **Status** | 8-bit | `0x00` = Success, `0x01` = Invalid Opcode, `0x02` = Invalid Arg. |
| `4` | **Cmd_ID** | 32-bit | The `Cmd_ID` from the original CMD packet. |
| `8` | **Opcode** | 16-bit | The `Opcode` from the original CMD packet. |
| `10` | **Reserved** | 48-bit | Pad to 16 bytes. |

### 3.5. CMD_CPL Packet (FPGA -> Host)
Sent by the FPGA after executing a **Non-Posted** CMD packet (e.g., Read Register). This acts as both an ACK and a data payload return.

| Offset (Bytes) | Field | Size | Description |
| :--- | :--- | :--- | :--- |
| `0` | **Magic** | 16-bit | Fixed identifier `0xDA01`. |
| `2` | **Type** | 8-bit | Always `0x05` for CMD_CPL. |
| `3` | **Status** | 8-bit | `0x00` = Success, `0x01` = Invalid Address. |
| `4` | **Cmd_ID** | 32-bit | The `Cmd_ID` from the original CMD packet. |
| `8` | **Opcode** | 16-bit | The `Opcode` from the original CMD packet. |
| `10` | **Read_Data**| 32-bit | The data read from the requested address. |
| `14` | **Reserved** | 16-bit | Pad to 16 bytes. |

---

## 4. Implementation Details

### 4.1. FPGA Hardware Architecture

The LUDP core sits between the ADC/FIFO subsystem and the `udp_complete_64` core. It consists of three main modules:

1.  **`cmd_nack_parser.v` (RX Path)**
    *   **Input**: `rx_udp_payload_axis_*` from `udp_complete_64`.
    *   **Function**: Reads the first 16 bytes. Checks `Magic`. 
    *   If `Type == 0x02` (CMD):
        *   If `Flags == 0x00` (Posted): Updates control registers/memory. Triggers a `CMD_ACK` generation to the TX path.
        *   If `Flags == 0x01` (Non-Posted): Reads the requested register/memory. Triggers a `CMD_CPL` generation to the TX path, attaching the read data.
    *   If `Type == 0x03` (NACK): Extracts `Miss_Seq` and pulses a retransmit request to the TX path.
    *   If `Type == 0x06` (CREDIT): Extracts `Abs_Credit` and updates the TX engine's absolute credit limit.
    *   Drops all other or malformed packets.

2.  **`retransmit_buffer.v` (Storage)**
    *   **Memory**: A dual-port Block RAM (BRAM) or UltraRAM (URAM) configured as a circular buffer.
    *   **Size Calculation**: For a 1KB payload, storing the last 512 packets requires 512KB of memory. On UltraScale+, this easily fits in URAM.
    *   **Addressing**: Uses `Seq_Num % BUFFER_CAPACITY` to determine the start address of a packet.
    *   **Port A (Write)**: Connected to the live transmission path. Saves every outgoing DATA packet.
    *   **Port B (Read)**: Connected to the retransmission multiplexer. Reads out specific packets when requested by a NACK.

3.  **`daq_packetizer.v` (TX Path)**
    *   **Input**: Raw data AXI-Stream from the ADC.
    *   **Output**: `tx_udp_payload_axis_*` to `udp_complete_64`.
    *   **State**: Maintains `Seq_Num` (current packet index) and `Abs_Credit` (maximum allowed packet index).
    *   **Function (Live Mode)**: 
        *   Waits for `Length` bytes of data to be available in the ADC FIFO **AND** `Seq_Num < Abs_Credit`.
        *   Generates the 16-byte DATA header (Cycle 1 & 2).
        *   Passes ADC data (Cycle 3+).
        *   Increments `Seq_Num`.
        *   Simultaneously writes the header and data to `retransmit_buffer.v`.
    *   **Function (Retransmit Mode)**:
        *   If a NACK request is received, it pauses the Live Mode (applying backpressure to the ADC FIFO).
        *   Calculates the memory address of `Miss_Seq`.
        *   Reads the packet from `retransmit_buffer.v`.
        *   Modifies `Flags` to `0x01` (Retransmitted).
        *   Sends to `udp_complete_64`.
        *   Resumes Live Mode.
    *   **Function (CMD_ACK / CMD_CPL Mode)**:
        *   If a response trigger is received from the RX path, pauses Live Mode briefly.
        *   Generates the 16-byte `CMD_ACK` or `CMD_CPL` packet based on the trigger type and data.
        *   Sends the packet and immediately resumes Live Mode.

### 4.2. Host Software Architecture

The host software (Python or C/C++) must be capable of handling high-throughput UDP sockets and reordering packets.

1.  **Socket Configuration**:
    *   Bind a UDP socket to `0.0.0.0:1234`.
    *   Increase the OS socket receive buffer size (e.g., `SO_RCVBUF` to 64MB or higher) to prevent OS-level drops during CPU scheduling spikes.

2.  **Receive Thread (High Priority)**:
    *   Continuously calls `recvfrom()`.
    *   Reads the 16-byte header.
    *   **Check `Seq_Num`**:
        *   If `Seq_Num == Expected_Seq`: Push payload to the application buffer. Increment `Expected_Seq`.
        *   If `Seq_Num > Expected_Seq`: A packet was lost! 
            *   Send a NACK packet for `Expected_Seq`.
            *   Store the out-of-order packet (`Seq_Num`) in a temporary "Out-of-Order Map".
        *   If `Seq_Num < Expected_Seq` AND `Flags == 0x01`: This is a retransmitted packet we requested.
            *   Insert it into the correct position.
            *   Check the Out-of-Order Map to see if we can now advance `Expected_Seq` by multiple steps.
    *   **Credit Management & Keep-Alive**: 
        *   The host maintains a sliding window based on its available buffer size (e.g., `Window_Size = 1024` packets).
        *   Whenever the host successfully processes and consumes $N$ packets (e.g., $N = 64$), it sends a `CREDIT` packet with `Abs_Credit = Last_Consumed_Seq + Window_Size`.
        *   **Lost CREDIT Handling (Timer-based Polling)**: The host must run a timer (e.g., every 50ms). If no new data is received and the host still has available buffer space, it re-transmits the latest `CREDIT` packet. This ensures that if a `CREDIT` packet is dropped by the switch, the FPGA will eventually receive the updated `Abs_Credit` and resume transmission.

3.  **Application Thread**:
    *   Reads contiguous, reliable data from the application buffer.
    *   Sends CMD packets to start/stop the acquisition or read/write registers.
    *   **Implements CMD Retransmission Timeout (RTO)**: When sending a CMD, starts a timer (e.g., 100ms). If a matching `CMD_ACK` (for Posted) or `CMD_CPL` (for Non-Posted) is not received within the timeout, the host resends the CMD.

### 4.3. UDP Checksum Handling

The LUDP implementation disables UDP checksum generation (`UDP_CHECKSUM_GEN_ENABLE = 0`) to support jumbo frames and reduce latency.

**Rationale:**
The `udp_checksum_gen_64` module contains an internal payload FIFO with an effective capacity of 2KB. For jumbo frames (9KB payload + 16-byte LUDP header = 9016 bytes), this FIFO fills up and causes backpressure that stalls transmission. Disabling checksum generation bypasses this bottleneck entirely.

**Validity:**
Per **RFC 768**, the UDP checksum field is optional for IPv4. A transmitted value of `0x0000` explicitly indicates that no checksum was generated. This is widely supported by modern operating systems and NICs.

**Impact Analysis:**

| Layer | Protection | Status |
|-------|-----------|--------|
| Ethernet FCS | Frame corruption on the wire | Active |
| LUDP Magic Number (`0xDA01`) | Protocol identification & header integrity | Active |
| LUDP Sequence Number | Packet ordering, deduplication, gap detection | Active |
| UDP Checksum | End-to-end integrity | Disabled (set to 0) |

In a local Ethernet environment (single switch or direct attach), the Ethernet FCS provides sufficient protection against line errors. The LUDP protocol's magic number and sequence numbers provide additional application-level integrity checks.

**Performance Benefits:**
*   **Reduced latency:** No need to buffer the entire frame before transmission begins.
*   **Lower resource usage:** Eliminates the 2KB payload FIFO in the checksum generator.
*   **Higher throughput:** No backpressure from checksum computation.

**When to Re-enable:**
Consider re-enabling UDP checksum generation (with an increased FIFO depth) if:
*   End-to-end integrity is required across multiple routed network hops.
*   Operating in a noisy electrical environment where higher-layer error detection is desired.
*   The application mandates UDP checksum validation.
*   Using IPv6 (where UDP checksum is mandatory).

### 4.4. Jumbo Frame Support

The LUDP implementation supports variable payload sizes from small tail frames (e.g., 16 bytes) up to 9KB jumbo frames.

**FPGA MAC FIFO Configuration:**
The `eth_mac_10g_fifo` TX/RX FIFOs are configured with `DEPTH = 32768` (32KB). This provides sufficient buffering for 9KB frames, which would otherwise exceed the default 4KB FIFO capacity and be silently dropped by the MAC when `TX_FRAME_FIFO = 1` and `DROP_OVERSIZE_FRAME = 1`.

### 4.5. Edge Cases & Handling
*   **NACK Loss**: If a NACK is lost, the host will notice `Seq_Num` continuing to increase without receiving the retransmitted packet. The host must have a timeout (e.g., 5ms) to resend the NACK if the requested packet has not arrived.
*   **Retransmit Buffer Overwrite**: If the host takes too long to send a NACK, the FPGA might overwrite the old packet in the circular buffer. To prevent this, the FPGA must check if `Miss_Seq` is still valid (i.e., `Current_Seq - Miss_Seq < BUFFER_CAPACITY`). If the packet is already overwritten, the FPGA must either ignore the NACK (causing the host to fail) or send a special "Fatal Error" packet indicating unrecoverable data loss.
