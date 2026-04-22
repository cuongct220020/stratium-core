----------------------- MODULE EngramConsensus -----------------------
EXTENDS Naturals, FiniteSets

(********************* INTERFACE & CONSTANTS ************************)
CONSTANTS 
    Nodes, 
    ResetTime, 
    Method, 
    Stake, 
    TotalStake,
    MaxBTCHeight

(********************* CONSENSUS LAYER VARIABLES (LAYER 2) ***********)
VARIABLES 
    tree,                 \* Buffer tree (AdoB)
    local_times,          \* Logical time of each node
    round,                \* Current consensus round
    rem_time,             \* Countdown timer
    fsm_state,            \* ABSTRACTION: Only 1 environment variable is needed
    h_btc_current,        \* Current Bitcoin height
    h_btc_anchored        \* Engram checkpoint height


vars == <<tree, local_times, round, rem_time, fsm_state, h_btc_current, h_btc_anchored>>

(********************* QUORUM OPTIMIZATION (MEMOIZATION) ****************)
RECURSIVE SumStakeOp(_)
SumStakeOp(Q) == IF Q = {} THEN 0 ELSE LET n == CHOOSE x \in Q : TRUE IN Stake[n] + SumStakeOp(Q \ {n})

SumStake[Q \in SUBSET Nodes] == SumStakeOp(Q)

\* Precompute the set of valid Quorums once
ValidQuorums == {q \in SUBSET Nodes : SumStake[q] * 3 > TotalStake * 2}

isSQuorum(Q) == Q \in ValidQuorums

(********************* INITIALIZATION ***********************************) 
Init == 
    /\ tree = {} 
    /\ local_times = [n \in Nodes |-> 0] 
    /\ round = 0        
    /\ rem_time = 0
    /\ fsm_state = "ANCHORED"
    /\ h_btc_current = 0
    /\ h_btc_anchored = 0


(********************* ABSTRACT PACEMAKER (LiDO) ******************) 
Elapse == 
    \* Block the countdown timer if the Leader has started Pull (E) or Invoke (M)
    /\ ~\E c \in tree : c.c_round = round /\ c.type \in {"E", "M"} 
    /\ rem_time > 0 
    /\ rem_time' = rem_time - 1 
    /\ UNCHANGED <<tree, local_times, round, fsm_state, h_btc_current, h_btc_anchored>>

TimeoutStartNext == 
    /\ rem_time = 0 
    /\ round' = round + 1 
    /\ rem_time' = ResetTime 
    /\ UNCHANGED <<tree, local_times, fsm_state, h_btc_current, h_btc_anchored>>

EarlyStartNext == 
    /\ \E c \in tree : c.type = "C" /\ c.c_round = round 
    /\ round' = round + 1 
    /\ rem_time' = ResetTime 
    /\ UNCHANGED <<tree, local_times, fsm_state, h_btc_current, h_btc_anchored>>


(********************* FORK-CHOICE & CAN_ELECT ********************)
\* Find the latest CCache block that node s supports.
active(tr, s) == 
    LET s_votes == {c \in tr : c.type = "C" /\ s \in c.voters}
    IN IF s_votes = {} THEN [type |-> "C", c_round |-> 0] 
       ELSE CHOOSE c \in s_votes : \A c2 \in s_votes : c.c_round >= c2.c_round

\* K-Deep Finality Rule
IsKDeep(c, k) == 
    /\ c.btc_height <= h_btc_anchored     \* 1. Điểm neo của block này chưa bị mất do Reorg
    /\ h_btc_current - c.btc_height >= k  \* 2. Độ sâu trên chuỗi Bitcoin đạt mức an toàn k


\* Simplify: The branch with the largest total stake is based on the number of voters.
IsMaxStakeBranch(c) == 
    \/ c.c_round = 0  \* Ngoại lệ luôn hợp lệ cho Genesis block
    \/ SumStake[c.voters] >= TotalStake \div 2

canElect(tr, c, Q, state_fsm) == 
    /\ c.type = "C" 
    /\ \A s \in Q : c.c_round >= active(tr, s).c_round
    /\ CASE state_fsm = "ANCHORED"   -> IsKDeep(c, 2) \* Use 2 instead of 6 for faster TLC performance.
         [] state_fsm = "SOVEREIGN"  -> IsMaxStakeBranch(c)
         [] state_fsm = "SUSPICIOUS" -> IsKDeep(c, 2)
         [] OTHER                    -> TRUE   


(********************* ADOB CORE OPERATIONS ***********************)
Pull(n) == 
    LET Q == CHOOSE q \in SUBSET Nodes : isSQuorum(q) 
        VirtualRoot == [type |-> "C", c_round |-> 0, voters |-> {}, btc_height |-> 0]
        ValidCaches == {c \in tree : c.type = "C"} \cup {VirtualRoot}
    IN \E Cmax \in ValidCaches: 
        /\ canElect(tree, Cmax, Q, fsm_state)
        /\ round > local_times[n]
        /\ local_times' = [s \in Nodes |-> IF s \in Q THEN round ELSE local_times[s]]
        /\ LET new_E_cache == [
               type       |-> "E", 
               c_round    |-> round, 
               caller     |-> n, 
               method     |-> "None", 
               voters     |-> Q, 
               btc_height |-> h_btc_current
           ]
           IN tree' = tree \cup {new_E_cache}
        /\ UNCHANGED <<round, rem_time, fsm_state, h_btc_current, h_btc_anchored>>


Invoke(n, m) == 
    /\ m \in Method 
    /\ \E c \in tree : 
        /\ c.type = "E" 
        /\ c.caller = n 
        /\ c.c_round = round 
    /\ LET new_M_cache == [
           type       |-> "M", 
           c_round    |-> round, 
           caller     |-> n, 
           method     |-> m, 
           voters     |-> {n}, 
           btc_height |-> h_btc_current
       ]
       IN tree' = tree \cup {new_M_cache} 
    /\ UNCHANGED <<local_times, round, rem_time, fsm_state, h_btc_current, h_btc_anchored>>


Push(n) == 
    LET Q == CHOOSE q \in SUBSET Nodes : isSQuorum(q) IN 
    /\ \E c \in tree : 
        /\ c.type = "M" 
        /\ c.caller = n 
        /\ c.c_round = round 
    /\ local_times' = [s \in Nodes |-> IF s \in Q THEN round + 1 ELSE local_times[s]] 
    /\ LET new_C_cache == [
           type       |-> "C", 
           c_round    |-> round, 
           caller     |-> n, 
           method     |-> "None", 
           voters     |-> Q, 
           btc_height |-> h_btc_current
       ]
       IN tree' = tree \cup {new_C_cache} 
    /\ UNCHANGED <<round, rem_time, fsm_state, h_btc_current, h_btc_anchored>>

(********************* OPTIMIZED ENVIRONMENT ******************)
UpdateEnv == 
    /\ h_btc_current < MaxBTCHeight 
    /\ h_btc_current' = h_btc_current + 1 
    \* Điểm neo có thể giữ nguyên (chưa chốt checkpoint) hoặc được cập nhật 
    /\ h_btc_anchored' \in {h_btc_anchored, h_btc_current'} 
    /\ fsm_state' = "ANCHORED" 
    /\ UNCHANGED <<tree, local_times, round, rem_time>>

\* Mô phỏng Bitcoin Reorg làm mất giao dịch OP_RETURN
BitcoinReorg == 
    /\ h_btc_anchored > 0
    \* Chiều cao thực của Bitcoin vẫn tiếp tục tăng hoặc giữ nguyên
    /\ h_btc_current' \in {h_btc_current, h_btc_current + 1}
    \* Giao dịch OP_RETURN bị mất, điểm neo bị đẩy lùi về một mốc trong quá khứ
    /\ \E lost_anchor \in 0..(h_btc_anchored - 1): 
           h_btc_anchored' = lost_anchor
    \* FSM kích hoạt ngắt mạch khẩn cấp do btc_gap tăng vọt
    /\ fsm_state' = "SOVEREIGN"
    /\ UNCHANGED <<tree, local_times, round, rem_time>>

(********************* NEXT STATE  ****************)
Next == 
    \/ Elapse 
    \/ TimeoutStartNext 
    \/ EarlyStartNext 
    \/ \E n \in Nodes : Pull(n) 
    \/ \E n \in Nodes, m \in Method : Invoke(n, m) 
    \/ \E n \in Nodes : Push(n) 
    \/ UpdateEnv
    \/ BitcoinReorg

(********************* FAIRNESS (LIVENESS) ************************)
Safety == Init /\ [][Next]_vars


Liveness == 
    /\ WF_vars(TimeoutStartNext)
    /\ WF_vars(EarlyStartNext)
    /\ WF_vars(UpdateEnv)
    /\ \A n \in Nodes : WF_vars(Pull(n)) /\ WF_vars(Push(n))
    /\ \A n \in Nodes, m \in Method : WF_vars(Invoke(n, m))


Spec == Safety /\ Liveness
=====================================================================