---------------- MODULE MC_ServerRefinementLiveness ---------------- 
EXTENDS EngramServer, TLC, Sequences

CONSTANTS n1, n2, n3, n4

ASSUME QuorumOverlap

(* ======================== NETWORK SCALE =============================== *)
MC_Nodes == {n1, n2, n3, n4} 
MC_Method == {"TX_NORMAL", "TX_WITHDRAWAL"}
MC_Faulty == {n4}
MC_Corr == MC_Nodes \ MC_Faulty

(* ======================== ROTATIONAL LEADER CONFIGURATION =============================== *)
MC_NodeSeq == <<n1, n2, n3, n4>>
MC_Proposer == [r \in 0..5 |-> MC_NodeSeq[(r % 4) + 1]]

(* ======================== INIT & NEXT =============================== *)
MC_Server_Init == Server_Init
MC_Server_Next == Server_Next

(* ======================== FAIRNESS & SPECIFICATION =============================== *) 
MC_Server_Fairness == 
    /\ WF_serverVars(Server_AdvanceRealTime)
    /\ \A p \in MC_Corr : WF_serverVars(Server_MessageProcessing(p)) 
    /\ FSM_Fairness

MC_Server_Spec == MC_Server_Init /\ [][MC_Server_Next]_serverVars /\ MC_Server_Fairness

(* ======================== PRUNING CONSTRAINT) =============================== *)
StateSpaceLimit == 
    \* 1. Tendermint constraints
    /\ \A n \in MC_Corr : round[n] <= MaxRound
    /\ realTime <= MaxTimestamp

    \* 2. Environment Constraints
    /\ h_btc_current <= MaxBTCHeight
    /\ h_engram_current <= MaxEngramHeight
    /\ h_engram_verified <= h_engram_current
    /\ h_btc_submitted <= h_btc_current
    /\ h_btc_anchored <= h_btc_submitted

    \* 3. Controlled Chaos
    /\ peer_count \in {2, 3}
    /\ is_das_failed \in BOOLEAN
    /\ state \in {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}


(* ======================== REFINEMENT CHECKS =============================== *)
\* Phase 1: Verify Safety
RefinementSafety == AbstractConsensus!Safety

\* Phase 2: Verify Liveness
RefinementLiveness == AbstractConsensus!Liveness
=============================================================================