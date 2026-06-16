# LUDP TX DMA AXI 设计文档

## 1. 概述

LUDP TX DMA AXI 模块 (`ludp_tx_dma_axi.sv`) 是 LUDP 协议栈的核心数据搬运引擎，负责将 AXI-Stream 数据流写入 DDR，并从 DDR 读出数据发送到协议 TX 引擎。该模块替代了原有的 BRAM 缓冲方案，将重传缓冲区迁移到 DDR，解决了高速场景下丢包问题。

### 1.1 设计目标

- 支持 10Gbps 线速转发（大帧/jumbo frame 场景）
- AXI-Stream ↔ AXI4 直通架构，无中间 RAM 开销
- 支持 LUDP 协议的 clear 中止机制
- 支持 AXI4 突发传输和 4K 地址边界对齐
- 极简实现，311 行代码

### 1.2 替代方案对比

| 方案 | 数据路径 | 代码量 | clear/abort | 4K 边界 | 评估 |
|------|---------|--------|-------------|---------|------|
| taxi_dma_if_axi | AXI4 → RAM → AXI4 | ~2390 行 | ❌ | ✅ | 不适用：无 AXI-Stream 接口 |
| Corundum axi_dma_wr/rd | AXI-Stream ↔ AXI4 | ~1634 行 | ❌ (abort 未实现) | ✅ | 接近但缺少 clear |
| **ludp_tx_dma_axi (当前)** | **AXI-Stream ↔ AXI4** | **311 行** | **✅** | **✅** | **最优** |

## 2. 架构设计

### 2.1 模块框图

```
                    ┌─────────────────────────────────────────┐
                    │           ludp_tx_dma_axi               │
                    │                                         │
  TX Engine ──────►│ wr_axis_tdata/tvalid/tlast/tkeep        │
  (AXI-Stream)     │     │                                   │
                    │     ▼                                   │
                    │  ┌─────────┐    ┌──────┐    ┌────────┐ │
                    │  │ WR_AW   │───►│WR_DATA│───►│WR_B/   │ │
                    │  │ (发AW)  │    │(写W)  │    │WR_RESP │ │
                    │  └─────────┘    └──────┘    └────────┘ │
                    │         │                      │       │
                    │         ▼                      ▼       │
                    │  m_axi_wr (AW/W/B channels)            │
                    │         │                      │       │
                    │         ▼                      ▼       │
                    │    ┌─────────────────────────────┐     │
                    │    │       AXI4 DDR (RAM)        │     │
                    │    └─────────────────────────────┘     │
                    │         │                      │       │
                    │         ▼                      ▼       │
                    │  m_axi_rd (AR/R channels)              │
                    │     │                                   │
                    │     ▼                                   │
                    │  ┌─────────┐    ┌────────┐             │
                    │  │ RD_AR   │───►│RD_DATA │             │
                    │  │ (发AR)  │    │(读R)   │             │
                    │  └─────────┘    └────────┘             │
                    │     │                                   │
                    │     ▼                                   │
  Proto TX ◄───────│ rd_axis_tdata/tvalid/tlast/tkeep        │
  (AXI-Stream)     │                                         │
                    └─────────────────────────────────────────┘
```

### 2.2 写路径状态机

```
WR_IDLE ──(desc_enable && tvalid)──► WR_AW ──(awready)──► WR_DATA
                                       ▲                      │
                                       │                      │
                                    WR_B ◄──(burst done)──────┤
                                       │                      │
                                       │              (all done)
                                    WR_RESP ◄─────────────────┘
                                       │
                                       ▼
                                    WR_IDLE (wr_done=1)
```

| 状态 | 功能 | 关键信号 |
|------|------|---------|
| WR_IDLE | 等待描述符 | wr_desc_enable, wr_axis_tvalid |
| WR_AW | 发送 AW 地址 | m_axi_wr.awvalid, awready |
| WR_DATA | 写入数据 | m_axi_wr.wvalid, wready, tvalid |
| WR_B | 等待 B 响应（burst 未完成） | m_axi_wr.bvalid |
| WR_RESP | 等待 B 响应（全部完成） | m_axi_wr.bvalid, wr_done |

### 2.3 读路径状态机

```
RD_IDLE ──(rd_desc_req)──► RD_AR ──(arready)──► RD_DATA
    ▲                                         │
    │                                         │
    ├──(rlast && all done)────────────────────┤
    │                                         │
    └──(rlast && more bursts)──► RD_AR ◄──────┘
```

| 状态 | 功能 | 关键信号 |
|------|------|---------|
| RD_IDLE | 等待描述符 | rd_desc_req |
| RD_AR | 发送 AR 地址 | m_axi_rd.arvalid, arready |
| RD_DATA | 接收 R 数据 | m_axi_rd.rvalid, rlast |

### 2.4 关键设计决策

#### 2.4.1 写路径 B 响应等待

写路径在每次 burst 完成后进入 WR_B 状态等待 B 响应，然后再发下一个 AW。这是为了避免 AXI RAM 模型在未收到前一个 B 响应时拒绝新 AW 导致死锁。

权衡：牺牲了 burst 间流水化的吞吐量（每 burst 多 2 cycle 间隙），换取了与 AXI RAM 模型的兼容性和设计简洁性。

#### 2.4.2 读路径 clear 中止

读路径支持 `clear` 信号中止正在进行的传输。当 LUDP 协议层收到 CMD_START 时，需要丢弃当前帧并重新开始。实现方式：

- `clear` 信号设置 `rd_clear_pending_reg` 标志
- 当前 burst 的 rlast 到来时，检查标志
- 如果 clear_pending，完成当前 burst 后回到 RD_IDLE，不发出 rd_done
- 如果不在 RD_DATA 状态，直接在 RD_IDLE 中忽略 clear

这确保了 AXI 事务的完整性——不会在 burst 中途中断，避免 AXI 协议违规。

#### 2.4.3 突发长度锁存

写路径在 AW 被接受时锁存当前 burst 长度到 `wr_cur_burst_len_reg`，避免在 WR_DATA 状态中因 `wr_beats_remaining` 减小导致 burst 长度动态变化。

#### 2.4.4 4K 地址边界对齐

读写路径均实现了 4K 地址边界对齐检查，确保 AXI 突发不跨越 4K 边界：

```systemverilog
wire [MEM_ADDR_W-1:0] wr_4k_boundary = {wr_addr_reg[MEM_ADDR_W-1:12], 12'b0} + 32'h1000;
wire [MEM_ADDR_W-1:0] wr_beats_to_boundary = (wr_4k_boundary - wr_addr_reg) >> BEAT_BYTE_W;
```

关键修复：原始实现使用 `12'h1000`，在 12 位宽度下被截断为 0，导致 `beats_to_boundary=0`，进而 `awlen=255`（256-beat 突发）。修复为 `32'h1000`。

## 3. 吞吐量分析

### 3.1 系统带宽上限

```
AXI 总线: 64-bit × 156.25 MHz = 10.0 Gbps (1.25 GB/s)
10G 以太网: 10.3125 Gbps (线速率) → 有效载荷约 9.6 Gbps
```

AXI 总线带宽与线速率匹配，需要接近 100% 的 AXI 利用率才能线速转发。

### 3.2 写路径效率

写路径 burst 间间隙 = 1 cycle (B 响应) + 1 cycle (AW 接受) = 2 cycles

```
时序图（多 burst 写）:
     ┌──────┐                          ┌──────┐
AW:  │valid │                          │valid │
     └──────┘                          └──────┘
              ┌──────────────────────┐       ┌──────────────────────┐
W:            │  burst 0 (N beats)   │       │  burst 1 (M beats)   │
              └──────────────────────┘       └──────────────────────┘
                                        ┌───┐                    ┌───┐
B:                                     │resp│                    │resp│
                                        └───┘                    └───┘
                                        ◄─ 2 cycles ─►
```

| Payload | Beats | Burst 数 | 数据周期 | 间隙周期 | 写效率 | 写吞吐量 |
|---------|-------|---------|---------|---------|--------|---------|
| 16B | 2 | 1 | 2 | 2 | 50% | 5.0 Gbps |
| 64B | 8 | 1 | 8 | 2 | 80% | 8.0 Gbps |
| 256B | 32 | 1 | 32 | 2 | 94% | 9.4 Gbps |
| 1024B | 128 | 1 | 128 | 2 | 98% | 9.8 Gbps |
| 8960B | 1120 | 5 | 1120 | 10 | 99.1% | 9.9 Gbps |

### 3.3 读路径效率

读路径 burst 间间隙 = 1 cycle (AR 接受)

```
时序图（多 burst 读）:
     ┌──────┐       ┌──────┐
AR:  │valid │       │valid │
     └──────┘       └──────┘
              ┌──────────────┐ ┌──────────────┐
R:            │ burst 0 data │ │ burst 1 data │
              └──────────────┘ └──────────────┘
                              ◄ 1 cycle ►
```

| Payload | Beats | Burst 数 | 数据周期 | 间隙周期 | 读效率 | 读吞吐量 |
|---------|-------|---------|---------|---------|--------|---------|
| 16B | 2 | 1 | 2 | 1 | 67% | 6.7 Gbps |
| 64B | 8 | 1 | 8 | 1 | 89% | 8.9 Gbps |
| 256B | 32 | 1 | 32 | 1 | 97% | 9.7 Gbps |
| 1024B | 128 | 1 | 128 | 1 | 99% | 9.9 Gbps |
| 8960B | 1120 | 5 | 1120 | 5 | 99.6% | 10.0 Gbps |

### 3.4 端到端吞吐量

3-block 调度器提供流水线深度，稳态下写路径和读路径可以重叠：

```
时间线:
Block 0: [DMA WR ][DMA RD ][TX send]
Block 1:         [DMA WR ][DMA RD ][TX send]
Block 2:                 [DMA WR ][DMA RD ][TX send]
         ◄──── pipeline depth = 3 blocks ────►
```

| 场景 | 写效率 | 读效率 | 端到端效率 | 端到端吞吐量 | 是否线速 |
|------|--------|--------|-----------|-------------|---------|
| Jumbo (8960B) | 99.1% | 99.6% | ~99% | ~9.9 Gbps | ✅ |
| 大帧 (1024B) | 98% | 99% | ~98% | ~9.8 Gbps | ✅ |
| 中帧 (256B) | 94% | 97% | ~94% | ~9.4 Gbps | ✅ |
| 小帧 (64B) | 80% | 89% | ~80% | ~8.0 Gbps | ⚠️ |
| 极小帧 (16B) | 50% | 67% | ~50% | ~5.0 Gbps | ❌ |

### 3.5 与 Corundum axi_dma_wr/rd 的吞吐量对比

| 特性 | ludp_tx_dma_axi | axi_dma_wr/rd |
|------|-----------------|---------------|
| Burst 间间隙 (写) | 2 cycles | **0 cycles** (output FIFO) |
| Burst 间间隙 (读) | 1 cycle | **0 cycles** (双状态机) |
| 多 burst 并发 | ❌ 串行 | ✅ status FIFO 追踪 |
| 内部 FIFO | 无 | 32 项 output FIFO |
| 背压处理 | 直接反压 AXI-Stream | FIFO 吸收突发背压 |

Corundum DMA 通过 output FIFO + 多 burst 并发实现零间隙突发：

```
Corundum 写路径（流水化）:
AW0: ┌──────┐┌──────┐┌──────┐
     │valid ││valid ││valid │
     └──────┘└──────┘└──────┘
W:   ┌────────┐┌────────┐┌────────┐
     │burst 0 ││burst 1 ││burst 2 │  ← 无间隙
     └────────┘└────────┘└────────┘
B:                      ┌───┐┌───┐┌───┐  ← B 响应异步回来
                        └───┘└───┘└───┘
```

### 3.6 小帧吞吐量影响评估

小帧场景下的吞吐量损失在实际网络中影响有限：

1. **小帧绝对传输时间短**：64B 帧仅 8 个 AXI beat，间隙 2 cycle 占比虽高（20%），但绝对时间仅 12.8 ns
2. **高吞吐场景使用大帧**：10G 网络的线速场景几乎总是使用 jumbo frame
3. **以太网帧间隔**：10G 以太网最小帧间隔（12B IFG + 8B preamble = 160 ns）本身就限制了小帧 pps
4. **LUDP 协议设计**：LUDP 的 payload_size 由 CMD_START 配置，典型值为 1024B-8960B

### 3.7 吞吐量优化路径（如需）

如果未来需要优化小帧吞吐量，可考虑以下改进：

| 优化 | 效果 | 复杂度 | 说明 |
|------|------|--------|------|
| 写路径 output FIFO | 写间隙 2→0 cycles | +100 行 | FIFO 解耦 AW 和 W 通道 |
| 读路径双状态机 | 读间隙 1→0 cycles | +80 行 | AR 和 R 通道独立运行 |
| 多 burst 并发 | 消除所有间隙 | +150 行 | status FIFO 追踪 burst 完成 |
| 增加 block 数量 | 提高流水线深度 | 参数修改 | NUM_BLOCKS 3→6 |

## 4. 替代方案详细对比

### 4.1 taxi_dma_if_axi（不可用）

| 维度 | taxi_dma_if_axi | ludp_tx_dma_axi |
|------|-----------------|------------------|
| 数据路径 | AXI4 → RAM → AXI4 | AXI-Stream ↔ AXI4 |
| 代码量 | ~2390 行 (3 文件) | ~311 行 (1 文件) |
| AXI-Stream 接口 | ❌ 无 | ✅ 有 |
| 内部 RAM | 强制 2x 宽度 | 无 |
| clear/abort | ❌ | ✅ |
| 延迟 | +2 RAM 周期 | 直通 |

**不可用原因**：数据路径架构根本不同（RAM 中转 vs Stream 直通），无 AXI-Stream 接口。

### 4.2 Corundum axi_dma_wr/axi_dma_rd（接近但不可用）

| 维度 | axi_dma_wr/rd | ludp_tx_dma_axi |
|------|--------------|------------------|
| 数据路径 | AXI-Stream ↔ AXI4 | AXI-Stream ↔ AXI4 |
| 代码量 | ~1634 行 (2 文件) | ~311 行 (1 文件) |
| 4K 边界 | ✅ | ✅ |
| clear/abort | ❌ abort 未实现 | ✅ clear 已实现 |
| 多 burst 并发 | ✅ | ❌ |
| output FIFO | 32 项 | 无 |
| 非对齐传输 | ENABLE_UNALIGNED | 不支持 |

**不可用原因**：`abort` 端口存在但未实现。LUDP 协议需要 `clear` 信号中止读传输，而 `axi_dma_rd` 无法中止正在进行的传输。修改 692 行第三方代码添加 abort 逻辑风险高于自研 311 行精简代码。

## 5. Bug 修复记录

### 5.1 4K 边界计算截断

- **问题**：`12'h1000` 在 12 位宽度下被截断为 0，导致 `beats_to_boundary=0`，`awlen=255`
- **修复**：改为 `32'h1000`
- **影响**：读写路径均受影响

### 5.2 写路径缺少 4K 边界检查

- **问题**：写路径没有 4K 边界对齐检查，AXI 突发可能跨越 4K 边界
- **修复**：添加与读路径一致的 4K 边界检查逻辑

### 5.3 写突发长度动态变化

- **问题**：`wr_burst_len` 是组合逻辑，随 `wr_beats_remaining` 减小而变化，导致 8-beat 突发只发 5 拍就结束
- **修复**：添加 `wr_cur_burst_len_reg` 寄存器，在 AW 被接受时锁存突发长度

### 5.4 协议 TX 与调度器竞态条件

- **问题**：协议 TX 模块在调度器还在处理上一个 DMA 读取时就启动新包，导致 `tx_pkt_start` 被忽略
- **修复**：添加 `sch_ready` 信号，协议 TX 在启动新包前等待调度器就绪

## 6. 验证结果

### 6.1 功能覆盖率

| 测试序列 | UVM_ERROR | 功能覆盖率 |
|----------|-----------|-----------|
| tx_dma_codecov_vseq | 0 | **100%** (25/25) |
| test_all (默认) | 0 | **100%** (25/25) |
| cmd | 0 | 68% |
| credit | 0 | 56% |
| data | 0 | 56% |
| retx | 0 | 68% |
| error | 0 | 68% |
| mech | 0 | 68% |
| basics | 0 | 36% |
| cov | 0 | 92% |
| reset | 0 | 12% |

所有 10 个测试 case 全部通过，0 个 UVM_ERROR。

### 6.2 功能覆盖点 (25 bins)

| 类别 | 覆盖点 | 状态 |
|------|--------|------|
| Protocol RX | ARP reply, CMD_START, CMD_STOP, CMD_ACK, CMD_CPL, CMD skip, CREDIT valid, CREDIT stale, NACK→RETX, NACK no-entry, Bad MAGIC, Unknown TYPE, tuser error, Status suppress | ✅ 全部覆盖 |
| Protocol TX | DATA sent, PRBS OK, PRBS ERR, RETX priority, Status RESP | ✅ 全部覆盖 |
| Scheduler | Block recycle, WR backpressure | ✅ 全部覆盖 |
| System | Reset recovery, Double START, Credit exhaust, Credit advance | ✅ 全部覆盖 |
| Payload | [0] 8-32B, [1] 33-128B, [2] 129-512B, [3] 513-2KB, [4] 2KB-9KB | ✅ 全部覆盖 |
