---------------- MODULE MC_TendermintLiveness ----------------
EXTENDS EngramTendermint, TLC

CONSTANTS p1, p2, p3, p4, v1, v3

MC_Proposer == [r \in 0..MaxRound |-> IF r % 2 = 0 THEN p1 ELSE p2]

MC_Init == 
    /\ Init
    /\ state = "ANCHORED"
    /\ h_btc_current = 100
    /\ h_btc_submitted = 100
    /\ h_btc_anchored = 100
    /\ h_da_local = 50
    /\ h_da_verified = 50
    /\ is_das_failed = FALSE
    /\ peer_count = 10
    /\ safe_blocks = 0
    /\ reanchoring_proof_valid = TRUE

Termination == 
    /\ \/ \A p \in Corr : step[p] = "DECIDED"
       \/ realTime >= MaxTimestamp
       \/ \E p \in Corr : round[p] >= 1
    /\ UNCHANGED <<coreVars, temporalVars, invariantVars, fsmVars>>
    /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, evidence, receivedTimelyProposal, inspectedProposal>>
    /\ action' = "Termination"

MC_Next == Next \/ Termination

MC_LivenessSpec == MC_Init /\ [][MC_Next]_vars /\ Fairness
==============================================================