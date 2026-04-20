----------------------- MODULE EngramConsensus -----------------------
EXTENDS Naturals, FiniteSets

(********************* INTERFACE & CONSTANTS ************************)
CONSTANTS 
    Nodes, 
    ResetTime, 
    Method, 
    Stake, 
    TotalStake

(********************* CONSENSUS LAYER VARIABLES (LAYER 2) ***********)
VARIABLES 
    tree,                 \* Buffer tree (AdoB)
    local_times,          \* Logical time of each node
    round,                \* Current consensus round
    rem_time,             \* Countdown timer
    fsm_state,            \* ABSTRACTION: Only 1 environment variable is needed
    h_btc_current         \* Current Bitcoin height


vars == <<tree, local_times, round, rem_time, fsm_state, h_btc_current>>

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

(********************* ABSTRACT PACEMAKER (LiDO) ******************)
Elapse == 
    /\ rem_time > 0
    /\ rem_time' = rem_time - 1
    /\ UNCHANGED <<tree, local_times, round, fsm_state>>

TimeoutStartNext == 
    /\ rem_time = 0
    /\ round' = round + 1
    /\ rem_time' = ResetTime
    /\ UNCHANGED <<tree, local_times, fsm_state>>

EarlyStartNext ==
    /\ \E c \in tree : c.type = "C" /\ c.round = round
    /\ round' = round + 1
    /\ rem_time' = ResetTime
    /\ UNCHANGED <<tree, local_times, fsm_state>>


(********************* FORK-CHOICE & CAN_ELECT ********************)
\* Find the latest CCache block that node s supports.
active(tr, s) == 
    LET s_votes == {c \in tr : c.type = "C" /\ s \in c.voters}
    IN IF s_votes = {} THEN [type |-> "C", round |-> 0] 
       ELSE CHOOSE c \in s_votes : \A c2 \in s_votes : c.round >= c2.round

\* K-Deep Finality Rule
IsKDeep(c, k) == h_btc_current - c.btc_height >= k

\* Simplify: The branch with the largest total stake is based on the number of voters.
IsMaxStakeBranch(c) == SumStake[c.voters] >= TotalStake \div 2 

canElect(tr, c, Q, state_fsm) == 
    /\ c.type = "C" 
    /\ \A s \in Q : c.round >= active(tr, s).round
    /\ CASE state_fsm = "ANCHORED"   -> IsKDeep(c, 2) \* Use 2 instead of 6 for faster TLC performance.
         [] state_fsm = "SOVEREIGN"  -> IsMaxStakeBranch(c)
         [] state_fsm = "SUSPICIOUS" -> IsKDeep(c, 2)
         [] OTHER                    -> TRUE   

(********************* ADOB CORE OPERATIONS ***********************)
Pull(n) == 
    LET Q == CHOOSE q \in SUBSET Nodes : isSQuorum(q) IN
    \E Cmax \in {c \in tree : c.type = "C"} \cup {[type |-> "C", round |-> 0, voters |-> {}, btc_height |-> 0]}: 
        /\ canElect(tree, Cmax, Q, fsm_state)
        /\ round > local_times[n]
        /\ local_times' = [s \in Nodes |-> IF s \in Q THEN round ELSE local_times[s]]
        /\ tree' = tree \cup {[type |-> "E", round |-> round, caller |-> n, method |-> "None", voters |-> Q, btc_height |-> h_btc_current]}
        /\ UNCHANGED <<round, rem_time, fsm_state, h_btc_current>>

Invoke(n, m) == 
    /\ m \in Method
    /\ \E c \in tree : c.type = "E" /\ c.caller = n /\ c.round = round
    /\ tree' = tree \cup {[type |-> "M", round |-> round, caller |-> n, method |-> m, voters |-> {n}, btc_height |-> h_btc_current]}
    /\ UNCHANGED <<local_times, round, rem_time, fsm_state, h_btc_current>>

Push(n) == 
    LET Q == CHOOSE q \in SUBSET Nodes : isSQuorum(q) IN 
        /\ \E c \in tree : c.type = "M" /\ c.caller = n /\ c.round = round
        /\ local_times' = [s \in Nodes |-> IF s \in Q THEN round + 1 ELSE local_times[s]]
        /\ tree' = tree \cup {[type |-> "C", round |-> round, caller |-> n, method |-> "None", voters |-> Q, btc_height |-> h_btc_current]}
        /\ UNCHANGED <<round, rem_time, fsm_state, h_btc_current>>

(********************* OPTIMIZED ENVIRONMENT ******************)
UpdateEnv == 
    /\ rem_time = 0  \* ONLY CHANGE STATE ON TIMEOUT (Suppress state explosion)
    /\ fsm_state' \in {"ANCHORED", "SOVEREIGN"}
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

(********************* FAIRNESS (LIVENESS) ************************)
Safety == Init /\ [][Next]_vars


Fairness == 
    /\ WF_vars(TimeoutStartNext)
    /\ WF_vars(EarlyStartNext)
    /\ \A n \in Nodes : WF_vars(Pull(n)) /\ WF_vars(Push(n))
    /\ \A n \in Nodes, m \in Method : WF_vars(Invoke(n, m))


Spec == Safety /\ Fairness
=====================================================================