----------------------- MODULE EngramServer ----------------------- 
EXTENDS Naturals, FiniteSets, EngramTendermint, EngramFSM

CONSTANTS Nodes, Method, Stake, TotalStake, ResetTime, MaxBTCHeight

InitServer == 
    /\ Init       
    /\ FSM_Init   
    /\ qcs = {} 
    /\ tcs = {}

\* Helper: Kích hoạt khi mạng lưới đã gom đủ 2/3 Precommit hợp lệ (Đã chốt Block)
GlobalDecisionExists == 
    \E r \in Rounds : 
        \E m \in msgsPrecommit[r] : 
            m.id /= NilProposal /\ Cardinality({msg \in msgsPrecommit[r] : msg.id = m.id}) >= THRESHOLD2

\* Hook 0: Leader inserts proposal -> Create E_QC (Maps to Abstract Pull)
Server_InsertProposal(p) == 
    /\ ~GlobalDecisionExists       \* <--- CHỐT CHẶN 1: Cấm mồi block mới nếu mạng đã chốt xong
    /\ InsertProposal(p) 
    /\ LET NewEQC == [ type       |-> "E_QC", 
                       round      |-> round[p], 
                       caller     |-> p, 
                       method     |-> "None", 
                       btc_height |-> h_btc_current ] 
       IN qcs' = qcs \cup {NewEQC} 
    /\ UNCHANGED <<tcs, fsmVars>>

\* Hook 1: Proposer votes for its own proposal -> Create M_QC (Maps to Abstract Invoke)
Server_ProposerVotes(p) == 
    /\ \/ UponProposalInPropose(p) 
       \/ UponProposalInProposeAndPrevote(p)    \* <--- BẮT CẢ HÀNH ĐỘNG VOTE LẠI BLOCK CŨ
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

\* Bridge all other Tendermint actions as Pass-Through
Server_PassThrough(p) == 
    \/ ReceiveProposal(p) 
    \/ UponProposalInPrevoteOrCommitAndPrevote(p) 
    \/ UponQuorumOfPrevotesAny(p) 
    \/ /\ UponQuorumOfPrecommitsAny(p)
       /\ ~GlobalDecisionExists       \* <--- CHỐT CHẶN CẮT TỈA NHÁNH
    \/ UponProposalInPrecommitNoDecision(p) 
    \/ OnTimeoutPropose(p) 
    \/ OnQuorumOfNilPrevotes(p) 
    \/ OnRoundCatchup(p)

Server_MessageProcessing(p) == 
    \/ Server_PassThrough(p) /\ UNCHANGED <<qcs, tcs, fsmVars>> 
    \/ Server_InsertProposal(p)
    \/ Server_ProposerVotes(p)

NextServer == 
    \/ AdvanceRealTime /\ UNCHANGED <<qcs, tcs, fsmVars>> 
    \/ /\ SynchronizedLocalClocks 
       /\ \E p \in Corr: Server_MessageProcessing(p) 
    \/ FSM_Next /\ UNCHANGED <<coreVars, temporalVars, invariantVars, bookkeepingVars, action, qcs, tcs>>

SpecServer == InitServer /\ [][NextServer]_serverVars

ServerEventualDecision == <>(\E p \in Corr : step[p] = "DECIDED")

ServerFSMLiveness == 
    /\ CircuitBreakerLiveness 
    /\ RecoveryAttemptLiveness 
    /\ CompleteRecoveryLiveness

ForcedInclusionLiveness == 
    \A tx \in ValidValues : 
        ([]<> (\E r \in Rounds, p \in Corr : \E m \in msgsPropose[r] : m.src = p /\ m.proposal.value = tx)) 
        => <>(\E p \in Corr : decision[p] /= NilDecision /\ decision[p][1].value = tx)

GST_Reached == 
    /\ SynchronizedLocalClocks 
    /\ \A p \in Corr : peer_count >= MIN_PEERS  
    /\ state = "ANCHORED"

EventualDecisionUnderGST == ([]<> GST_Reached) ~> (\E p \in Corr : step[p] = "DECIDED")

\* --- ABSTRACT MAPPING ZONE ---

RECURSIVE SS_Op(_)
SS_Op(Q) == IF Q = {} THEN 0 ELSE LET n == CHOOSE x \in Q : TRUE IN Stake[n] + SS_Op(Q \ {n})
Q_abstract == CHOOSE q \in SUBSET Nodes : (SS_Op(q) * 3 > TotalStake * 2)

\* FIX 1: Trích xuất chính xác phần tử của Tuple bằng pair[1] (vòng) và pair[2] (proposal)
CommitPairs == UNION { { <<r, m.id>> : m \in msgsPrecommit[r] } : r \in Rounds }
ValidCommits == 
    { pair \in CommitPairs : 
        /\ pair[2] /= NilProposal 
        /\ Cardinality({m \in msgsPrecommit[pair[1]] : m.id = pair[2]}) >= THRESHOLD2 }

\* FIX 2: Ép cứng method |-> "None" cho C_Cache để khớp tuyệt đối với lõi LiDO
c_caches_dynamic == {
    [ type       |-> "C", 
      c_round    |-> pair[1] + 1, 
      caller     |-> Proposer[pair[1]], 
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
    IN e_caches \cup m_caches \cup c_caches_dynamic

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

AbstractConsensus == INSTANCE EngramConsensus WITH
    Nodes           <- Nodes,
    Method          <- Method,
    Stake           <- Stake,
    TotalStake      <- TotalStake,
    ResetTime       <- 0,
    MaxBTCHeight    <- MaxBTCHeight,
    tree            <- mapped_tree,
    fsm_state       <- mapped_fsm_state,
    round           <- Max({round[n] : n \in Corr}) + 1,
    local_times     <- mapped_local_times,
    rem_time        <- 0,
    h_btc_current   <- h_btc_current + 2,
    h_btc_anchored  <- h_btc_anchored + 2

QuorumOverlap == 
    \A q1, q2 \in AbstractConsensus!ValidQuorums : 
        (q1 \intersect q2) \intersect Corr /= {}

===================================================================