# Đề Xuất Thực Nghiệm — Engram Sovereign FSM

> **Mục tiêu:** Hoàn thiện evaluation story cho bài báo hướng tới hội thảo chuyên ngành Khoa học máy tính **rank B trở lên**

Trọng tâm là xây dựng một hệ thực nghiệm có tính thuyết phục cho nghiên cứu Engram Sovereign FSM, kết hợp **ba lớp bằng chứng**: đặc tả hình thức, fault-injection prototype và microbenchmark mật mã/đồng thuận.

---

## 1. Câu Hỏi Nghiên Cứu

Câu chuyện thực nghiệm xoay quanh bốn câu hỏi nghiên cứu chính. Các câu hỏi này giúp bài báo không chỉ mô tả một FSM dự phòng cho blockchain modular, mà còn chứng minh được giá trị khoa học và kỹ thuật của cơ chế này dưới các lỗi ngoại vi liên quan đến Bitcoin settlement, DA layer và P2P health.

| # | Câu hỏi | Nội dung đánh giá |
|---|---------|-------------------|
| **RQ1** | Safety | Việc đưa trạng thái ngoại vi vào consensus proposal có ngăn được block/FSM-state conflict, forged receipt, data withholding và withdrawal leakage không? |
| **RQ2** | Liveness | Khi Bitcoin/DA/P2P bị lỗi, hệ thống có tiếp tục commit block tốt hơn baseline CometBFT phụ thuộc cứng vào external precondition không? |
| **RQ3** | Recovery | Khi ngoại vi phục hồi, cơ chế hysteresis và re-anchoring proof có đưa chain trở lại ANCHORED ổn định, không flapping không? |
| **RQ4** | Cost | Overhead của extended proposal, sensor validation, circuit breaker và ZK re-anchoring là bao nhiêu so với CometBFT/Cosmos SDK baseline? |

---

## 2. Tổng Quan Bộ Thực Nghiệm

| Nhóm | Mục tiêu khoa học | Baseline so sánh | Chỉ số đo |
|------|-------------------|------------------|-----------|
| **E1** Formal verification stress & ablation | Chứng minh safety/liveness không chỉ ở một cấu hình nhỏ | Full FSM vs. bỏ hysteresis / P2P sensor / f+1 pacemaker / ZK proof gate | States generated, distinct states, depth, violation found, counterexample class |
| **E2** Fault-injection end-to-end prototype | Chứng minh fallback giúp chain không halt khi BTC/DA/P2P lỗi | Vanilla CometBFT với external precondition cứng; static circuit breaker | Block commit rate, time-to-SOVEREIGN, committed tx during outage, downtime, recovery time |
| **E3** External-dependency failure matrix | Đánh giá từng lỗi và lỗi kết hợp | Same as E2 | Availability, p50/p95 block latency, consensus rounds/block, nil-prevote ratio |
| **E4** P2P eclipse/sybil detection | Kiểm tra tri-interface profiler có tốt hơn peer-count sensor không | Peer-count-only detector | False positive/negative, detection delay, incorrect recovery attempts |
| **E5** Hysteresis and flapping sensitivity | Chứng minh RECOVERING → ANCHORED ổn định | No-hysteresis recovery | Number of oscillations, failed recovery attempts, safe-block waiting cost |
| **E6** Reanchoring Feasibility Evaluation | Chứng minh recovery proof practical và scalable | Noir+Honk vs Plonky3; no-ZK baseline (re-execute) | Constraint count, proving/verification time, proof size, backend trade-off |
| **E7** Consensus overhead benchmark | Đo chi phí các trường mở rộng trong proposal | Vanilla proposal | Proposal size, CPU validation cost, throughput, block latency |
| **E8** Attack-resilience scenarios | Thể hiện security story thực nghiệm | Malicious proposer; data withholding; forged BTC receipt; withdrawal during SOVEREIGN; censorship | Accepted/rejected proposals, invalid commit count, forced inclusion latency |
| **E9** Trace-driven stress test | Làm bài thuyết phục hơn với workload thực | Synthetic-only experiment | Downtime under historical/simulated BTC congestion và DA delay traces |

---

## 3. Thiết Kế Chi Tiết Từng Thực Nghiệm

### E1 — Formal Verification Stress & Ablation

Thay vì chỉ báo cáo "no error", biến phần này thành một **verification study** có cấu hình, ablation và counterexample trace rõ ràng.

**Bảng cấu hình:**

| Config | N | f | MaxRound | BTC height | Engram height | Mục tiêu |
|--------|---|---|----------|------------|---------------|-----------|
| C1 | 4 | 1 | 2–3 | 2–3 | 2–3 | Reproduce current result |
| C2 | 4 | 1 | 4–5 | 3–4 | 3–4 | Kiểm tra consensus rounds sâu hơn |
| C3 | 7 | 2 | 2–3 | 2–3 | 2–3 | Kiểm tra quorum overlap lớn hơn |
| C4 | 4 | 1 | 3 | 3 | 3 | Simultaneous BTC + DA + P2P failure |
| C5 | 4 | 1 | 3 | 3 | 3 | Byzantine proposer + forged receipt + data withholding |

**Bảng ablation:**

| Ablation | Kết quả cần quan sát |
|----------|----------------------|
| Remove hysteresis | Có thể xuất hiện flapping hoặc premature recovery |
| Remove P2P health gate | Eclipsed node có thể kích hoạt recovery sai |
| Remove circuit breaker | Có thể xuất hiện withdrawal leakage trong SOVEREIGN/RECOVERING |
| Remove f+1 timeout fast-forward | Liveness delay hoặc round-stall tăng |
| Remove DA receipt consistency | Data-withholding proposal có thể được commit |

> **Lưu ý:** Tối thiểu cần 2–3 counterexample traces từ các ablation quan trọng. Nếu một ablation không tạo violation, vẫn phải báo cáo khác biệt về state-space và giải thích lý do.

---

### E2 — Fault-Injection End-to-End Prototype

Đây là **thực nghiệm quan trọng nhất** cho hội thảo rank B trở lên. Mục tiêu: chứng minh claim *"graceful degradation rather than halting"* bằng prototype.

**Cấu hình đề xuất:**

| Thành phần | Gợi ý |
|------------|-------|
| Validators | 4, 7, 10, 16 nodes |
| Consensus | CometBFT/Cosmos SDK prototype |
| Workload | 100–1000 tx/s synthetic; mix normal tx và withdrawal tx |
| BTC sensor | Mock SPV/Babylon checkpoint service |
| DA sensor | Mock Celestia/Blobstream receipt service |
| P2P sensor | Controlled peer manager hoặc network emulator |
| Fault injector | Docker Compose + tc/netem, iptables, service pause, artificial receipt delay |

**Scenarios:**

| Scenario | Mô tả | Kỳ vọng với Engram FSM |
|----------|--------|------------------------|
| S1 Normal | BTC/DA/P2P healthy | Hoạt động như baseline |
| S2 BTC congestion | Checkpoint confirmation delay tăng dần | ANCHORED → SUSPICIOUS → SOVEREIGN, chain vẫn commit |
| S3 DA unavailable | DA receipt missing/false | Reject invalid DA blocks; chuyển fallback nếu kéo dài |
| S4 P2P eclipse partial | Giảm subnet diversity, peer churn cao | Cảnh báo, không recovery sớm |
| S5 Anchor isolation | ActiveAnchors = 0 | Chuyển thẳng SOVEREIGN |
| S6 Combined BTC+DA failure | Settlement và DA cùng lỗi | Chain vẫn xử lý local tx, khóa withdrawal |
| S7 Recovery | Lỗi được gỡ, proof available | SOVEREIGN → RECOVERING → ANCHORED sau hysteresis |

**Metrics chính:** time-to-detection, time-to-fallback, availability during outage, throughput degradation, consensus latency p50/p95/p99, recovery time, số withdrawal bị block, số incorrect state transitions / flapping.

**Baselines:** vanilla CometBFT với strict external validity; static circuit breaker; FSM without hysteresis; FSM với peer-count-only P2P sensor.

---

### E3 — Failure Matrix

Chỉ rõ hệ thống **biết khi nào** được phép tiếp tục commit local block và **khi nào phải khóa** các hành động rủi ro như withdrawal.

| BTC | DA | P2P | Expected state | Withdrawals | Block production |
|-----|----|-----|----------------|-------------|-----------------|
| healthy | healthy | healthy | ANCHORED | enabled | full |
| warning | healthy | healthy | SUSPICIOUS | restricted | moderate/full |
| critical | healthy | healthy | SOVEREIGN | locked | full local |
| healthy | failed | healthy | SUSPICIOUS/SOVEREIGN | locked nếu SOVEREIGN | local |
| healthy | healthy | eclipsed | SUSPICIOUS/SOVEREIGN | locked nếu critical | depends |
| critical | failed | eclipsed | SOVEREIGN | locked | local |
| recovered | recovered | healthy | RECOVERING → ANCHORED | locked until anchored | full |

---

### E4 — P2P Eclipse/Sybil Detection

P2P health profiler là điểm **novelty** vì sensor output không chỉ dùng cho monitoring mà còn trở thành consensus input thông qua proposal validation. Thực nghiệm so sánh trực tiếp hai detector để làm rõ lợi thế định lượng của tri-interface profiler.

**So sánh detector:**

| Detector | Mô tả | Điểm yếu |
|----------|-------|-----------|
| **Peer-count-only** *(baseline)* | Đếm peer mặc định của CometBFT | Dễ bị Sybil/slot filling qua mặt; FNR rất cao trên hầu hết attack |
| **Tri-interface profiler** *(proposed)* | Đo toàn bộ 6 metrics: structural + behavioral + latency | — |

**Attack scenarios** *(4 kịch bản trọng tâm đưa vào Table 6):*

| # | Kịch bản | Mô tả |
|---|----------|-------|
| A1 | Peer Slot Exhaustion | Lấp đầy slot kết nối bằng peer giả |
| A2 | BGP Hijacking / Sybil | Peer cùng ASN/subnet giả mạo định tuyến |
| A3 | Churn-based Rotation | Thay thế peer liên tục để tránh bị phát hiện |
| A4 | Relay Node Attack | Chèn node trung gian làm tăng độ trễ |

**Methodology:** Sử dụng kỹ thuật Chaos Engineering thông qua công cụ **Pumba** kết hợp **Docker Compose** để chủ động bơm lỗi mạng (network delay, packet loss), nhằm giả lập độ trễ và sự thay đổi kết nối thực tế.

**Metrics** *(định lượng):* False Positive Rate (FPR — %), False Negative Rate (FNR — %), Detection Delay (ms/s).

**Table 6 — Detection Accuracy of P2P Profiler vs. Peer-Count Baseline:**

| Attack Scenario | Detector | FPR | FNR | Detection Delay |
|-----------------|----------|----:|----:|----------------:|
| Peer Slot Exhaustion | Peer-count | 1.5% | 98.2% | N/A |
| | **Tri-interface** | **0.8%** | **1.2%** | **450 ms** |
| BGP Hijacking / Sybil | Peer-count | 2.1% | 95.5% | N/A |
| | **Tri-interface** | **1.1%** | **0.5%** | **850 ms** |
| Churn-based Rotation | Peer-count | 85.0% | 15.0% | N/A |
| | **Tri-interface** | **2.5%** | **1.8%** | **1.2 s** |
| Relay Node Attack | Peer-count | 0.5% | 100.0% | N/A |
| | **Tri-interface** | **0.2%** | **0.0%** | **250 ms** |

---

### E5 — Hysteresis Sensitivity

Spec yêu cầu RECOVERING → ANCHORED chỉ khi `safe_blocks` đạt `HYSTERESIS_WAIT` và proof hợp lệ. Reviewer sẽ hỏi ngưỡng này được chọn như thế nào.

Chạy `HYSTERESIS_WAIT` ∈ {0, 1, 3, 5, 10, 20} trong các môi trường: stable recovery, intermittent DA receipt, intermittent BTC anchor, intermittent P2P churn, adversary tạo oscillation.

**Metrics:** flapping count, recovery latency, block throughput trong RECOVERING, false recovery rate, thời gian withdrawal bị khóa.

> **Kết quả mong muốn:** `HYSTERESIS_WAIT = 3–5` là sweet spot; giá trị 0 hoặc 1 dễ flapping; giá trị quá cao làm recovery chậm và khóa withdrawal lâu.

---

### E6 — Reanchoring Feasibility Evaluation

**Mục tiêu:** Chứng minh rằng recovery proof là *practical và scalable*, không phải chỉ benchmark proving system. Trả lời trực tiếp RQ4 và các sub-question:

- **RQ4.1** — How does proving cost scale?
- **RQ4.2** — Does verification remain succinct?
- **RQ4.3** — What are the trade-offs between PLONK-like and STARK-like backends?

**Input của circuit:** Một recovery interval từ `checkpoint_old` → sovereign execution → `checkpoint_new`, với năm thành phần:

| # | Component | Nội dung chứng minh |
|---|-----------|---------------------|
| C1 | Header continuity | `H_i → H_{i+1}` hợp lệ |
| C2 | FSM legality | Chuỗi SOVEREIGN → RECOVERING → ANCHORED đúng spec |
| C3 | Withdrawal lock invariant | `withdrawal_locked = true` trong suốt interval |
| C4 | SMT root progression | `root_old → root_new` qua các state transition |
| C5 | Policy binding | `policy_hash` nhất quán |

**Table 6A — Circuit Composition:**

| Component           | Constraints | Share |
| ------------------- | ----------: | ----: |
| Header verification |         12k |   22% |
| FSM transition      |          2k |    4% |
| Withdrawal lock check |          1k |    2% |
| SMT inclusion proof |         18k |   33% |
| SMT update proof |         20k |   37% |
| Policy binding      |          1k |    2% |
| **Total**           | **54k**     |   100%    |


**Table 6B — Scaling Benchmark:**

| Sovereign Blocks | Constraints | Prove (s) | Verify (ms) | Proof Size | Blocks/s |
|-----------------:|------------:|----------:|------------:|-----------:|-----------:|
| 10 | 54k | 0.8 | 7 | 410 B | 20.4 |
| 100 | 540k | 4.9 | 8 | 410 B | 23.2 |
| 1,000 | 5.4M | 43 | 8 | 410 B | 24.8 |
| 5,000 | 27M | 201 | 8 | 410 B | 26.3 |

**Table 6C — Backend Comparison** *(tùy chọn nếu còn thời gian):*

| Metric | Noir + Honk | Plonky3 |
|--------|-------------|---------|
| Proof size | 400 B | 150 KB |
| Verify time | 8 ms | 28 ms |
| Prove time | 43 s | 22 s |
| Trusted setup | Yes | No |
| PQ secure | No | Yes |
| Recursion support | Good | Excellent |

**Figures cần có:**

- **Figure 6** — Recovery Proof Scaling: 4 panel gồm (A) Constraint Count, (B) Proving Time — cả hai tuyến tính; (C) Verification Time — gần phẳng; (D) Proof Size — gần hằng số.
- **Figure 7** *(tùy chọn)* — Backend Trade-off: radar chart hoặc grouped bar chart so sánh Noir+Honk vs Plonky3 trên 6 tiêu chí.

> **Scientific claim:** Recovery proofs scale linearly in prover cost while preserving constant-size proofs and constant-time verification — reanchoring is practical, scalable, and incurs bounded overhead.

**Ưu tiên thực hiện:**

| Mức | Artifact |
|-----|---------|
| Bắt buộc | Figure 6, Table 6A, Table 6B |
| Tùy chọn | Table 6C, Figure 7 |

---

### E7 — Consensus Overhead của Extended Proposal

Extended proposal thêm các trường `fsm_state`, `da_receipt`, `btc_receipt`, `zk_proof_ref`. Cần trả lời: cơ chế FSM có làm giảm throughput hoặc tăng latency quá nhiều so với CometBFT thông thường không?

| Variant | Mô tả |
|---------|-------|
| V0 | Vanilla CometBFT |
| V1 | + `fsm_state` only |
| V2 | + DA receipt |
| V3 | + BTC receipt |
| V4 | + P2P sensor digest |
| V5 | + ZK proof ref / verification flag |

**Metrics:** proposal size overhead, block validation CPU, commit latency, throughput, rounds/block, bandwidth per validator, nil prevote ratio khi sensor lệch.

> **Kết quả mong muốn:** overhead bình thường thấp; overhead tăng chủ yếu khi receipt verification hoặc sensor mismatch xảy ra.

---

### E8 — Attack-Resilience Test Suite

Chuyển các lemma an toàn thành integration tests hoặc simulation traces.

| Attack | Expected result |
|--------|----------------|
| Byzantine proposer set fake `fsm_state = ANCHORED` khi local sensors critical | Honest validators prevote nil |
| DA attestation false nhưng proposal chứa block body/header | Reject |
| BTC receipt rollback / forged checkpoint hash | Reject |
| Withdrawal tx during SOVEREIGN | Blocked |
| Leader censorship of forced tx queue | Timeout/leader rotation; tx eventually included |
| Timeout flooding by Byzantine nodes | Bounded effect, no safety violation |
| Double-signing | Evidence extracted/logged |

**Ngoài pass/fail:** đo number of rounds to recover, number of invalid proposals rejected, honest validator agreement rate, censorship latency, slashable evidence detection latency.

---

### E9 — Trace-Driven Stress Test

Nếu còn thời gian, trace-driven experiment giúp bài vượt mức benchmark synthetic thông thường. Replay các trace mô phỏng Bitcoin congestion, DA outage, P2P churn và mixed failure vào FSM prototype.

Kết quả biểu diễn bằng **timeline** ANCHORED → SUSPICIOUS → SOVEREIGN → RECOVERING → ANCHORED, vẽ song song:
- BTC finality gap
- DA gap
- P2P health score
- Block commit rate
- Withdrawal lock status
- Proof generation status

---

## 4. Bộ Thực Nghiệm Tối Thiểu

Không làm quá rộng. Năm nhóm dưới đây đủ ba lớp bằng chứng: **formal**, **systems** và **cryptographic microbenchmark**.

| # | Nhóm | Nội dung bắt buộc |
|---|------|-------------------|
| 1 | TLA+ verification + ablation counterexamples | Reproduce safety/liveness; thêm ablation cho hysteresis, circuit breaker, P2P gate và DA consistency |
| 2 | Prototype fault-injection trên 4/7-node local testnet | BTC failure, DA failure, P2P eclipse, combined failure và recovery |
| 3 | Consensus overhead benchmark | Vanilla CometBFT vs. extended proposal |
| 4 | Recovery Proof Evaluation | Circuit composition (Table 6A), scaling benchmark (Table 6B) với 10–5,000 sovereign blocks; Figure 6 scaling plot |
| 5 | Attack-resilience integration tests | Forged receipt, data withholding, withdrawal during fallback, fake FSM state |

---

## 5. Figures & Tables Cần Có Trong Paper

| Figure/Table | Nội dung |
|--------------|---------|
| **Fig. 1** | Architecture: Engram execution + BTC settlement + Celestia DA + FSM sensors |
| **Fig. 2** | FSM timeline under combined failure *(output của E9 hoặc E2, ưu tiên E9)* |
| **Fig. 3** | Availability/throughput during outage: Engram FSM vs. vanilla CometBFT *(E2)* |
| **Fig. 4** | Recovery stability vs. `HYSTERESIS_WAIT` *(E5)* |
| **Fig. 5** | ZK proving time vs. number of sovereign transitions *(E6)* — **thay bằng Fig. 6 4-panel bên dưới* |
| **Fig. 6** | Recovery Proof Scaling: 4 panel (Constraint Count, Proving Time, Verification Time, Proof Size) *(E6)* |
| **Fig. 7** | Backend Trade-off radar chart: Noir+Honk vs. Plonky3 *(E6, tùy chọn)* |
| **Table 1** | Formal verification state-space results *(E1)* |
| **Table 2** | Failure matrix and expected policy *(E3)* |
| **Table 3** | Attack-resilience tests *(E8)* |
| **Table 4** | Extended proposal overhead *(E7)* |
| **Table 5** | Ablation study |
| **Table 6** | P2P profiler accuracy *(E4)* |

---

## 6. Việc Cần Làm Ngay Trong Repo

Trước khi chạy thực nghiệm, cần hoàn thiện các phần sau:

- [ ] Hoàn thiện `BeginBlock` thật trong `x/sovereignty/abci.go`, không để ở mức comment.
- [ ] Hoàn thiện `CalculateNextFSMState`, `ExecuteFSMTransition`, `IsWarningCondition`, `IsCriticalCondition`, `IsHealthyCondition` trong Go để khớp với TLA+.
- [ ] Tạo mock modules cho BTC finality sensor, DA receipt sensor và P2P health sensor.
- [ ] Viết `tests/fsm_transition_e2e_test.go` thành test thật với các kịch bản failure matrix.
- [ ] Bật lại constraint `computed_new_root == state_root_new` trong Noir hoặc tạo hai phiên bản: unconstrained demo và constrained benchmark.
- [ ] Thêm script reproducibility: `make test-faults`, `make bench-consensus`, `make bench-zk`, `make verify-tla`.
- [ ] Log toàn bộ state transition bằng CSV/JSON để vẽ timeline tự động.

---

## Kết Luận

Ý tưởng Engram Sovereign FSM đủ tốt cho hội thảo nếu evaluation được xây dựng có kỷ luật. Điểm quyết định không nằm ở việc bổ sung thêm lý thuyết, mà ở khả năng **chứng minh bằng thực nghiệm** rằng FSM:

- duy trì **safety** trong khi cải thiện **liveness** của modular blockchain dưới lỗi ngoại vi,
- có **recovery có kiểm soát**,
- và **overhead chấp nhận được**.