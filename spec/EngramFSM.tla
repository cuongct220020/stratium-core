--------------------------- MODULE EngramFSM ---------------------------
EXTENDS Integers, Sequences

CONSTANTS T1, T2 \* Thresholds for Suspicious and Sovereign states (T1 < T2)
VARIABLES state, gap, connection

States == {"ANCHORED", "SUSPICIOUS", "SOVEREIGN"}

Init ==
    /\ state = "ANCHORED"
    /\ gap = 0
    /\ connection = "STABLE"

NormalToSuspicious ==
    /\ state = "ANCHORED"
    /\ gap >= T1
    /\ gap < T2
    /\ state' = "SUSPICIOUS"
    /\ UNCHANGED <<gap, connection>>

SuspiciousToSovereign ==
    /\ state = "SUSPICIOUS"
    /\ gap >= T2
    /\ state' = "SOVEREIGN"
    /\ UNCHANGED <<gap, connection>>

SovereignToAnchored ==
    /\ state = "SOVEREIGN"
    /\ connection = "STABLE"
    /\ gap < T1
    /\ state' = "ANCHORED"
    /\ UNCHANGED <<gap, connection>>

\* Invariant: Ensure the system can always recover to Anchored (Liveness)
Liveness == WF_vars(SovereignToAnchored)

\* Safety: Ensure the FSM remains in valid states
TypeOK == state \in States
=============================================================================