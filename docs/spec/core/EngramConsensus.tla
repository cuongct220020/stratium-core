----------------------- MODULE EngramConsensus -----------------------
EXTENDS Naturals, FiniteSets

(********************* GIAO DIỆN & HẰNG SỐ ************************)
CONSTANTS Nodes, ResetTime, Method, Stake, TotalStake

(********************* BIẾN CỦA TẦNG CONSENSUS (TẦNG 2) ***********)
VARIABLES 
    tree,                 \* Cây bộ đệm (AdoB
    local_times,          \* Thời gian logic của từng node
    round,                \* Vòng đồng thuận hiện tại
    rem_time,             \* Thời gian đếm ngược
    fsm_state             \* TRỪU TƯỢNG HÓA: Chỉ cần 1 biến môi trường

vars == <<tree, local_times, round, rem_time, fsm_state>>

(********************* TỐI ƯU QUORUM (MEMOIZATION) ****************)
RECURSIVE SumStakeOp(_)
SumStakeOp(Q) == IF Q = {} THEN 0 ELSE LET n == CHOOSE x \in Q : TRUE IN Stake[n] + SumStakeOp(Q \ {n})

SumStake[Q \in SUBSET Nodes] == SumStakeOp(Q)

\* Tính sẵn một lần tập hợp các Quorum hợp lệ
ValidQuorums == {q \in SUBSET Nodes : SumStake[q] * 3 > TotalStake * 2}

isSQuorum(Q) == Q \in ValidQuorums

(********************* KHỞI TẠO ***********************************)
Init == 
    /\ tree = {}
    /\ local_times = [n \in Nodes |-> 0]
    /\ round = 1
    /\ rem_time = ResetTime
    /\ fsm_state = "ANCHORED"

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

(********************* ADOB CORE OPERATIONS ***********************)
Pull(n) == 
    LET Q == CHOOSE q \in SUBSET Nodes : isSQuorum(q) IN
        /\ round > local_times[n]
        /\ local_times' = [s \in Nodes |-> IF s \in Q THEN round ELSE local_times[s]]
        /\ tree' = tree \cup {[type |-> "E", round |-> round, caller |-> n, method |-> "None", voters |-> Q]}
        /\ UNCHANGED <<round, rem_time, fsm_state>>

Invoke(n, m) == 
    /\ m \in Method
    /\ \E c \in tree : c.type = "E" /\ c.caller = n /\ c.round = round
    /\ tree' = tree \cup {[type |-> "M", round |-> round, caller |-> n, method |-> m, voters |-> {n}]}
    /\ UNCHANGED <<local_times, round, rem_time, fsm_state>>

Push(n) == 
    LET Q == CHOOSE q \in SUBSET Nodes : isSQuorum(q) IN 
        /\ \E c \in tree : c.type = "M" /\ c.caller = n /\ c.round = round
        /\ local_times' = [s \in Nodes |-> IF s \in Q THEN round + 1 ELSE local_times[s]]
        /\ tree' = tree \cup {[type |-> "C", round |-> round, caller |-> n, method |-> "None", voters |-> Q]}
        /\ UNCHANGED <<round, rem_time, fsm_state>>

(********************* MÔI TRƯỜNG ĐỘNG ĐÃ TỐI ƯU ******************)
UpdateEnv == 
    /\ rem_time = 0  \* CHỈ ĐỔI TRẠNG THÁI KHI HẾT GIỜ (Triệt tiêu bùng nổ)
    /\ fsm_state' \in {"ANCHORED", "SOVEREIGN"}
    /\ UNCHANGED <<tree, local_times, round, rem_time>>

(********************* TRẠNG THÁI TIẾP THEO (NEXT) ****************)
Next == 
    \/ Elapse
    \/ TimeoutStartNext
    \/ EarlyStartNext
    \/ \E n \in Nodes : Pull(n)
    \/ \E n \in Nodes, m \in Method : Invoke(n, m)
    \/ \E n \in Nodes : Push(n)
    \/ UpdateEnv

(********************* FAIRNESS (LIVENESS) ************************)
Liveness == 
    /\ WF_vars(TimeoutStartNext)
    /\ WF_vars(EarlyStartNext)
    /\ \A n \in Nodes : WF_vars(Pull(n)) /\ WF_vars(Push(n))
    /\ \A n \in Nodes, m \in Method : WF_vars(Invoke(n, m))

Spec == Init /\ [][Next]_vars /\ Liveness
=====================================================================