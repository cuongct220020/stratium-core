--------------------------- MODULE EngramConsensus ---------------------------
EXTENDS Naturals, FiniteSets

(********************* INTERFACE & CONSTANTS ************************)
CONSTANTS 
    Nodes,
    Method,
    Stake,
    RESET_TIME,
    TOTAL_STAKE,
    MAX_BTC_HEIGHT,
    K_DEEP_FINALITY

(********************* CONSENSUS LAYER VARIABLES ***********)
VARIABLES 
    tree,                 \* Buffer tree (AdoB)
    local_times,          \* Logical time of each node
    round,                \* Current consensus round
    rem_time,             \* Countdown timer
    fsm_state,            \* FSM state
    h_btc_current,        \* Current Bitcoin height
    h_btc_anchored        \* Engram checkpoint height


vars == <<tree, local_times, round, rem_time, 
            fsm_state, h_btc_current, h_btc_anchored>>

(********************* QUORUM OPTIMIZATION (MEMOIZATION) ****************)
RECURSIVE SumStakeOp(_)
SumStakeOp(Q) == IF Q = {} THEN 0 ELSE LET n == CHOOSE x \in Q : TRUE IN Stake[n] + SumStakeOp(Q \ {n})

SumStake[Q \in SUBSET Nodes] == SumStakeOp(Q)

\* Precompute the set of valid Quorums once
ValidQuorums == {q \in SUBSET Nodes : SumStake[q] * 3 > TOTAL_STAKE * 2}

IsSQuorum(Q) == Q \in ValidQuorums

(********************* INITIALIZATION ***********************************) 
Init == 
    /\ tree = {} 
    /\ local_times = [n \in Nodes |-> 0] 
    /\ round = 1        
    /\ rem_time = RESET_TIME
    /\ fsm_state = "ANCHORED"
    /\ h_btc_current = K_DEEP_FINALITY
    /\ h_btc_anchored = K_DEEP_FINALITY


(********************* ABSTRACT PACEMAKER (LiDO) ******************) 
Elapse == 
    \* Block the countdown timer if the Leader has started Pull (E) or Invoke (M)
    /\ ~\E c \in tree : c.cert_round = round /\ c.type \in {"E", "M"} 
    /\ rem_time > 0 
    /\ rem_time' = rem_time - 1 
    /\ UNCHANGED <<tree, round, local_times>>
    /\ UNCHANGED <<fsm_state, h_btc_current, h_btc_anchored>>

TimeoutStartNext == 
    /\ rem_time = 0 
    /\ round' = round + 1 
    /\ rem_time' = RESET_TIME 
    /\ UNCHANGED <<tree, local_times>>
    /\ UNCHANGED <<fsm_state, h_btc_current, h_btc_anchored>>

EarlyStartNext == 
    /\ \E c \in tree : c.type = "C" /\ c.cert_round = round 
    /\ round' = round + 1 
    /\ rem_time' = RESET_TIME 
    /\ UNCHANGED <<tree, local_times>>
    /\ UNCHANGED <<fsm_state, h_btc_current, h_btc_anchored>>


(********************* FORK-CHOICE & CAN_ELECT ********************)
\* Find the latest CCache block that node s supports.
Active(tr, s) == 
    LET s_votes == {c \in tr : c.type = "C" /\ s \in c.voters}
    IN IF s_votes = {} THEN [type |-> "C", cert_round |-> 0] 
       ELSE CHOOSE c \in s_votes : \A c2 \in s_votes : c.cert_round >= c2.cert_round

\* K-Deep Finality Rule
IsKDeep(c, k) == 
    /\ c.btc_anchored <= h_btc_anchored     \* The anchor point of this block has not been lost due to Reorg.
    /\ h_btc_current - c.btc_anchored >= k  \* Bitcoin's on-chain depth has reached a safe level.


\* Simplify: The branch with the largest total stake is based on the number of voters.
IsMaxStakeBranch(c) == 
    \/ c.cert_round = 0    \* Exceptions are always valid for Genesis blocks
    \/ SumStake[c.voters] >= TOTAL_STAKE \div 2


CanElect(tr, c, Q, state_fsm) == 
    /\ c.type = "C" 
    /\ \A s \in Q : c.cert_round >= Active(tr, s).cert_round
    /\ CASE state_fsm = "ANCHORED"   -> IsKDeep(c, K_DEEP_FINALITY)
         [] state_fsm = "SUSPICIOUS" -> IsKDeep(c, K_DEEP_FINALITY)
         [] state_fsm = "SOVEREIGN"  -> IsMaxStakeBranch(c)
         [] OTHER                    -> TRUE   


(********************* ADOB CORE OPERATIONS ***********************)
Pull(n) == 
    LET Q == CHOOSE q \in SUBSET Nodes : IsSQuorum(q)
        VirtualRoot == [type |-> "C", cert_round |-> 0, voters |-> {}, btc_anchored |-> 0]
        ValidCaches == {c \in tree : c.type = "C"} \cup {VirtualRoot}
    IN \E Cmax \in ValidCaches:
       /\ CanElect(tree, Cmax, Q, fsm_state)
       /\ round > local_times[n]
       /\ local_times' = [s \in Nodes |-> IF s \in Q THEN round ELSE local_times[s]]
       /\ \E chosen_anchor \in h_btc_anchored..h_btc_current :
           LET new_E_cache == [ 
               type             |-> "E",
               cert_round       |-> round,
               caller           |-> n,
               method           |-> "None",
               voters           |-> Q,
               btc_anchored     |-> chosen_anchor 
           ]
           IN tree' = tree \cup {new_E_cache}
       /\ UNCHANGED <<round, rem_time>>
       /\ UNCHANGED <<fsm_state, h_btc_current, h_btc_anchored>>


Invoke(n, m) == 
    /\ m \in Method
    /\ \E c \in tree : 
       /\ c.type = "E"
       /\ c.caller = n
       /\ c.cert_round = round
       /\ \E chosen_anchor \in h_btc_anchored..h_btc_current :
           LET new_M_cache == [ 
               type             |-> "M",
               cert_round       |-> round,
               caller           |-> n,
               method           |-> m,
               voters           |-> {n},
               btc_anchored     |-> chosen_anchor 
           ]
           IN tree' = tree \cup {new_M_cache}
    /\ UNCHANGED <<local_times, round, rem_time>>
    /\ UNCHANGED <<fsm_state, h_btc_current, h_btc_anchored>>


Push(n) == 
    /\ \E c \in tree : 
       /\ c.type = "M"
       /\ c.caller = n
       /\ c.cert_round = round
       /\ \E chosen_anchor \in h_btc_anchored..h_btc_current :
           LET new_C_cache == [ 
               type             |-> "C",
               cert_round       |-> round,
               caller           |-> n,
               voters           |-> {n},
               btc_anchored     |-> chosen_anchor 
           ]
           IN tree' = tree \cup {new_C_cache}
    /\ UNCHANGED <<local_times, round, rem_time>>
    /\ UNCHANGED <<fsm_state, h_btc_current, h_btc_anchored>>

(********************* OPTIMIZED ENVIRONMENT ******************)
UpdateEnv == 
    /\ h_btc_current' \in {h_btc_current, h_btc_current + 1}
    /\ h_btc_anchored' \in h_btc_anchored..h_btc_current'   \* Allow h_btc_anchored to catch up comfortably
    /\ fsm_state' = fsm_state  
    /\ UNCHANGED <<tree, local_times, round, rem_time>>


FSMStateChange ==
    /\ fsm_state' \in {"ANCHORED", "SOVEREIGN"}
    /\ fsm_state' /= fsm_state
    /\ UNCHANGED <<tree, local_times, round, rem_time>>
    /\ UNCHANGED <<h_btc_current, h_btc_anchored>>


\* Bitcoin Reorg simulation loses OP_RETURN transaction
BitcoinReorg == 
    /\ h_btc_anchored > 0  
    /\ h_btc_current' \in {h_btc_current, h_btc_current + 1} 
    /\ \E lost_anchor \in 0..(h_btc_anchored - 1): h_btc_anchored' = lost_anchor 
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
    \/ FSMStateChange
    \/ BitcoinReorg

(********************* SAFETY & FAIRNESS (LIVENESS) ************************)
Safety == Init /\ [][Next]_vars


Liveness == 
    /\ WF_vars(TimeoutStartNext)
    /\ WF_vars(EarlyStartNext)
    /\ WF_vars(UpdateEnv)
    /\ \A n \in Nodes : 
        /\ WF_vars(Pull(n))
        /\ WF_vars(Push(n))
    /\ \A n \in Nodes, m \in Method : WF_vars(Invoke(n, m))


Spec == Safety /\ Liveness
=====================================================================