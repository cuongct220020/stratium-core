--------------------------- MODULE EngramVars ---------------------------
(*
 * EngramVars — Shared Variable Declarations
 *
 * This module declares ALL variables used across the Engram specification.
 *)

CONSTANTS
    HYSTERESIS_WAIT,    \* Consecutive safe blocks required for successful recovery
    DA_THRESHOLD        \* Max allowed block gap since last DA publication verification


(* ======================== TENDERMINT CORE VARIABLES ======================== *)
\* Tendermint BFT state machine variables (per-process maps over Corr).
VARIABLES
    round,          \* Current consensus round of each correct process
    step,           \* Current step: "PROPOSE" | "PREVOTE" | "PRECOMMIT" | "DECIDED"
    decision,       \* Decided value (NilDecision if not yet decided)
    locked_value,   \* Value locked by the process in the last lock round
    locked_round,   \* Round in which locked_value was locked
    valid_value,    \* Most recent valid proposal seen
    valid_round     \* Round in which valid_value was observed

tendermintCoreVars == <<round, step, decision, 
                        locked_value, locked_round, valid_value, valid_round>>


(* ======================== TEMPORAL / CLOCK VARIABLES ======================= *)
\* Physical and logical time tracking for clock-synchrony proofs.
VARIABLES
    local_clock,    \* Each correct process's local clock reading
    real_time,      \* Global "wall clock" (advanced by AdvanceRealTime)
    local_rem_time  \* Remaining timeout countdown per process

temporalVars == <<local_clock, real_time, local_rem_time>>


(* ======================== BOOKKEEPING VARIABLES ============================ *)
\* Message buffers and audit log.
VARIABLES
    msgs_propose,               \* Proposal messages indexed by round
    msgs_prevote,               \* Prevote messages indexed by round
    msgs_precommit,             \* Precommit messages indexed by round
    msgs_timeout,               \* Timeout messages indexed by round
    evidence,                   \* Set of collected evidence (for accountability)
    action,                     \* String label of last executed action (for TLC tracing)
    received_timely_proposal,   \* Per-process set of timely proposal messages
    inspected_proposal          \* Per-(round,process) timestamp of last inspection

\* Small group 1: messsage broadcast
msgsBroadcastVars == <<msgs_propose, msgs_prevote, msgs_precommit, msgs_timeout>>

\* Small group 2: Auditing proposal
propAuditVars == <<received_timely_proposal, inspected_proposal>>

\* Small group 3: trace and evidence
traceVars == <<evidence, action>>

bookkeepingVars == <<msgsBroadcastVars, propAuditVars, traceVars>>

(* ======================== INVARIANT SUPPORT VARIABLES ====================== *)
\* Ghost variables used exclusively to express timing invariants.
\* These are never read by the protocol logic itself.
VARIABLES
    begin_round,            \* Earliest local clock when any process entered round r
    end_consensus,          \* Local clock when process p decided
    last_begin_round,       \* Latest local clock when any process entered round r
    proposal_time,          \* Real time at which the proposal for round r was broadcast
    proposal_received_time  \* Real time at which the first timely proposal was received

invariantVars == 
    <<begin_round, end_consensus, last_begin_round, 
        proposal_time, proposal_received_time>>


(* ======================== P2P HEALTH / DA GAP / BTC GAP SENSOR ================================ *)
VARIABLES 
    active_peers,            \* Set of currently connected peers
    anchor_peers,            \* Statically configured bootstrap/anchor peer set
    blacklisted_peers,       \* Peers identified as malicious and blacklisted
    peer_churn_rate,         \* Interference/disconnection rate in the routing table
    avg_peer_tenure,         \* Average age of current connections
    peer_latency             \* Average block/heartbeat transmission latency

p2pHealthSensorVars == 
    <<active_peers, anchor_peers, blacklisted_peers, 
        peer_churn_rate, avg_peer_tenure, peer_latency>>


VARIABLES 
    h_engram_current,           \* Latest Engram chain block height
    h_engram_verified,          \* Last DA-verified Engram block height
    is_attestation_failed,      \* DA attestation failure flag from Blobstream
    is_das_failed               \* Data availability sampling failure flag

daGapSensorVars == <<h_engram_current, h_engram_verified, is_attestation_failed, is_das_failed>>


VARIABLES
    h_btc_current,              \* Latest observed Bitcoin block height
    h_btc_submitted,            \* Height at which the ZK re-anchoring proof was submitted
    h_btc_anchored,             \* Last confirmed Engram checkpoint height on Bitcoin
    is_btc_spv_failed           \* OP_RETURN inclusion check & Block header verification failure flag

btcGapSensorVars == <<h_btc_current, h_btc_submitted, h_btc_anchored, is_btc_spv_failed>>

\* All environmental sensors
networkSensorVars == <<p2pHealthSensorVars, daGapSensorVars, btcGapSensorVars>>


(* ======================== FSM VARIABLES ====================== *)
\* Circuit-breaker FSM state
VARIABLES
    state,                   \* FSM state: "ANCHORED"|"SUSPICIOUS"|"SOVEREIGN"|"RECOVERING"
    safe_blocks,             \* Consecutive healthy blocks counted during RECOVERING
    suspicious_duration,     \* Count the number of system blocks/ticks stuck in SUSPICIOUS
    reanchoring_proof_valid  \* Boolean: ZK re-anchoring proof confirmed on-chain

\* Top-level FSM tuple consumed by EngramTendermint actions
fsmVars == <<state, safe_blocks, suspicious_duration, reanchoring_proof_valid>>


(* ======================== CENSORSHIP VARIABLES ======================= *)
VARIABLES
    forced_tx_queue,         \* Transactions pending forced inclusion (censorship resistance)
    tx_ignored_rounds        \* Per-(process,tx) counter of rounds where tx was ignored

censorshipVars == <<forced_tx_queue, tx_ignored_rounds>>


(* ======================== LIDO CERTIFICATE VARIABLES ============== *)
\* Abstract pacemaker certificates used by EngramServer and the LiDO refinement.
VARIABLES
    quorum_certs,       \* Set of Quorum Certificates (E_QC, M_QC)
    timeout_certs       \* Set of Timeout Certificates (T_QC)

\* Tuple of consensus certificates (LiDO Certificates)
certificateVars == <<quorum_certs, timeout_certs>>

=========================================================================
