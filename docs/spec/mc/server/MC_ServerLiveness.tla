---------------- MODULE MC_ServerLiveness ----------------
EXTENDS EngramServer, TLC

CONSTANTS n1, n2, n3, tx1

\* Bounding nhỏ hơn để tìm Liveness không bị treo máy
StateSpaceLimit == \A n \in Nodes : server_rounds[n] <= 2

RefinementProperty == Consensus!SpecConsensus
==========================================================