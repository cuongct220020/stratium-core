---------------- MODULE MC_ConsensusSafety ----------------
EXTENDS EngramConsensus, TLC

CONSTANTS n1, n2, n3, n4, tx1, tx2


\* Bounding: Maximum of 3 laps
StateSpaceLimit == 
    /\ round <= 3
    /\ Cardinality(tree) <= 5

\* Optimize Symmetry for Safety (Rất quan trọng)
SymmetryPerms == Permutations(Nodes)

MC_Nodes == {n1, n2, n3, n4}
MC_Method == {tx1, tx2}

MC_Stake == [n \in Nodes |-> 10]
===========================================================