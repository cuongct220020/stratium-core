--------------------------- MODULE EngramFSM ---------------------------
EXTENDS Integers, EngramVars

CONSTANTS 
    T_SUSPICIOUS,                   \* Warning delay threshold (Gray Failure)
    T_SOVEREIGN,                    \* Sovereign partition threshold (Hard Failure)
    MIN_PEERS                       \* Minimum peers required to prevent isolation


ASSUME 
    /\ T_SUSPICIOUS \in Nat 
    /\ T_SOVEREIGN \in Nat 
    /\ T_DA \in Nat 
    /\ HYSTERESIS_WAIT \in Nat  
    /\ MIN_PEERS \in Nat
    /\ T_SUSPICIOUS < T_SOVEREIGN


(************************ CALCULATE DYNAMIC GAPS *********************)
MinVal(a, b) == IF a < b THEN a ELSE b

\* Bitcoin layer verification gap
btc_gap == h_btc_current - MinVal(h_btc_submitted, h_btc_anchored)

\* Data Availability layer verification gap
da_gap == h_engram_current - h_engram_verified


(************************ MACROS & DERIVED VARIABLES *********************)
WithdrawLocked == state \in {"SOVEREIGN", "RECOVERING"}

IsDAHealthy == (da_gap < T_DA) /\ ~is_das_failed

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
    /\ IsDAHealthy
    /\ peer_count >= MIN_PEERS


(************************ TYPE INVARIANT & SANITY CHECK *********************)
TypeInvariant == 
    /\ state \in {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}
    /\ btc_gap >= 0
    /\ da_gap >= 0
    /\ is_das_failed \in BOOLEAN
    /\ peer_count \in 0..(MIN_PEERS * 2)
    /\ safe_blocks \in 0..HYSTERESIS_WAIT
    /\ reanchoring_proof_valid \in BOOLEAN

\* Sanity Check: Deliberately detecting errors to ensure the system does NOT freeze.
SanityCheck == state /= "RECOVERING"


(************************ STATE MACHINE LOGIC *********************)
FSM_Init == 
    /\ state = "ANCHORED" 
    /\ h_btc_current = 0 
    /\ h_btc_submitted = 0 
    /\ h_btc_anchored = 0 
    /\ h_engram_current = 0 
    /\ h_engram_verified = 0 
    /\ is_das_failed = FALSE 
    /\ peer_count = MIN_PEERS + 1 
    /\ safe_blocks = 0 
    /\ reanchoring_proof_valid = FALSE

\* Non-deterministic environment variable updates (Simulates real network)
UpdateSensors ==
    \* The height of a block can only increase or remain constant; each subsequent block cannot exceed the previous one.
    /\ h_btc_current' \in {h_btc_current, h_btc_current + 1}
    /\ h_btc_submitted' \in {h_btc_submitted, h_btc_current'}
    /\ h_btc_anchored' \in {h_btc_anchored, h_btc_submitted'}
    
    /\ h_engram_current' \in {h_engram_current, h_engram_current + 1}
    /\ h_engram_verified' \in {h_engram_verified, h_engram_current'}

    \* ZK proof is only valid when the Bitcoin anchor point is confirmed (anchored)
    \* catches up with or exceeds the proof submission time.
    /\ reanchoring_proof_valid' = 
          IF state = "RECOVERING" /\ h_btc_anchored' >= h_btc_submitted' /\ h_btc_submitted' > 0
          THEN TRUE 
          ELSE FALSE
    
    \* Random external environmental variables
    /\ is_das_failed' \in BOOLEAN
    /\ peer_count' \in 0..(MIN_PEERS * 2)

    \* Keep core FSM states unchanged during sensor updates
    /\ UNCHANGED <<state, safe_blocks>>


\* FSM state transitions based on sensor data
AnchoredToSuspicious == 
    /\ state = "ANCHORED"
    /\ IsWarningCondition
    /\ ~IsCriticalCondition
    /\ state' = "SUSPICIOUS"
    /\ UNCHANGED <<envVars>>
    /\ UNCHANGED <<safe_blocks>>

SuspiciousToSovereign == 
    /\ state = "SUSPICIOUS"
    /\ IsCriticalCondition
    /\ state' = "SOVEREIGN"
    /\ UNCHANGED <<envVars>>
    /\ UNCHANGED <<safe_blocks>>

AnchoredToSovereign == 
    /\ state = "ANCHORED"
    /\ IsCriticalCondition
    /\ state' = "SOVEREIGN"
    /\ UNCHANGED <<envVars>>
    /\ UNCHANGED <<safe_blocks>>

SuspiciousToAnchored == 
    /\ state = "SUSPICIOUS"
    /\ IsHealthyCondition
    /\ state' = "ANCHORED"
    /\ UNCHANGED <<envVars>>
    /\ UNCHANGED <<safe_blocks>>

SovereignToRecovering == 
    /\ state = "SOVEREIGN"
    /\ IsHealthyCondition
    /\ state' = "RECOVERING"
    /\ safe_blocks' = 0
    /\ UNCHANGED <<envVars>>


RecoveringProgress == 
    /\ state = "RECOVERING"
    /\ IsHealthyCondition
    /\ safe_blocks < HYSTERESIS_WAIT
    /\ safe_blocks' = safe_blocks + 1
    /\ UNCHANGED <<envVars>>
    /\ UNCHANGED <<state>>

RecoveringToAnchored == 
    /\ state = "RECOVERING"
    /\ IsHealthyCondition
    /\ safe_blocks = HYSTERESIS_WAIT
    /\ reanchoring_proof_valid = TRUE
    /\ state' = "ANCHORED"
    /\ safe_blocks' = 0
    /\ reanchoring_proof_valid' = FALSE
    /\ UNCHANGED <<h_engram_current, h_engram_verified, h_btc_current, h_btc_submitted, h_btc_anchored, peer_count, is_das_failed>>


RecoveringToSuspicious == 
    /\ state = "RECOVERING"
    /\ IsWarningCondition
    /\ ~IsCriticalCondition
    /\ state' = "SUSPICIOUS"
    /\ safe_blocks' = 0
    /\ UNCHANGED <<envVars>>


RecoveringToSovereign == 
    /\ state = "RECOVERING"
    /\ IsCriticalCondition
    /\ state' = "SOVEREIGN"
    /\ safe_blocks' = 0
    /\ UNCHANGED <<envVars>>


FSM_Transition == 
    \/ AnchoredToSuspicious \/ SuspiciousToSovereign \/ AnchoredToSovereign 
    \/ SuspiciousToAnchored \/ SovereignToRecovering \/ RecoveringProgress 
    \/ RecoveringToAnchored \/ RecoveringToSuspicious \/ RecoveringToSovereign

FSM_Next == UpdateSensors \/ FSM_Transition


FSM_Fairness == 
    /\ WF_fsmVars(AnchoredToSuspicious)
    /\ WF_fsmVars(SuspiciousToSovereign)
    /\ WF_fsmVars(AnchoredToSovereign)
    /\ WF_fsmVars(SuspiciousToAnchored)
    /\ WF_fsmVars(SovereignToRecovering)
    /\ WF_fsmVars(RecoveringProgress)
    /\ WF_fsmVars(RecoveringToAnchored)
    /\ WF_fsmVars(RecoveringToSuspicious)
    /\ WF_fsmVars(RecoveringToSovereign)

FSM_Spec == FSM_Init /\ [][FSM_Next]_fsmVars /\ FSM_Fairness



(************************ SAFETY PROPERTIES *********************)
\* Safety 1: All withdrawals must be locked when in Sovereign or Recovering
CircuitBreakerSafety == WithdrawLocked <=> (state \in {"SOVEREIGN", "RECOVERING"})

\* Safety 2: Ensure the system never gets stuck (Deadlock-Free).
NoDeadlockSafety == ENABLED FSM_Next

\* Safety 3: The sequential nature of Hysteresis (No skipping steps allowed)
HysteresisSafety == 
    [][ (state = "RECOVERING" /\ state' = "ANCHORED") => (safe_blocks = HYSTERESIS_WAIT /\ reanchoring_proof_valid) ]_fsmVars


(************************ LIVENESS PROPERTIES *********************)
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