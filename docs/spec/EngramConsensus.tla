---- MODULE EngramConsensus ----
EXTENDS Naturals, FiniteSets

\* Các hằng số được định nghĩa từ bên ngoài (thông qua file .cfg)
CONSTANTS Nodes, Quorum, T_SOVEREIGN, MAX_GAP

VARIABLES node_state, msgs, env_gap

vars == <<node_state, msgs, env_gap>>

\* -----------------------------------------------------------------------------
\* KHÔNG GIAN BẢN TIN (MESSAGE SPACE)
\* -----------------------------------------------------------------------------
Messages == 
    [type: {"VOTE_SOVEREIGN", "VOTE_RECOVER"}, sender: Nodes] \cup
    [type: {"QC_SOVEREIGN", "QC_RECOVER"}]

\* -----------------------------------------------------------------------------
\* KHỞI TẠO HỆ THỐNG
\* -----------------------------------------------------------------------------
Init == 
    /\ node_state = [n \in Nodes |-> "ANCHORED"]
    /\ msgs = {}
    /\ env_gap = 0

\* -----------------------------------------------------------------------------
\* CÁC HÀNH ĐỘNG (ACTIONS)
\* -----------------------------------------------------------------------------
\* 1. Môi trường thay đổi (Mạng đứt gãy hoặc phục hồi)
EnvUpdate == 
    /\ env_gap' \in 0..MAX_GAP
    /\ UNCHANGED <<node_state, msgs>>

\* 2. Node phát hiện lỗi và gửi Vote yêu cầu chuyển sang SOVEREIGN
SendVoteSovereign(n) == 
    /\ node_state[n] \in {"ANCHORED", "SUSPICIOUS"}
    /\ env_gap >= T_SOVEREIGN
    /\ msgs' = msgs \cup {[type |-> "VOTE_SOVEREIGN", sender |-> n]}
    /\ UNCHANGED <<node_state, env_gap>>

\* 3. Mạng tổng hợp đủ Vote thành Quorum Certificate (QC)
AggregateQCSovereign == 
    /\ \E Q \in SUBSET Nodes : 
        /\ Cardinality(Q) >= Quorum
        /\ \A n \in Q : [type |-> "VOTE_SOVEREIGN", sender |-> n] \in msgs
    /\ msgs' = msgs \cup {[type |-> "QC_SOVEREIGN"]}
    /\ UNCHANGED <<node_state, env_gap>>

\* 4. Node nhận được QC và chính thức chuyển trạng thái
TransitionToSovereign(n) == 
    /\ [type |-> "QC_SOVEREIGN"] \in msgs
    /\ node_state[n] /= "SOVEREIGN"
    /\ node_state' = [node_state EXCEPT ![n] = "SOVEREIGN"]
    /\ UNCHANGED <<msgs, env_gap>>

\* -----------------------------------------------------------------------------
\* ĐÓNG GÓI TRẠNG THÁI (NEXT & FAIRNESS)
\* -----------------------------------------------------------------------------
Next == 
    \/ EnvUpdate
    \/ \E n \in Nodes : SendVoteSovereign(n) \/ TransitionToSovereign(n)
    \/ AggregateQCSovereign

Fairness == 
    /\ WF_vars(AggregateQCSovereign)
    /\ \A n \in Nodes : WF_vars(SendVoteSovereign(n)) /\ WF_vars(TransitionToSovereign(n))

Spec == Init /\ [][Next]_vars /\ Fairness

\* -----------------------------------------------------------------------------
\* THUỘC TÍNH KIỂM CHỨNG (PROPERTIES)
\* -----------------------------------------------------------------------------
TypeOK == 
    /\ node_state \in [Nodes -> {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}]
    /\ msgs \subseteq Messages

\* Safety: Không một node nào được phép nhảy sang SOVEREIGN nếu chưa có QC (bằng chứng đồng thuận)
ConsensusSafety == 
    \A n \in Nodes : (node_state[n] = "SOVEREIGN") => ([type |-> "QC_SOVEREIGN"] \in msgs)

\* Liveness: Nếu mạng đứt gãy đủ lâu, cuối cùng TẤT CẢ các node đều phải sang được SOVEREIGN
ConsensusLiveness == 
    (env_gap >= T_SOVEREIGN) ~> (\A n \in Nodes : node_state[n] = "SOVEREIGN" \/ env_gap < T_SOVEREIGN)
================================