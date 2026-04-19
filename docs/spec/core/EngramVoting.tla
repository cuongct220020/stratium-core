----------------------- MODULE EngramVoting -----------------------
EXTENDS Integers, FiniteSets

(********************* GIAO DIỆN & HẰNG SỐ ************************)
CONSTANTS Nodes,          \* Tập hợp các node tham gia đồng thuận
          TotalStake,     \* Tổng trọng số Stake của mạng
          Stake,          \* Hàm ánh xạ trọng số: [Nodes -> Nat]
          ValidValues,    \* Các giá trị hợp lệ
          MaxRound,       \* Số vòng tối đa cho TLC Model Checker
          Proposer,       \* Hàm chọn Proposer: [Rounds -> Nodes]
          MinTimestamp,   
          MaxTimestamp    

(********************* BIẾN CỦA TẦNG VOTING (TẦNG 4) **************)
VARIABLES tm_round, step, decision, lockedValue, lockedRound, validValue, validRound
coreVars == <<tm_round, step, decision, lockedValue, lockedRound, validValue, validRound>>

VARIABLES msgsPropose, msgsPrevote, msgsPrecommit, evidence
bookkeepingVars == <<msgsPropose, msgsPrevote, msgsPrecommit, evidence>>

vars_voting == <<coreVars, bookkeepingVars>>

(********************* BIẾN CỦA TẦNG SERVER & CONSENSUS (ĐỂ ÁNH XẠ)*)
VARIABLES server_rounds, qcs, tcs, tree, local_times, lido_round, rem_time, btc_connection
vars_upper == <<server_rounds, qcs, tcs, tree, local_times, lido_round, rem_time, btc_connection>>

vars == <<vars_voting, vars_upper>>

(********************* BEST PRACTICE 1: INSTANCE TẦNG TRÊN ********)
\* Mapping lido_round vào biến round của EngramServer để tránh trùng lặp
Server == INSTANCE EngramServer WITH round <- lido_round

(********************* HÀM BỔ TRỢ & LOCAL POS *********************)
RECURSIVE SumStake(_)
SumStake(Q) == 
    IF Q = {} THEN 0 
    ELSE LET n == CHOOSE x \in Q : TRUE 
         IN Stake[n] + SumStake(Q \ {n})

isSQuorum(Q) == btc_connection = "STABLE" /\ SumStake(Q) * 3 > TotalStake * 2

(********************* KHỞI TẠO ***********************************)
InitVoting == 
    /\ Server!InitServer
    /\ tm_round = [n \in Nodes |-> 0]
    /\ step = [n \in Nodes |-> "PROPOSE"]
    /\ decision = [n \in Nodes |-> <<"None", -1>>]
    /\ lockedValue = [n \in Nodes |-> "None"]
    /\ lockedRound = [n \in Nodes |-> -1]
    /\ validValue = [n \in Nodes |-> <<"None", -1, -1>>]
    /\ validRound = [n \in Nodes |-> -1]
    /\ msgsPropose = [r \in 0..MaxRound |-> {}]
    /\ msgsPrevote = [r \in 0..MaxRound |-> {}]
    /\ msgsPrecommit = [r \in 0..MaxRound |-> {}]
    /\ evidence = {}

(********************* CÁC HÀNH ĐỘNG BỎ PHIẾU CỐT LÕI *************)
UponProposalInProposeAndPrevote(p) == 
    \E v \in ValidValues, t \in MinTimestamp..MaxTimestamp, vr \in 0..MaxRound, pr \in 0..MaxRound: 
        LET r == tm_round[p] IN 
        LET prop == <<v, t, pr>> IN 
        /\ step[p] = "PROPOSE" 
        /\ 0 <= vr /\ vr < r 
        /\ pr <= vr 
        /\ LET msg == [ type |-> "PROPOSAL", src |-> Proposer[r], round |-> r, proposal |-> prop, validRound |-> vr ] IN 
           /\ msg \in msgsPropose[r] 
           /\ LET PV == { m \in msgsPrevote[vr]: m.id = prop } IN 
              /\ isSQuorum(PV) 
              /\ evidence' = PV \union {msg} \union evidence 
              /\ LET mid == IF (lockedRound[p] <= vr \/ lockedValue[p] = v) THEN prop ELSE "None" IN 
                 msgsPrevote' = [msgsPrevote EXCEPT ![r] = msgsPrevote[r] \union {[type |-> "PREVOTE", src |-> p, round |-> r, id |-> mid]}]
        /\ step' = [step EXCEPT ![p] = "PREVOTE"]
        /\ UNCHANGED <<tm_round, decision, lockedValue, lockedRound, validValue, validRound, msgsPropose, msgsPrecommit, vars_upper>>

UponQuorumOfPrevotesAny(p) == 
    /\ step[p] = "PREVOTE" 
    /\ \E MyEvidence \in SUBSET msgsPrevote[tm_round[p]]: 
        LET Voters == { m.src: m \in MyEvidence } IN 
        /\ isSQuorum(Voters) 
        /\ evidence' = MyEvidence \union evidence 
        /\ msgsPrecommit' = [msgsPrecommit EXCEPT ![tm_round[p]] = msgsPrecommit[tm_round[p]] \union {[type |-> "PRECOMMIT", src |-> p, round |-> tm_round[p], id |-> "None"]}]
        /\ step' = [step EXCEPT ![p] = "PRECOMMIT"]
        /\ qcs' = qcs \cup {[round |-> tm_round[p], method |-> "None", signers |-> Voters]} 
        /\ UNCHANGED <<tm_round, decision, lockedValue, lockedRound, validValue, validRound, msgsPropose, msgsPrevote, server_rounds, tcs, tree, local_times, lido_round, rem_time, btc_connection>>

UponProposalInPrevoteOrCommitAndPrevote(p) == 
    \E v \in ValidValues, t \in MinTimestamp..MaxTimestamp, vr \in -1..MaxRound: 
        LET r == tm_round[p] IN 
        LET prop == <<v, t, r>> IN 
        /\ step[p] \in {"PREVOTE", "PRECOMMIT"} 
        /\ LET msg == [ type |-> "PROPOSAL", src |-> Proposer[r], round |-> r, proposal |-> prop, validRound |-> vr ] IN 
           /\ msg \in msgsPropose[r] 
           /\ LET PV == { m \in msgsPrevote[r]: m.id = prop } IN 
              /\ isSQuorum(PV) 
              /\ evidence' = PV \union {msg} \union evidence 
              /\ IF step[p] = "PREVOTE" THEN 
                    /\ lockedValue' = [lockedValue EXCEPT ![p] = v] 
                    /\ lockedRound' = [lockedRound EXCEPT ![p] = r] 
                    /\ msgsPrecommit' = [msgsPrecommit EXCEPT ![r] = msgsPrecommit[r] \union {[type |-> "PRECOMMIT", src |-> p, round |-> r, id |-> prop]}] 
                    /\ step' = [step EXCEPT ![p] = "PRECOMMIT"]
                    /\ UNCHANGED <<tm_round, decision, validValue, validRound>>
                 ELSE 
                    /\ validValue' = [validValue EXCEPT ![p] = prop] 
                    /\ validRound' = [validRound EXCEPT ![p] = r] 
                    /\ UNCHANGED <<tm_round, step, decision, lockedValue, lockedRound, msgsPrecommit>>
        /\ UNCHANGED <<msgsPropose, msgsPrevote, vars_upper>>

UponQuorumOfPrecommitsAny(p) == 
    /\ \E MyEvidence \in SUBSET msgsPrecommit[tm_round[p]]: 
        LET Committers == { m.src: m \in MyEvidence } IN 
        /\ isSQuorum(Committers) 
        /\ evidence' = MyEvidence \union evidence 
        /\ tm_round[p] + 1 <= MaxRound 
        /\ tm_round' = [tm_round EXCEPT ![p] = tm_round[p] + 1]
        /\ step' = [step EXCEPT ![p] = "PROPOSE"]
        /\ tcs' = tcs \cup {[round |-> tm_round[p], signers |-> Committers]} 
        /\ UNCHANGED <<decision, lockedValue, lockedRound, validValue, validRound, msgsPropose, msgsPrevote, msgsPrecommit, server_rounds, qcs, tree, local_times, lido_round, rem_time, btc_connection>>

UponProposalInPrecommitNoDecision(p) == 
    /\ decision[p] = <<"None", -1>> 
    /\ \E v \in ValidValues, t \in MinTimestamp..MaxTimestamp, r \in 0..MaxRound, pr \in 0..MaxRound, vr \in -1..MaxRound: 
        LET prop == <<v, t, pr>> IN 
        LET msg == [ type |-> "PROPOSAL", src |-> Proposer[r], round |-> r, proposal |-> prop, validRound |-> vr ] IN 
        /\ msg \in msgsPropose[r] 
        /\ LET PV == { m \in msgsPrecommit[r]: m.id = prop } IN 
           /\ isSQuorum(PV) 
           /\ evidence' = PV \union {msg} \union evidence 
           /\ decision' = [decision EXCEPT ![p] = <<prop, r>>] 
           /\ step' = [step EXCEPT ![p] = "DECIDED"]
           /\ qcs' = qcs \cup {[round |-> r, method |-> v, signers |-> PV]} 
           /\ UNCHANGED <<tm_round, lockedValue, lockedRound, validValue, validRound, msgsPropose, msgsPrevote, msgsPrecommit, server_rounds, tcs, tree, local_times, lido_round, rem_time, btc_connection>>

(********************* TRẠNG THÁI TIẾP THEO (NEXT) ****************)
MessageProcessing(p) == 
    \/ UponProposalInProposeAndPrevote(p)
    \/ UponQuorumOfPrevotesAny(p)
    \/ UponProposalInPrevoteOrCommitAndPrevote(p)
    \/ UponQuorumOfPrecommitsAny(p)
    \/ UponProposalInPrecommitNoDecision(p)

NextVoting == \E p \in Nodes: MessageProcessing(p)

(********************* BEST PRACTICE 2: FAIRNESS (LIVENESS) *******)
SpecVoting == 
    /\ InitVoting 
    /\ [][NextVoting]_vars 
    /\ WF_vars(NextVoting)

(********************* BEST PRACTICE 3: ĐỊNH LÝ REFINEMENT ********)
THEOREM SpecVoting => Server!SpecServer
======================================================================