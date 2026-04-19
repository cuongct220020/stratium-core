---------------- MODULE MC_ConsensusLiveness ----------------
EXTENDS EngramConsensus, TLC

CONSTANTS n1, n2, n3, tx1


MC_Nodes == {n1, n2, n3}
MC_Method == {tx1}
MC_Stake == [n \in MC_Nodes |-> 10]

\* Liveness 1: Hệ thống luôn luôn tạo ra các block được Commit (CCache) mới
ConsensusProgress == []<>(\E c \in tree : c.type = "C")

\* Liveness 2: Nếu một đề xuất (M) được đưa ra, mạng lưới cuối cùng sẽ chốt một Commit
MethodCommitted == \A n \in Nodes, m \in Method :
    (\E c \in tree : c.type = "M" /\ c.caller = n /\ c.method = m) 
    ~> (\E c \in tree : c.type = "C")

\* Giới hạn không gian trạng thái (Lưu ý: chặn trạng thái có thể gây lỗi liveness giả ở vòng cuối)
StateSpaceLimit == 
    /\ round <= 3
    /\ Cardinality(tree) <= 7

=================================================================