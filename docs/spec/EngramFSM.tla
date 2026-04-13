--------------------------- MODULE EngramFSM ---------------------------
EXTENDS Integers

CONSTANTS 
    T_SUSPICIOUS,                   \* Warning delay threshold (Gray Failure)
    T_SOVEREIGN,                    \* Sovereign partition threshold (Hard Failure)
    MAX_BTC_GAP,                    \* Maximum BTC gap limit to bound state space
    T_DA,                           \* Block gap since the last DA publication verification
    MAX_DA_GAP,                     \* Maximum DA gap limit to bound state space
    HYSTERESIS_WAIT,                \* Consecutive safe blocks required for successful recovery
    MIN_PEERS                       \* Minimum peers required to prevent isolation


ASSUME 
    /\ T_SUSPICIOUS \in Nat /\ T_SOVEREIGN \in Nat /\ MAX_BTC_GAP \in Nat 
    /\ T_DA \in Nat /\ MAX_DA_GAP \in Nat
    /\ HYSTERESIS_WAIT \in Nat  /\ MIN_PEERS \in Nat
    /\ T_SUSPICIOUS < T_SOVEREIGN /\ T_SOVEREIGN < MAX_BTC_GAP
    /\ T_DA < MAX_DA_GAP


VARIABLES 
    state,                          \* Current FSM state
    btc_gap,                        \* Bitcoin layer verification gap
    da_gap,                         \* Data Availability layer verification gap
    is_das_failed,                  \* DAS sampling failure state
    peer_count,                     \* Current number of P2P peers
    safe_blocks,                    \* Hysteresis counter to prevent flapping
    reanchoring_proof_valid         \* ZK proof verified onchain/off-chain

vars == <<state, btc_gap, da_gap, peer_count, safe_blocks, reanchoring_proof_valid, is_das_failed>>
env_vars == <<btc_gap, da_gap, peer_count, reanchoring_proof_valid, is_das_failed>>


\* -----------------------------------------------------------------------------
\* MACROS & DERIVED VARIABLES
\* -----------------------------------------------------------------------------
withdraw_locked == state \in {"SOVEREIGN", "RECOVERING"}


\* Critical failure conditions (Triggers circuit breaker)
IsCriticalCondition == btc_gap >= T_SOVEREIGN 

\* Warning conditions for unstable network or risks
IsWarningCondition == 
    \/ (btc_gap >= T_SUSPICIOUS /\ btc_gap < T_SOVEREIGN)
    \/ da_gap >= T_DA
    \/ is_das_failed
    \/ peer_count < MIN_PEERS

\* Completely healthy network conditions
IsHealthyCondition == 
    /\ btc_gap < T_SUSPICIOUS
    /\ da_gap < T_DA
    /\ ~is_das_failed
    /\ peer_count >= MIN_PEERS


\* -----------------------------------------------------------------------------
\* TYPE INVARIANT & SANITY CHECK
\* -----------------------------------------------------------------------------
TypeInvariant == 
    /\ state \in {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}
    /\ btc_gap \in 0..MAX_BTC_GAP
    /\ da_gap \in 0..MAX_DA_GAP
    /\ is_das_failed \in BOOLEAN
    /\ peer_count \in 0..(MIN_PEERS * 2)
    /\ safe_blocks \in 0..HYSTERESIS_WAIT
    /\ reanchoring_proof_valid \in BOOLEAN

\* Sanity Check: Deliberately detecting errors to ensure the system does NOT freeze.
SanityCheck == state /= "RECOVERING"


\* -----------------------------------------------------------------------------
\* STATE MACHINE LOGIC
\* -----------------------------------------------------------------------------
Init == 
    /\ state = "ANCHORED"
    /\ btc_gap = 0
    /\ da_gap = 0
    /\ is_das_failed = FALSE
    /\ peer_count = MIN_PEERS + 1
    /\ safe_blocks = 0
    /\ reanchoring_proof_valid = FALSE

\* Non-deterministic environment variable updates (Simulates real network)
UpdateSensors ==
    /\ btc_gap' \in 0..MAX_BTC_GAP
    /\ da_gap' \in 0..MAX_DA_GAP
    /\ is_das_failed' \in BOOLEAN
    /\ reanchoring_proof_valid' \in BOOLEAN
    /\ peer_count' \in 0..MIN_PEERS * 2
    /\ UNCHANGED <<state, safe_blocks>>

\* FSM state transitions based on sensor data
AnchoredToSuspicious == 
    /\ state = "ANCHORED"
    /\ IsWarningCondition
    /\ ~IsCriticalCondition
    /\ state' = "SUSPICIOUS"
    /\ UNCHANGED <<safe_blocks>>

SuspiciousToSovereign == 
    /\ state = "SUSPICIOUS"
    /\ IsCriticalCondition
    /\ state' = "SOVEREIGN"
    /\ UNCHANGED <<safe_blocks>>

AnchoredToSovereign == 
    /\ state = "ANCHORED"
    /\ IsCriticalCondition
    /\ state' = "SOVEREIGN"
    /\ UNCHANGED <<safe_blocks>>

SuspiciousToAnchored == 
    /\ state = "SUSPICIOUS"
    /\ IsHealthyCondition
    /\ state' = "ANCHORED"
    /\ UNCHANGED <<safe_blocks>>

SovereignToRecovering == 
    /\ state = "SOVEREIGN"
    /\ IsHealthyCondition
    /\ state' = "RECOVERING"
    /\ safe_blocks' = 0

RecoveringProgress == 
    /\ state = "RECOVERING"
    /\ IsHealthyCondition
    /\ safe_blocks < HYSTERESIS_WAIT
    /\ safe_blocks' = safe_blocks + 1
    /\ UNCHANGED <<state>>

RecoveringToAnchored == 
    /\ state = "RECOVERING"
    /\ IsHealthyCondition
    /\ safe_blocks = HYSTERESIS_WAIT
    /\ reanchoring_proof_valid = TRUE
    /\ state' = "ANCHORED"
    /\ safe_blocks' = 0

RecoveringToSuspicious == 
    /\ state = "RECOVERING"
    /\ IsWarningCondition
    /\ ~IsCriticalCondition
    /\ state' = "SUSPICIOUS"
    /\ safe_blocks' = 0

RecoveringToSovereign == 
    /\ state = "RECOVERING"
    /\ IsCriticalCondition
    /\ state' = "SOVEREIGN"
    /\ safe_blocks' = 0

FSM_Transition == 
    \/ AnchoredToSuspicious \/ SuspiciousToSovereign \/ AnchoredToSovereign 
    \/ SuspiciousToAnchored \/ SovereignToRecovering \/ RecoveringProgress 
    \/ RecoveringToAnchored \/ RecoveringToSuspicious \/ RecoveringToSovereign

Next == UpdateSensors \/ (FSM_Transition /\ UNCHANGED env_vars)


Fairness == 
    /\ WF_vars(AnchoredToSuspicious /\ UNCHANGED env_vars)
    /\ WF_vars(SuspiciousToSovereign /\ UNCHANGED env_vars)
    /\ WF_vars(AnchoredToSovereign /\ UNCHANGED env_vars)
    /\ WF_vars(SuspiciousToAnchored /\ UNCHANGED env_vars)
    /\ WF_vars(SovereignToRecovering /\ UNCHANGED env_vars)
    /\ WF_vars(RecoveringProgress /\ UNCHANGED env_vars)
    /\ WF_vars(RecoveringToAnchored /\ UNCHANGED env_vars)
    /\ WF_vars(RecoveringToSuspicious /\ UNCHANGED env_vars)
    /\ WF_vars(RecoveringToSovereign /\ UNCHANGED env_vars)

Spec == Init /\ [][Next]_vars /\ Fairness


\* -----------------------------------------------------------------------------
\* SAFETY PROPERTIES
\* -----------------------------------------------------------------------------

\* Safety 1: All withdrawals must be locked when in Sovereign or Recovering
CircuitBreakerSafety == withdraw_locked <=> (state \in {"SOVEREIGN", "RECOVERING"})

\* Safety 2: Ensure the system never gets stuck (Deadlock-Free).
NoDeadlockSafety == ENABLED Next

\* Safety 3: The sequential nature of Hysteresis (No skipping steps allowed)
HysteresisSafety == 
    [][ (state = "RECOVERING" /\ state' = "ANCHORED") => (safe_blocks = HYSTERESIS_WAIT /\ reanchoring_proof_valid) ]_vars


\* -----------------------------------------------------------------------------
\* LIVENESS PROPERTIES
\* -----------------------------------------------------------------------------

\* Liveness 1: If critical thresholds are reached, system MUST transition to SOVEREIGN
CircuitBreakerLiveness == 
    IsCriticalCondition ~> (state = "SOVEREIGN" \/ ~IsCriticalCondition)

\* Liveness 2: If in SOVEREIGN and network recovers, system MUST attempt recovery
RecoveryAttemptLiveness == 
    (state = "SOVEREIGN" /\ IsHealthyCondition) ~> (state = "RECOVERING" \/ ~IsHealthyCondition)

\* Liveness 3: Ensure the recovery process will be completed.
CompleteRecoveryLiveness == 
    (state = "RECOVERING" /\ reanchoring_proof_valid /\ IsHealthyCondition) 
    ~> (state = "ANCHORED" \/ ~IsHealthyCondition \/ ~reanchoring_proof_valid)
=============================================================================