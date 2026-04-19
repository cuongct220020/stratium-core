---------------- MODULE MC_ServerSafety ----------------
EXTENDS EngramServer, TLC, Permutations

CONSTANTS n1, n2, n3, n4, tx1, tx2

\* Bounding: Chỉ cho phép server chạy tối đa 3 vòng
StateSpaceLimit == \A n \in Nodes : server_rounds[n] <= 3

\* Symmetry Breaking để giảm không gian trạng thái n! lần
SymmetryPerms == Permutations(Nodes)

\* Thuộc tính chứng minh Tầng 3 tuân thủ Tầng 2
RefinementProperty == Consensus!SpecConsensus
========================================================
