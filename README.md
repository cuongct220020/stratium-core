# Stratium Core

## Directory Structure

```plaintext
cuongct090_04@MacBookAir stratium-core % tree
.
├── Dockerfile
├── LICENSE
├── Makefile
├── README.md
├── app
│   └── app.go
├── cmd
│   └── stratiumd
│       └── main.go
├── docker-compose.yml
├── go.mod
├── go.sum
├── requirements.txt
├── scripts
│   ├── the_big_merge
│   │   ├── benchmark_prover.go
│   │   ├── simulate_acceptance.py
│   │   └── zk_circuit_mock.go
│   └── the_great_disconnect
│       ├── measure_latency.py
│       └── trigger_disconnect.py
├── spec
│   ├── EngramFSM.cfg
│   ├── EngramFSM.tla
│   └── README.md
├── tests
│   └── fsm_transition_e2e_test.go
└── x
    ├── babylon_mock
    │   ├── api.go
    │   └── keeper.go
    └── fsm
        ├── abci.go
        ├── keeper
        │   ├── censor.go
        │   ├── circuit_breaker.go
        │   └── reanchor.go
        ├── module.go
        └── types
            ├── events.go
            ├── keys.go
            └── state.go
```

## File and Directory Roles

### Group 1: Project Management & Environment (Root level)
- **Dockerfile & docker-compose.yml**: Packages the `stratiumd` node and sets up a virtual network (4 Engram nodes, 1 Celestia mock node, Prometheus, Grafana) for network disconnection testing.
- **Makefile**: Contains shorthand commands (e.g., `make build`, `make test`, `make verify-fsm`) to help reviewers easily rerun all your experiments without remembering complex commands.
- **README.md**: Installation guide, overall architecture, and instructions to reproduce the paper's data.
- **go.mod & go.sum**: Manages Go dependencies (notably Cosmos SDK and CometBFT).
- **requirements.txt**: Lists Python libraries (e.g., `matplotlib`, `pandas`, `requests`) for plotting and API interaction.

### Group 2: Application Startup & Wiring (App & Cmd)
- **cmd/stratiumd/main.go**: Entry point for the Engram node software. Calls the `app` directory.
- **app/app.go**: Wires up the Cosmos SDK. Integrates your `x/fsm` and `x/babylon_mock` modules with default modules (e.g., `bank`, `auth`, `crisis`).

### Group 3: Experiment Scripts (Scripts - Stage 3 of the Paper)
#### The Great Disconnect
- **scripts/the_great_disconnect/trigger_disconnect.py**: Uses Docker API to disconnect Celestia/Babylon networks.
- **scripts/the_great_disconnect/measure_latency.py**: Pulls data from Prometheus and uses `matplotlib` to generate PDF charts (Latency, Throughput).

#### The Big Merge
- **scripts/the_big_merge/zk_circuit_mock.go**: Dummy ZK circuit representing block compression power.
- **scripts/the_big_merge/benchmark_prover.go**: Measures CPU time for generating "Super-proof" (O(NlogN)).
- **scripts/the_big_merge/simulate_acceptance.py**: Calculates parent chain proof acceptance time (O(1)).

### Group 4: Formal Specification (Spec - Stage 1 of the Paper)
- **spec/EngramFSM.tla & EngramFSM.cfg**: Contains TLA+ code proving mathematically that your FSM never violates Safety (Double-spending between two modes) and always achieves Liveness.
- **spec/README.md**: Explains TLA+ logic for reviewers before running the TLC Model Checker.

### Group 5: Core Scientific Contributions (Custom Modules)
#### Babylon Mock Node
- **x/babylon_mock/**: Mock node for the Payment layer. Continuously returns simulated height `H_anchor` for the FSM module to calculate latency.

#### FSM Module
- **x/fsm/**: The heart of the paper – Adaptive Consensus Finite State Machine.
  - **types/state.go, events.go, keys.go**: Defines 3 states (`ANCHORED`, `SUSPICIOUS`, `SOVEREIGN`) and triggering events.
  - **abci.go**: `BeginBlock` function, runs at the start of each block to collect sensor data and automatically transition FSM states.
  - **keeper/censor.go**: (Note: You may have mistakenly named this `censor.go` instead of `sensors.go`. This file is for Sensors to calculate ΔH and measure `T_DA`, not Censorship. Consider renaming it to `sensors.go`.)
  - **keeper/circuit_breaker.go**: Logic to lock withdrawal features when the network transitions to `SOVEREIGN`.
  - **keeper/reanchor.go**: Logic to resynchronize the parent chain when the connection is restored.

## The Big Merge

### Prototype Deployment Strategy (Avoid Full ZK-Rollup Implementation)
Writing a complete ZK circuit to prove state transitions for the entire Cosmos SDK (with thousands of transaction types) is the workload of a multi-million-dollar project, not a scientific paper.

#### Solution: Dummy Circuit Benchmarking
Use a "Dummy Circuit Benchmarking" method. Write a ZK circuit simulating the verification of a hash chain of 1,000 block headers. This represents the computational complexity of aggregation.

- **Theoretical Basis**: Based on Jens Groth's (2016) theory of ultra-small SNARK proofs (3 group elements) combined with Recursive SNARK composition to compress multiple proofs into a fully succinct SNARK.

### Core Metrics for Experiment 2

#### A. Proof Generation Time (Prover)
- **Theory**: Computational complexity for the Prover to generate ZK-Aggregation Proof is $O(N \cdot \log N)$, where $N$ is the number of transactions or blocks in the Sovereign phase.
- **Experiment**: In `scripts/the_big_merge/`, write code (using Go's `gnark` library or Rust's `snarkjs`) to create a proof for 1,000 Poseidon or SHA-256 hashes. Measure CPU/RAM usage in seconds/minutes to generate proof $\pi_{RA}$.

#### B. Parent Chain Acceptance Time (Verifier)
- **Theory**: Verifier complexity is $O(1)$ or $O(\log N)$, highly optimized for the DA layer. Proof size $\pi_{RA}$ (based on Groth16) is a tiny constant (~128 bytes).
- **Experiment (Simulated Time)**:
  - **On Celestia (DA Layer)**: The 128-byte proof occupies minimal space. Acceptance time equals Celestia's block creation time (~10-15 seconds).
  - **On Bitcoin (Payment Layer via Babylon)**: The compressed proof $\pi_{RA}$ can be attached to the payload of an `OP_RETURN` transaction. Acceptance time equals the thermodynamic finality of $k$ Bitcoin blocks (typically $k=6$, ~60 minutes).