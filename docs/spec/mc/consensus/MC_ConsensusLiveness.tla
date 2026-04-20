---------------- MODULE MC_ConsensusLiveness ----------------
EXTENDS EngramConsensus, TLC

CONSTANTS n1, n2, n3, tx1


MC_Nodes == {n1, n2, n3}
MC_Method == {tx1}
MC_Stake == [n \in MC_Nodes |-> 10]


\* State space limitations (Note: state blocking can cause false liveness errors in the final loop)
StateSpaceLimit == 
    /\ round <= 3
    /\ Cardinality(tree) <= 7


\* Liveness 1: The system always generates new commented blocks (CCache).
ConsensusProgress == []<>(\E c \in tree : c.type = "C")


\* Liveness 2: If a proposal (M) is submitted, the network will eventually lock in a Commitment.
MethodCommitted == \A n \in Nodes, m \in Method :
    (\E c \in tree : c.type = "M" /\ c.caller = n /\ c.method = m) 
    ~> (\E c \in tree : c.type = "C")
=================================================================