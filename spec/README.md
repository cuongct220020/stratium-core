# Formal Specification of Engram FSM

This directory contains the formal mathematical specification of the **Adaptive Consensus FSM (Finite State Machine)** for the Engram Protocol network. The model is written in **TLA+** to verify the correctness of the system design under network partition scenarios.

## 1. System Model Overview

The FSM governs the consensus mechanism of Engram based on three core states:
- **ANCHORED**: The network operates normally, securely anchored to Bitcoin via Babylon.
- **SUSPICIOUS**: The validation gap ($\Delta H$) exceeds the threshold $T_1$ (100 blocks). The protocol begins restricting high-risk transactions.
- **SOVEREIGN**: The validation gap exceeds the threshold $T_2$ (500 blocks). The network becomes isolated (Network Partition) and automatically activates the Local PoS mechanism to maintain Liveness, while also triggering the Circuit Breaker.

## 2. Verified Properties

This model uses the TLC Model Checker to prove two core mathematical theorems of the paper:

1. **Safety (`TypeOK`)**: Proves $Safety_{Anchored} \cap Safety_{Sovereign} \neq \emptyset$. The FSM never exists in two states simultaneously, completely eliminating the risk of Double-spending between modes.
2. **Liveness (`Liveness`)**: Proves `WF_vars(SovereignToAnchored)`. Regardless of how long the network is partitioned, the system always has a valid mathematical path to recover (Re-anchoring) to the `ANCHORED` state when external connectivity is restored.

## 3. How to Run Verification

To verify this model, you need to install the TLA+ Toolbox or use the TLC CLI.

### Using Command Line (CLI):
Run the following command in the project root directory:
```bash
# Compile and run the TLC Model Checker with the EngramFSM.cfg configuration file
java -jar tlacli.jar -config EngramFSM.cfg EngramFSM.tla
```
