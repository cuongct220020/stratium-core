----------------------- MODULE EngramServer ----------------------- 
EXTENDS Naturals, FiniteSets, EngramFSM, EngramTendermint

CONSTANTS Nodes, Method, ResetTime

(* ======================== SERVER HOOKS (INTEGRATION LAYER) =============================== *)
\* Helper: Activated when the network has collected 2/3 of valid Precommits (Block closed)
GlobalDecisionExists == 
    \E r \in Rounds : 
        \E m \in msgsPrecommit[r] : 
            m.id /= NilProposal /\ Cardinality({msg \in msgsPrecommit[r] : msg.id = m.id}) >= THRESHOLD2

\* Hook 1: Leader prepares and inserts proposal -> Create E_QC (Maps to Abstract Pull)
Server_InsertProposal(p) ==
    /\ ~GlobalDecisionExists 
    /\ p = Proposer[round[p]]
    /\ step[p] = "PROPOSE"
    /\ \A m \in msgsPropose[round[p]]: m.src /= p
    
    \* STATE SPACE CONTROL: Only branch here, before calling the black-box Tendermint
    /\ \E v \in ValidValues:
         LET 
            receipt == [
                blockHeight |-> h_engram_verified, 
                attestation |-> IsDAHealthy
            ]
            proof_search_space == 
                IF state = "RECOVERING" /\ safe_blocks >= HYSTERESIS_WAIT
                THEN {TRUE, FALSE}
                ELSE {FALSE}
         IN 
            \E proof_found \in proof_search_space:
                LET prop == IF validValue[p] /= NilProposal
                            THEN validValue[p]
                            ELSE Proposal(v, localClock[p], round[p], state, 
                                            receipt, h_btc_anchored, proof_found)
                IN 
                    \* Inject the concrete proposal into Tendermint
                    /\ InsertProposal(p, prop)
                    
                    \* Abstract Pacemaker (LiDO) mapping
                    /\ LET NewEQC == [ type         |-> "E_QC", 
                                       round        |-> round[p], 
                                       caller       |-> p, 
                                       method       |-> "None", 
                                       btc_height   |-> h_btc_current ]
                       IN qcs' = qcs \cup {NewEQC}
    /\ UNCHANGED <<tcs, fsmVars>> 


\* Hook 2: Proposer votes for its own proposal -> Create M_QC (Maps to Abstract Invoke)
Server_ProposerVotes(p) == 
    /\ \/ UponProposalInPropose(p) 
       \/ UponProposalInProposeAndPrevote(p)
    /\ IF p = Proposer[round[p]] /\ \E m \in msgsPropose[round[p]] : m.src = p THEN
           LET prop == (CHOOSE m \in msgsPropose[round[p]] : m.src = p).proposal
               NewMQC == [ type       |-> "M_QC", 
                           round      |-> round[p], 
                           caller     |-> p, 
                           method     |-> prop.value, 
                           btc_height |-> h_btc_current ] 
           IN qcs' = qcs \cup {NewMQC} 
       ELSE
           qcs' = qcs
    /\ UNCHANGED <<tcs, fsmVars>>


\* Hook 3: Intercept the decision moment to trigger FSM recovery and State Sync
Server_UponProposalInPrecommitNoDecision(p) ==
    \* 1. Execute the core Tendermint decision logic
    /\ UponProposalInPrecommitNoDecision(p)
    
    \* 2. Extract the just-decided proposal (the majority's truth)
    /\ LET r == round[p]
           msg == CHOOSE m \in msgsPropose[r] : m.src = Proposer[r] /\ m.type = "PROPOSAL"
           prop == msg.proposal
       IN
            \* 3. STATE SYNC: Force local memory to update according to the majority of the network.
            /\ state' = prop.fsm_state
            /\ h_btc_anchored' = prop.btc_anchored
            /\ h_engram_verified' = prop.da_receipt.blockHeight
            
            \* Note: Proof of ZK submission to Bitcoin has been acknowledged, but is not yet considered valid.
            /\ IF prop.fsm_state = "RECOVERING" /\ prop.zk_proof_ref = TRUE
                THEN /\ h_btc_submitted' = h_btc_current
                     /\ reanchoring_proof_valid' = FALSE   \* Wait for Bitcoin confirmation
                ELSE /\ h_btc_submitted' = h_btc_submitted
                     /\ reanchoring_proof_valid' = reanchoring_proof_valid

            \* Force local sensors: If the majority of the network is locked, all false alarms must be turned off.
            /\ IF prop.fsm_state = "ANCHORED" 
                THEN 
                    /\ h_btc_current' = prop.btc_anchored
                    /\ h_engram_current' = prop.da_receipt.blockHeight
                    /\ is_das_failed' = FALSE
                ELSE 
                    \* If not in ANCHORED mode, leave the sensor in place and let the FSM make the decision.
                    /\ UNCHANGED <<h_btc_current, h_engram_current, is_das_failed>>
             
          /\ UNCHANGED <<safe_blocks, peer_count>>
                 
    \* 4. Keep Abstract Pacemaker state unchanged
    /\ UNCHANGED <<qcs, tcs>>


\* Hook 4: Intercept the moment a Quorum of Timeouts is reached to create T_QC
Server_UponTimeoutCert(p) ==
    \* 1. Check if the Timeout message inbox has enough votes (2f+1) for the current round.
    /\ \E MyEvidence \in SUBSET msgsTimeout[round[p]]:
        LET Timers == { m.src: m \in MyEvidence } IN
        Cardinality(Timers) >= THRESHOLD2
        
    \* 2. Move on to the next round.
    /\ StartRound(p, round[p] + 1)
    
    \* 3. Ghi nhận sự kiện TimeoutCert vào tcs cho LiDO
    /\ LET NewTQC == [
           type       |-> "T_QC",
           round      |-> round[p],
           caller     |-> p,
           btc_height |-> h_btc_current
       ]
       IN tcs' = tcs \cup {NewTQC}
       
    /\ UNCHANGED <<qcs, fsmVars>>
    /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout, evidence, receivedTimelyProposal, inspectedProposal>>
    /\ UNCHANGED <<decision, lockedValue, lockedRound, validValue, validRound, endConsensus, proposalTime, proposalReceivedTime>>


\* Bridge all other Tendermint actions as Pass-Through
Server_PassThrough(p) ==
    \/ ReceiveProposal(p)
    \/ UponProposalInPrevoteOrCommitAndPrevote(p)
    \/ UponQuorumOfPrevotesAny(p)
    \/ /\ UponQuorumOfPrecommitsAny(p)
       /\ ~GlobalDecisionExists 
    \/ Server_UponProposalInPrecommitNoDecision(p)
    \/ OnTimeoutPropose(p)
    \/ OnQuorumOfNilPrevotes(p)
    \/ OnRoundCatchup(p)


Server_MessageProcessing(p) == 
    \/ Server_PassThrough(p) /\ UNCHANGED <<qcs, tcs, fsmVars>> 
    \/ Server_InsertProposal(p)
    \/ Server_ProposerVotes(p)


(* ======================== SYSTEM SPECIFICATION (INIT & NEXT) =============================== *)
Server_Init == 
    /\ TM_Init       
    /\ FSM_Init   
    /\ qcs = {} /\ tcs = {}

Server_AdvanceRealTime == 
    /\ AdvanceRealTime 
    /\ UNCHANGED <<qcs, tcs, fsmVars>>

Server_Next == 
    \/ Server_AdvanceRealTime
    \/ /\ SynchronizedLocalClocks 
       /\ \E p \in Corr: Server_MessageProcessing(p)
    \/ FSM_Next /\ UNCHANGED <<coreVars, temporalVars, invariantVars, bookkeepingVars, action, qcs, tcs>>

Server_Spec == Server_Init /\ [][Server_Next]_serverVars


(* ======================== HYBRID INVARIANTS =============================== *)
\* FSM state consistency in decided proposals
FSMStateConsistency == 
    \A p \in Corr: decision[p] /= NilDecision => decision[p].prop.fsm_state = state

\* DA receipt consistency
DAReceiptConsistency == 
    \A p \in Corr: (decision[p] /= NilDecision /\ decision[p].prop.fsm_state \in {"ANCHORED", "RECOVERING"}) 
        => decision[p].prop.da_receipt.attestation = TRUE

\* Bitcoin anchor consistency
BTCConsistency == 
    \A p \in Corr: decision[p] /= NilDecision => decision[p].prop.btc_anchored = h_btc_anchored

\* ZK Proof consistency
ZKProofConsistency == 
    \A p \in Corr: (decision[p] /= NilDecision /\ decision[p].prop.fsm_state = "RECOVERING" /\ safe_blocks = HYSTERESIS_WAIT) 
        => decision[p].prop.zk_proof_ref = TRUE

HybridTendermintInv ==
    /\ FSMStateConsistency
    /\ DAReceiptConsistency
    /\ BTCConsistency
    /\ ZKProofConsistency


(* ======================== LIVENESS & TEMPORAL PROPERTIES =============================== *)
ServerEventualDecision == <>(\E p \in Corr : step[p] = "DECIDED")

ServerFSMLiveness == 
    /\ CircuitBreakerLiveness 
    /\ RecoveryAttemptLiveness 
    /\ CompleteRecoveryLiveness

ForcedInclusionLiveness == 
    \A tx \in ValidValues : 
        ([]<> (\E r \in Rounds, p \in Corr : \E m \in msgsPropose[r] : m.src = p /\ m.proposal.value = tx)) 
        => <>(\E p \in Corr : decision[p] /= NilDecision /\ decision[p].prop.value = tx)

GST_Reached == 
    /\ SynchronizedLocalClocks 
    /\ \A p \in Corr : peer_count >= MIN_PEERS  
    /\ state = "ANCHORED"

EventualDecisionUnderGST == ([]<> GST_Reached) ~> (\E p \in Corr : step[p] = "DECIDED")


(* ======================== LIDO ABSTRACT MAPPING (REFINEMENT) =============================== *)
\* STATE SPACE OPTIMIZATION: Homogeneous Stake Assumption
\* Instead of calculating arbitrary stake weights, we treat each node equally (1 vote).
\* This prevents state space explosion while preserving the mathematical Quorum Overlap.
Q_abstract == CHOOSE q \in SUBSET Nodes : Cardinality(q) >= THRESHOLD2

CommitPairs == UNION { { <<r, m.id>> : m \in msgsPrecommit[r] } : r \in Rounds }

ValidCommits == 
    { pair \in CommitPairs : 
        /\ pair[2] /= NilProposal
        /\ Cardinality({m \in msgsPrecommit[pair[1]] : m.id = pair[2]}) >= THRESHOLD2 }

c_caches_dynamic == {
    [ type       |-> "C", 
      c_round    |-> pair[1] + 1, 
      caller     |-> Proposer[pair[2]], 
      method     |-> "None",
      voters     |-> Q_abstract, 
      btc_height |-> h_btc_current + 2 ] : pair \in ValidCommits
}

mapped_tree ==
    LET e_caches == {
        [ type       |-> "E",
          c_round    |-> qc.round + 1,
          caller     |-> qc.caller,
          method     |-> "None",
          voters     |-> Q_abstract,
          btc_height |-> qc.btc_height + 2 ] : qc \in {q \in qcs : q.type = "E_QC"}
    }
        m_caches == {
        [ type       |-> "M",
          c_round    |-> qc.round + 1,
          caller     |-> qc.caller,
          method     |-> qc.method,
          voters     |-> {qc.caller},
          btc_height |-> qc.btc_height + 2 ] : qc \in {q \in qcs : q.type = "M_QC"}
    }
        t_caches == {
        [ type       |-> "T",
          c_round    |-> tc.round + 1,
          caller     |-> tc.caller,
          method     |-> "None",
          voters     |-> Q_abstract,
          btc_height |-> tc.btc_height + 2 ] : tc \in {t \in tcs : t.type = "T_QC"}
    }
    IN e_caches \cup m_caches \cup c_caches_dynamic \cup t_caches

mapped_fsm_state == IF state \in {"ANCHORED", "SUSPICIOUS"} THEN "ANCHORED" ELSE "SOVEREIGN"

mapped_local_times == 
    [n \in Nodes |-> 
        IF n \in Q_abstract THEN
            Max(
                {0} \cup 
                {qc.round + 1 : qc \in {q \in qcs : q.type = "E_QC"}} \cup 
                {c.c_round + 1 : c \in c_caches_dynamic}
            )
        ELSE 0
    ]

\* SYNTHESIZE HOMOGENEOUS STAKE: Map each node to exactly 1 stake unit
HomogeneousStake == [n \in Nodes |-> 1]
HomogeneousTotalStake == Cardinality(Nodes)

CurrentMaxRound ==
   Max({ round[p] : p \in Corr })

CurrentRoundNodes ==
   { p \in Corr : round[p] = CurrentMaxRound }

MinRemTime ==
   Min({ localRemTime[p] : p \in CurrentRoundNodes })


AbstractConsensus ==
    INSTANCE EngramConsensus WITH
        Nodes           <- Nodes,
        Method          <- Method,
        Stake           <- HomogeneousStake,
        TotalStake      <- HomogeneousTotalStake,
        ResetTime       <- TimeoutDuration,
        MaxBTCHeight    <- MaxBTCHeight,
        tree            <- mapped_tree,
        fsm_state       <- mapped_fsm_state,
        round           <- CurrentMaxRound + 1,
        local_times     <- mapped_local_times,
        rem_time        <- MinRemTime,
        h_btc_current   <- h_btc_current + 2,
        h_btc_anchored  <- h_btc_anchored + 2

QuorumOverlap == 
    \A q1, q2 \in AbstractConsensus!ValidQuorums : 
        (q1 \intersect q2) \intersect Corr /= {}
===================================================================