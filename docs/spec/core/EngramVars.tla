--------------------------- MODULE EngramVars ---------------------------
CONSTANTS
    HYSTERESIS_WAIT,    \* Consecutive safe blocks required for successful recovery
    T_DA                \* Block gap since the last DA publication verification


(* ======================== TENDERMINT CORE VARIABLES  ======================== *)
VARIABLES 
    round, step, decision, lockedValue, lockedRound, validValue, validRound

coreVars == <<round, step, decision, lockedValue, lockedRound, validValue, validRound>>


(* ======================== TIME / TEMPORAL VARIABLES ======================== *)
VARIABLES 
    localClock, realTime, localRemTime

temporalVars == <<localClock, realTime, localRemTime>>


(* ======================== BOOKKEEPING VARIABLES ======================== *)
VARIABLES 
    msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout, evidence, action, 
    receivedTimelyProposal, inspectedProposal

bookkeepingVars == <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout, evidence, action, receivedTimelyProposal, inspectedProposal>>


(* ======================== INVARIANT SUPPORT VARIABLES ======================== *)
VARIABLES 
    beginRound, endConsensus, lastBeginRound, proposalTime, proposalReceivedTime

invariantVars == <<beginRound, endConsensus, lastBeginRound, proposalTime, proposalReceivedTime>>


(* ======================== FSM & ENVIRONMENT VARIABLES ======================== *)
VARIABLES 
    state, h_btc_current, h_btc_submitted, h_btc_anchored, 
    h_engram_current, h_engram_verified, is_das_failed, peer_count, 
    safe_blocks, reanchoring_proof_valid

\* Definition for EngramTendermint to use
fsmVars == <<state, h_btc_current, h_btc_submitted, h_btc_anchored, h_engram_current, h_engram_verified, is_das_failed, peer_count, safe_blocks, reanchoring_proof_valid>>

\* Definition for EngramFSM to use
envVars == <<h_engram_current, h_engram_verified, h_btc_current, h_btc_submitted, h_btc_anchored, peer_count, reanchoring_proof_valid, is_das_failed>>


(* ======================== SERVER & TENDERMINT TUPLES ======================== *)
VARIABLES 
    qcs, tcs

\* Standard tuple used for EngramTendermint (called in UNCHANGED vars, WF_vars rows)
tendermintVars == <<coreVars, temporalVars, bookkeepingVars, action, invariantVars, fsmVars>>

\* Tuple used for EngramServer
serverVars == <<coreVars, temporalVars, invariantVars, bookkeepingVars, action, qcs, tcs, fsmVars>>
=========================================================================