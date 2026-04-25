---------------- MODULE MC_ServerRefinement ---------------- 
EXTENDS EngramServer, TLC, Sequences

CONSTANTS n1, n2, n3, n4, tx1

\* --- 1. QUY MÔ MẠNG LƯỚI (START SMALL) ---
MC_Nodes == {n1, n2, n3, n4} 
MC_Method == {tx1}  
MC_Stake == [n \in MC_Nodes |-> 10] 
MC_Faulty == {n4}   
MC_Corr == MC_Nodes \ MC_Faulty 

\* --- 2. CẤU HÌNH LEADER LUÂN PHIÊN (HẰNG SỐ CHUẨN) ---
MC_NodeSeq == <<n1, n2, n3, n4>>
MC_Proposer == [r \in 0..5 |-> MC_NodeSeq[(r % 4) + 1]]

\* --- 3. TỐI ƯU HÓA HỆ SỐ PHÂN NHÁNH (CUSTOM NEXT) ---
\* Ghi đè NextServer để "khóa cứng" cụm biến FSM, dập tắt bùng nổ tổ hợp.
MC_Next == 
    /\ NextServer
    /\ fsmVars' = fsmVars


\* --- 4. GIỚI HẠN KHÔNG GIAN (PRUNING CONSTRAINT) ---
StateSpaceLimit == 
    /\ \A n \in MC_Corr : round[n] <= 1  \* BẮT BUỘC duyệt tới Vòng 1 để test Leader Rotation
    /\ realTime <= 2                     \* BẮT BUỘC mở rộng thời gian để Tendermint kịp Timeout

\* --- 5. THUỘC TÍNH KIỂM CHỨNG ÁNH XẠ (REFINEMENT CHECK) ---
RefinementSafety == AbstractConsensus!Safety
=============================================================================