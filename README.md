# Engram Sovereign FSM (in-progress)

## Prerequisites
- IDE: VSCode
- Extensions: `TLA+ (Temporal Logic of Actions)`, `Graphviz Interactive Preview`, `Noir Language Support`.

```bash
git clone <repo-url>
cd engram-sovereign-fsm

python3 -m venv .venv
source .venv/bin/activate 
pip install requirements.txt
```

## Scripts Directory
```
scripts/
├── common/                        # Dùng chung (Utility, Plotting, Logging)
│   ├── logger.py                  # Format log chuẩn cho tất cả thực nghiệm
│   └── plot_utils.py              # Thư viện vẽ biểu đồ chuẩn IEEE
├── e2_fault_injection_prototype/  # The Harness (Hạ tầng tiêm lỗi)
│   ├── controller.py              # Điều khiển vòng đời node (Start/Stop/Reset)
│   └── injector.py                # Gửi tín hiệu fault vào Keeper
├── e3_failure_matrix/             # The Test Suite (Ma trận lỗi)
│   ├── scenarios/                 # Nơi chứa file config kịch bản (YAML/JSON)
│   └── runner.py                  # Script đọc matrix & gọi e2 để chạy
├── e4_p2p_eclipse_attack/          # E4: Khả năng chống tấn công
│   ├── sybil_attacker.py          # Script giả lập Sybil attack
│   └── eclipse_monitor.py         # Theo dõi peer table (để verify detection)
├── e5_hysteresis_flapping/        # E5: Kiểm tra độ nhạy FSM
│   ├── flapping_gen.py            # Tạo nhiễu mạng dao động
│   └── stability_analyzer.py      # Phân tích xem có bị Flapping không
├── e6_zk_reanchoring_benchmark/   # E6: Microbenchmark ZK
│   ├── prover_bench.sh            # Script chạy nargo/prover
│   └── stats_collector.py         # Tổng hợp kết quả
├── e7_consensus_overhead/         # E7: Đo đạc Overhead
│   ├── proposal_analyzer.py       # Đo size Block Proposal
│   └── latency_tracker.py         # Đo consensus latency
├── e8_attack_resilience/          # E8: Resilience
│   └── attack_replay.py           # Replay các tấn công từ TLA+ counterexamples
└── e9_trace_driven/               # E9: Thực nghiệm vết
    └── traces/                    # Dữ liệu vết (BTC/Celestia)
        └── runner.py              # Replay engine
```