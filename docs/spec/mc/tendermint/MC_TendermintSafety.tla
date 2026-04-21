---------------- MODULE MC_TendermintSafety ----------------
EXTENDS EngramTendermint, TLC

\* KHAI BÁO TẤT CẢ MODEL VALUES ĐỂ TLC NHẬN DIỆN
CONSTANTS p1, p2, p3, p4, v1, v3

\* Giả lập hàm chọn Leader luân phiên
MC_Proposer == [r \in 0..MaxRound |-> IF r % 2 = 0 THEN p1 ELSE p2]

\* Khởi tạo state gốc của Tendermint VÀ giả lập môi trường FSM ổn định
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

\* Hành động kết thúc mô phỏng hợp lệ
Termination == 
    /\ \/ \A p \in Corr : step[p] = "DECIDED"
       \/ realTime >= MaxTimestamp
       \/ \E p \in Corr : round[p] >= 1
    /\ UNCHANGED <<coreVars, temporalVars, invariantVars, fsmVars>>
    /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, evidence, receivedTimelyProposal, inspectedProposal>>
    /\ action' = "Termination"


\* Trong bài test độc lập, FSM không thay đổi, chỉ có Tendermint chạy
MC_Next == Next \/ Termination

\* 1. KHAI BÁO TÍNH ĐỐI XỨNG (SYMMETRY)
Perms == Permutations(Corr)

\* 2. GIỚI HẠN KHÔNG GIAN TRẠNG THÁI (STATE CONSTRAINT)
StateConstraint == 
    /\ realTime <= 2 
    /\ \A p \in Corr: round[p] <= 1
============================================================
