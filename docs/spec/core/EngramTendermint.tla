-------------------- MODULE EngramTendermint ---------------------------
EXTENDS Integers, FiniteSets, EngramVars, EngramFSM

(***************************************************************************)
(* TODO [FUTURE WORK - APPENDIX]: PIPELINED TENDERMINT (PHASE MERGING)     *)
(* Goal: Block time < 2s (Optimistic Pre-Confirmations) via LiDO Appx D.   *)
(*                                                                         *)
(* Implementation Steps:                                                   *)
(* 1. REMOVE PRECOMMIT: Delete `msgsPrecommit` and related actions.        *)
(* 2. OVERLOAD PREVOTE: A `PREVOTE` referencing `r-1` acts as its commit.  *)
(* 3. DELEGATE COMMIT: Leader[r] delegates block commit to Proposer[r+1].  *)
(* 4. UPDATE LIVENESS: Committing now needs 2 consecutive honest leaders.  *)
(***************************************************************************)


(********************* PROTOCOL PARAMETERS **********************************)
\* General protocol parameters
CONSTANTS
    \* @type: Set(PROCESS);
    Corr,          \* the set of correct processes 
    \* @type: Set(PROCESS);
    Faulty,        \* the set of Byzantine processes, may be empty
    \* @type: Int;  
    N,             \* the total number of processes: correct, defective, and Byzantine
    \* @type: Int;  
    T,             \* an upper bound on the number of Byzantine processes
    \* @type: ROUND;    
    MaxRound,      \* the maximal round number
    \* @type: ROUND -> PROCESS;
    Proposer       \* the proposer function from Rounds to AllProcs


\* Time-related parameters
CONSTANTS
    \* @type: TIME;
    MaxTimestamp,  \* the maximal value of the clock tick
    \* @type: TIME;
    MinTimestamp,  \* the minimal value of the clock tick
    \* @type: TIME;
    Delay,         \* message delay
    \* @type: TIME;
    Precision,     \* clock precision: the maximal difference between two local clocks
    \* @type: TIME;
    TimeoutDuration


\* peripheral-related parameters
CONSTANTS
    \* @type: Int;
    MaxBTCHeight,
    \* @type: Int;
    MaxEngramHeight,
    \* @type: Int;
    MaxIgnoreRounds


ASSUME(N = Cardinality(Corr \union Faulty))

(*************************** BASIC DEFINITIONS ************************************)
\* @type: Set(PROCESS);
AllProcs == Corr \union Faulty      \* the set of all processes

\* @type: Set(ROUND);
Rounds == 0..MaxRound               \* the set of potential rounds
\* @type: ROUND;
NilRound == -1   \* a special value to denote a nil round, outside of Rounds
\* @type: Set(ROUND);
RoundsOrNil == Rounds \union {NilRound}

\* @type: Set(TIME);
Timestamps == 0..MaxTimestamp       \* the set of clock ticks
\* @type: TIME;
NilTimestamp == -1 \* a special value to denote a nil timestamp, outside of Ticks
\* @type: Set(TIME);
TimestampsOrNil == Timestamps \union {NilTimestamp}

\* @type: Set(STRING);
Values == {"TX_NORMAL", "TX_WITHDRAWAL"} 
\* @type: Set(STRING);
ValidValues == Values 
\* @type: STRING;
NilValue == "NIL_TX"
\* @type: SET(STRING)
ValuesOrNil == Values \union {NilValue}


(************************* ENGRAM EXTERNAL ENTITIES *************************)
\* @type: Set(STR);
FSM_State == {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}
\* @type: STR
NilFSM_State == "NONE"
\* @type: Set(STR);
FSM_StateOrNil == FSM_State \union NilFSM_State

\* @type: Set(Int);
BTC_Heights == 0..MaxBTCHeight
\* @type: Int;
NilBTCHeight == -1
\* @type: Set(Int);
BTC_HeightsOrNil == BTC_Heights \union {NilBTCHeight}

\* @type: Set(Int);
DA_Heights == 0..MaxEngramHeight
\* @type: Set(DA_RECEIPT);
DA_Receipts == [
    blockHeight: DA_Heights,   \* Height of published block N-k
    attestation: BOOLEAN       \* Verification from Blobstream
]
\* @type: DA_RECEIPT;
NilDA_Receipt == [
    blockHeight  |-> -1,
    attestation  |-> FALSE 
]

\* @type: Set(DA_RECEIPT);
DA_ReceiptsOrNil == DA_Heights \union NilDA_Receipt

(*********************** PROPOSAL & DECISION STRUCTURE **********************)
\* @type: Set(PROPOSAL);
Proposals == [
    value: ValuesOrNil,
    timestamp: TimestampsOrNil,
    round: RoundsOrNil,
    fsm_state: FSM_StateOrNil,
    da_receipt: DA_ReceiptsOrNil,
    btc_anchored: BTC_HeightsOrNil,
    zk_proof_ref: BOOLEAN 
]
\* @type: PROPOSAL;
NilProposal == [ 
    value           |-> NilValue, 
    timestamp       |-> NilTimestamp, 
    round           |-> NilRound, 
    fsm_state       |-> NilFSM_State, 
    da_receipt      |-> NilDA_Receipt, 
    btc_anchored    |-> NilBTCHeight,
    zk_proof_ref    |-> FALSE   
]
\* @type: Set(DECISION);
Decisions == [
    prop: Proposals,
    round: Rounds  \* The round where the decision is made
]
\* @type: DECISION;
NilDecision == [
    prop  |-> NilProposal,
    round |-> NilRound
]

(********************* BASIC HELPERS & THRESHOLDS ******************************)
\* a value hash is modeled as identity
\* @type: (t) => t;
Id(v) == v

\* the two thresholds that are used in the algorithm
\* @type: Int;
THRESHOLD1 == T + 1     \* at least one process is not faulty
\* @type: Int;
THRESHOLD2 == 2 * T + 1 \* a quorum when having N > 3 * T

\* @type: (TIME, TIME) => TIME;
Min2(a,b) == IF a <= b THEN a ELSE b
\* @type: (Set(TIME)) => TIME;
\* Min(S) == FoldSet( Min2, MaxTimestamp, S )
Min(S) == CHOOSE x \in S : \A y \in S : x <= y

\* @type: (TIME, TIME) => TIME;
Max2(a,b) == IF a >= b THEN a ELSE b
\* @type: (Set(TIME)) => TIME;
\* Max(S) == FoldSet( Max2, NilTimestamp, S )
Max(S) == CHOOSE x \in S : \A y \in S : y <= x

\* @type: (Set(MESSAGE)) => Int;
\* Card(S) == 
\*   LET 
\*     \* @type: (Int, MESSAGE) => Int;
\*     PlusOne(i, m) == i + 1
\*   IN FoldSet( PlusOne, 0, S )
Card(S) == Cardinality(S)


(********************* TIME UTILITIES ******************************)
\* Time validity check. If we want MaxTimestamp = \infty, set ValidTime(t) == TRUE
\* @type: (TIME) => Bool;
ValidTime(t) == t < MaxTimestamp


\* @type: (TIME, TIME) => Bool;
IsTimely(processTime, messageTime) ==
  /\ processTime >= messageTime - Precision
  /\ processTime <= messageTime + Precision + Delay

(********************* TRANSACTION & ZK-PROOF HELPERS ******************************)
\* Helper to identify withdrawal transactions
\* @type: (STRING) => Bool;
ContainsWithdrawal(propVal) == propVal = "TX_WITHDRAWAL"

\* Black-box verification: O(1) time complexity simulation for ZK-Proofs
\* @type: (PROPOSAL) => Bool;
VerifyZkProof(prop) == 
    /\ prop.zk_proof_ref = TRUE                         \* Leader claims proof exists
    /\ prop.da_receipt.attestation = TRUE               \* DA layer confirms data is available
    /\ prop.da_receipt.blockHeight > h_engram_verified  \* Check if the proof corresponds to the recovery target


(********************* CORE PROPOSAL VALIDITY (SEMANTIC FIREWALL) ******************************)
\* The core validity predicate for proposals
\* @type: (PROPOSAL) => Bool;
IsValidProposal(prop) == 
    /\ prop.value \in ValidValues
    /\ prop.timestamp \in MinTimestamp..MaxTimestamp
    /\ prop.fsm_state = CalculateNextFSMState   \* Cross-check
    
    \* DA Pipeline Check: Data must be available and within the allowed gap
    /\ (prop.fsm_state \in {"ANCHORED", "RECOVERING"}) => 
        /\ prop.da_receipt.attestation = TRUE
        /\ prop.da_receipt.blockHeight >= (h_engram_current - T_DA)
    
    \* Settlement Monotonicity Check: BTC anchor height cannot go backwards
    /\ prop.btc_anchored >= h_btc_anchored
    
    \* Economic Circuit Breaker: Halt all cross-chain withdrawals during partition
    /\ (prop.fsm_state = "SOVEREIGN") => ~ContainsWithdrawal(prop.value)
    
    \* RE-ANCHORING LOGIC: Mandatory ZK-Proof when hysteresis wait is met
    \* If not met, strict enforcement that no fake ZK-proof is attached.
    /\ IF prop.fsm_state = "RECOVERING" /\ safe_blocks = HYSTERESIS_WAIT 
       THEN VerifyZkProof(prop)
       ELSE prop.zk_proof_ref = FALSE


(********************* SENSORS & CENSORSHIP RESISTANCE ******************************)
\* Censorship sensor
\* @type: (PROCESS, PROPOSAL) => Bool;
IsCensoring(p, prop) == 
    \E tx \in forced_tx_queue :
        /\ tx_ignored_rounds[p][tx] >= MaxIgnoreRounds   \* Read from Node p's perspective
        /\ prop.value /= tx


(************************ BYZANTINE MESSAGE SETS *********************)
\* Only generate messages sent by the Faulty node (Extremely small number: T x MaxRound)
\* @type: (ROUND) => Set(MESSAGE);
FaultyTimeouts(r) == 
    { [type |-> "TIMEOUT", src |-> f, round |-> r] : f \in Faulty }

\* @type: (ROUND) => Set(MESSAGE);
FaultyPrevotes(r) == 
    { [type |-> "PREVOTE", src |-> f, round |-> r, id |-> Id(NilProposal)] : f \in Faulty }

\* @type: (ROUND) => Set(MESSAGE);
FaultyPrecommits(r) == 
    { [type |-> "PRECOMMIT", src |-> f, round |-> r, id |-> Id(NilProposal)] : f \in Faulty }


(********************* PROTOCOL INITIALIZATION ******************************)
\* @type: (ROUND) => Set(PROPMESSAGE);
RoundProposals(r) ==
    [
    type      : {"PROPOSAL"}, 
    src       : AllProcs,
    round     : {r}, 
    proposal  : Proposals, 
    validRound: RoundsOrNil
    ]

\* @type: (ROUND -> Set(MESSAGE)) => Bool;
BenignRoundsInMessages(msgfun) ==
  \* the message function never contains a message for a wrong round
  \A r \in Rounds:
    \A m \in msgfun[r]:
      r = m.round

\* The initial states of the protocol. Some faults can be in the system already.
TM_Init ==
    /\ round = [p \in Corr |-> 0]
    /\ localClock \in [Corr -> MinTimestamp..(MinTimestamp + Precision)]
    /\ localRemTime = [p \in Corr |-> TimeoutDuration]
    /\ realTime = 0
    /\ step = [p \in Corr |-> "PROPOSE"]
    /\ decision = [p \in Corr |-> NilDecision]
    /\ lockedValue = [p \in Corr |-> NilValue]
    /\ lockedRound = [p \in Corr |-> NilRound]
    /\ validValue = [p \in Corr |-> NilProposal]
    /\ validRound = [p \in Corr |-> NilRound]
    /\ msgsPropose = [r \in Rounds |-> {}]
    /\ msgsPrevote   = [r \in Rounds |-> FaultyPrevotes(r)]
    /\ msgsPrecommit = [r \in Rounds |-> FaultyPrecommits(r)]
    /\ msgsTimeout   = [r \in Rounds |-> FaultyTimeouts(r)]
    /\ receivedTimelyProposal = [p \in Corr |-> {}]
    /\ inspectedProposal = [r \in Rounds, p \in Corr |-> NilTimestamp]
    /\ BenignRoundsInMessages(msgsPropose)
    /\ BenignRoundsInMessages(msgsPrevote)
    /\ BenignRoundsInMessages(msgsPrecommit)
    /\ evidence = {}
    /\ action = "Init"
    /\ beginRound = 
      [r \in Rounds |-> 
        IF r = 0
        THEN Min({localClock[p] : p \in Corr})
        ELSE MaxTimestamp
      ]
    /\ endConsensus = [p \in Corr |-> NilTimestamp]
    /\ lastBeginRound = 
      [r \in Rounds |-> 
        IF r = 0
        THEN Max({localClock[p] : p \in Corr})
        ELSE NilTimestamp
      ]
    /\ proposalTime = [r \in Rounds |-> NilTimestamp]
    /\ proposalReceivedTime = [r \in Rounds |-> NilTimestamp]

    /\ forced_tx_queue = {"TX_NORMAL"}
    /\ tx_ignored_rounds = [p \in Corr |-> [tx \in ValidValues |-> 0]]


(************************ MESSAGE PASSING ********************************)
\* @type: (PROCESS, ROUND, PROPOSAL, ROUND) => Bool;
BroadcastProposal(pSrc, pRound, pProposal, pValidRound) ==
  LET 
    \* @type: PROPMESSAGE;
    newMsg ==
    [
      type       |-> "PROPOSAL", 
      src        |-> pSrc, 
      round      |-> pRound,
      proposal   |-> pProposal, 
      validRound |-> pValidRound
    ]
  IN
  /\ msgsPropose' = [msgsPropose EXCEPT ![pRound] = msgsPropose[pRound] \union {newMsg}]

\* @type: (PROCESS, ROUND, PROPOSAL) => Bool;
BroadcastPrevote(pSrc, pRound, pId) ==
  LET 
    \* @type: PREMESSAGE;
    newMsg == 
    [
      type  |-> "PREVOTE",
      src   |-> pSrc, 
      round |-> pRound, 
      id    |-> pId
    ]
  IN
  /\ msgsPrevote' = [msgsPrevote EXCEPT ![pRound] = msgsPrevote[pRound] \union {newMsg}]

\* @type: (PROCESS, ROUND, PROPOSAL) => Bool;
BroadcastPrecommit(pSrc, pRound, pId) ==
  LET
    \* @type: PREMESSAGE; 
    newMsg == 
    [
      type  |-> "PRECOMMIT",
      src   |-> pSrc, 
      round |-> pRound, 
      id    |-> pId
    ]
  IN
  /\ msgsPrecommit' = [msgsPrecommit EXCEPT ![pRound] = msgsPrecommit[pRound] \union {newMsg}]

\* @type: (PROCESS, ROUND) => Bool;
BroadcastTimeout(pSrc, pRound) == 
    LET 
        newMsg == 
        [ 
            type |-> "TIMEOUT", 
            src |-> pSrc, 
            round |-> pRound 
        ]
    IN 
    /\ msgsTimeout' = [msgsTimeout EXCEPT ![pRound] = msgsTimeout[pRound] \union {newMsg}]

(***************************** TIME **************************************)
\* @type: Bool;
SynchronizedLocalClocks ==
    \A p \in Corr : \A q \in Corr : 
        p /= q => 
            \/ /\ localClock[p] >= localClock[q]
               /\ localClock[p] - localClock[q] < Precision 
            \/ /\ localClock[p] < localClock[q]
               /\ localClock[q] - localClock[p] < Precision
    
\* @type: (VALUE, TIME, ROUND, STRING, DA_RECEIPT, Int, Bool) => PROPOSAL;
Proposal(v, t, r, fsm_state, da_receipt, h_btc, has_proof) == 
    [ 
        value             |-> v,
        timestamp         |-> t,
        round             |-> r,
        fsm_state         |-> fsm_state,
        da_receipt        |-> da_receipt,
        btc_anchored      |-> h_btc,
        zk_proof_ref      |-> has_proof  \* Has_proof is a Boolean from the environment
    ]

\* @type: (PROPOSAL, ROUND) => DECISION;
Decision(p, r) ==
    [
        prop  |-> p,
        round |-> r
    ]

(**************** MESSAGE PROCESSING TRANSITIONS *************************)
UpdateIgnoredRounds(p) ==
    tx_ignored_rounds' = [tx_ignored_rounds EXCEPT ![p] = 
        [tx \in ValidValues |-> 
            IF tx \in forced_tx_queue 
            THEN tx_ignored_rounds[p][tx] + 1 
            ELSE tx_ignored_rounds[p][tx]
        ]
    ]


\* @type: (PROCESS, ROUND) => Bool;
StartRound(p, r) ==
   /\ step[p] /= "DECIDED" \* a decided process does not participate in consensus
   /\ round' = [round EXCEPT ![p] = r]
   /\ step' = [step EXCEPT ![p] = "PROPOSE"]
   \* We only need to update (last)beginRound[r] once a process enters round `r`
   /\ beginRound' = [beginRound EXCEPT ![r] = Min2(@, localClock[p])]
   /\ lastBeginRound' = [lastBeginRound EXCEPT ![r] = Max2(@, localClock[p])]

   /\ localRemTime' = [localRemTime EXCEPT ![p] = TimeoutDuration]
   /\ UpdateIgnoredRounds(p)


\* Proposer inserts a valid proposal (injected directly from the Server layer)
\* @type: (PROCESS, PROPOSAL) => Bool;
InsertProposal(p, prop) ==
    LET r == round[p] IN
    /\ p = Proposer[r]
    /\ step[p] = "PROPOSE"
    /\ \A m \in msgsPropose[r]: m.src /= p
    
    \* Broadcast the injected proposal and assert its app-level validity
    /\ BroadcastProposal(p, r, prop, validRound[p])
    /\ IsValidProposal(prop)               
    
    /\ proposalTime' = [proposalTime EXCEPT ![r] = realTime]
    /\ UNCHANGED <<temporalVars, coreVars, fsmVars, censorVars>>
    /\ UNCHANGED <<msgsPrevote, msgsPrecommit, msgsTimeout, evidence, receivedTimelyProposal, inspectedProposal>>
    /\ UNCHANGED <<beginRound, endConsensus, lastBeginRound, proposalReceivedTime>>
    /\ action' = "InsertProposal"


\* - ReceiveProposal: Buffers incoming proposals from the leader. It acts as 
\* a time-bound filter, only accepting proposals that arrive within the 
\* synchronous time window (IsTimely).
\* @type: (PROCESS) => Bool;
ReceiveProposal(p) ==
  LET r == round[p] IN
  \E msg \in msgsPropose[r] :
      /\ msg.type = "PROPOSAL"
      /\ msg.src = Proposer[r]
      /\ msg.validRound = NilRound
      /\ inspectedProposal[r,p] = NilTimestamp
      /\ msg \notin receivedTimelyProposal[p]
      /\ inspectedProposal' = [inspectedProposal EXCEPT ![r,p] = localClock[p]]
      /\ LET isTimely == IsTimely(localClock[p], msg.proposal.timestamp) IN
         \/ /\ isTimely
            /\ receivedTimelyProposal' = [receivedTimelyProposal EXCEPT ![p] = @ \union {msg}]
            /\ LET isNilTimestamp == proposalReceivedTime[r] = NilTimestamp IN
               \/ /\ isNilTimestamp
                  /\ proposalReceivedTime' = [proposalReceivedTime EXCEPT ![r] = realTime]
               \/ /\ ~isNilTimestamp
                  /\ UNCHANGED proposalReceivedTime
         \/ /\ ~isTimely
            /\ UNCHANGED <<receivedTimelyProposal, proposalReceivedTime>>
      /\ UNCHANGED <<temporalVars, coreVars, fsmVars, censorVars>>
      /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout, evidence>>
      /\ UNCHANGED <<beginRound, endConsensus, lastBeginRound, proposalTime>>
      /\ action' = "ReceiveProposal"


\* - UponProposalInPropose: The "Gatekeeper". Evaluates a timely proposal. 
\* If it passes all application-level checks (IsValidProposal, ZK-proofs), 
\* the node casts a PREVOTE for it. Otherwise, it votes Nil.
\* @type: (PROCESS) => Bool;
UponProposalInPropose(p) ==
    LET r == round[p] IN
    \E msg \in receivedTimelyProposal[p] :
        /\ msg.type = "PROPOSAL"
        /\ msg.round = r
        /\ msg.src = Proposer[r]
        /\ msg.validRound = NilRound
        /\ step[p] = "PROPOSE"
        /\ evidence' = {msg} \union evidence
        /\ LET 
               prop == msg.proposal
           IN
           IF IsCensoring(p, prop) THEN
                \* 1. Branch under review: Prevote rejected, forced early round transfer
                /\ BroadcastTimeout(p, r)
                /\ StartRound(p, r + 1)
                
                /\ UNCHANGED <<lockedValue, lockedRound, validValue, validRound, decision>>
                /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, receivedTimelyProposal, inspectedProposal>>
                /\ UNCHANGED <<localClock, realTime>>
                /\ UNCHANGED <<endConsensus, proposalTime, proposalReceivedTime>>
                /\ UNCHANGED <<fsmVars, forced_tx_queue>>
           ELSE
                \* 2. Normal branch
                /\ LET vote_target == IF IsValidProposal(prop) /\ (lockedRound[p] = NilRound \/ lockedValue[p] = prop.value) 
                                        THEN prop 
                                        ELSE NilProposal
                    IN BroadcastPrevote(p, r, vote_target)
                /\ step' = [step EXCEPT ![p] = "PREVOTE"]
                
                /\ UNCHANGED <<round, decision, lockedValue, lockedRound, validValue, validRound>>
                /\ UNCHANGED <<msgsPropose, msgsPrecommit, msgsTimeout, receivedTimelyProposal, inspectedProposal>>
                /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
               
        /\ action' = "UponProposalInPropose"


\* - UponProposalInProposeAndPrevote: Handles a proposal that carries a 
\* `validRound` (indicating the network previously locked on this value in 
\* a prior round). Validates and PREVOTEs accordingly.
\* @type: (PROCESS) => Bool;
UponProposalInProposeAndPrevote(p) ==
  LET r == round[p] IN
  \E msg \in msgsPropose[r] :
      /\ msg.type = "PROPOSAL"
      /\ msg.src = Proposer[r]
      /\ msg.validRound >= 0 /\ msg.validRound < r
      /\ step[p] = "PROPOSE"
      /\ LET prop == msg.proposal
             vr == msg.validRound
             PV == { m \in msgsPrevote[vr]: m.id = Id(prop) }
         IN /\ Cardinality(PV) >= THRESHOLD2
            /\ evidence' = PV \union {msg} \union evidence
            /\ LET mid == IF IsValidProposal(prop) /\ (lockedRound[p] <= vr \/ lockedValue[p] = prop.value)
                          THEN Id(prop) ELSE NilProposal
               IN BroadcastPrevote(p, r, mid)
      /\ step' = [step EXCEPT ![p] = "PREVOTE"]
      /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
      /\ UNCHANGED <<round, decision, lockedValue, lockedRound, validValue, validRound>>
      /\ UNCHANGED <<msgsPropose, msgsPrecommit, msgsTimeout, receivedTimelyProposal, inspectedProposal>>
      /\ action' = "UponProposalInProposeAndPrevote"


\* - UponQuorumOfPrevotesAny: Triggered when the node observes a 2/3+ quorum 
\* of PREVOTEs for anything (including Nil). Advances the state to PRECOMMIT.
\* @type: (PROCESS) => Bool;
UponQuorumOfPrevotesAny(p) ==
    /\ step[p] = "PREVOTE" \* line 34 and 61
    /\ \E MyEvidence \in SUBSET msgsPrevote[round[p]]:
        \* find the unique voters in the evidence
        LET Voters == { m.src: m \in MyEvidence } IN
        \* compare the number of the unique voters against the threshold
        /\ Cardinality(Voters) >= THRESHOLD2 \* line 34
        /\ evidence' = MyEvidence \union evidence
        /\ BroadcastPrecommit(p, round[p], NilProposal)
        /\ step' = [step EXCEPT ![p] = "PRECOMMIT"]
        /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
        /\ UNCHANGED
            <<round, (*step,*) decision, lockedValue, 
            lockedRound, validValue, validRound>>
        /\ UNCHANGED 
            <<msgsPropose, msgsPrevote, (*msgsPrecommit, *)
            (*evidence,*) msgsTimeout, receivedTimelyProposal, inspectedProposal>>
        /\ action' = "UponQuorumOfPrevotesAny"


\* - UponProposalInPrevoteOrCommitAndPrevote: Triggered when a 2/3+ quorum of 
\* PREVOTEs for a *specific* valid proposal is reached. The node LOCKS the 
\* value (updates lockedValue/lockedRound) and PRECOMMITs for it.
\* @type: (PROCESS) => Bool;
UponProposalInPrevoteOrCommitAndPrevote(p) ==
  LET r == round[p] IN
  \E msg \in msgsPropose[r] :
      /\ msg.type = "PROPOSAL"
      /\ msg.src = Proposer[r]
      /\ step[p] \in {"PREVOTE", "PRECOMMIT"}
      /\ LET prop == msg.proposal
             PV == { m \in msgsPrevote[r]: m.id = Id(prop) }
         IN /\ Cardinality(PV) >= THRESHOLD2
            /\ evidence' = PV \union {msg} \union evidence
            /\ IF step[p] = "PREVOTE" THEN
                  /\ lockedValue' = [lockedValue EXCEPT ![p] = prop.value]
                  /\ lockedRound' = [lockedRound EXCEPT ![p] = r]
                  /\ BroadcastPrecommit(p, r, Id(prop))
                  /\ step' = [step EXCEPT ![p] = "PRECOMMIT"]
                  /\ UNCHANGED <<validValue, validRound>>
               ELSE
                  /\ validValue' = [validValue EXCEPT ![p] = prop]
                  /\ validRound' = [validRound EXCEPT ![p] = r]
                  /\ UNCHANGED <<lockedValue, lockedRound, msgsPrecommit, step>>
      /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
      /\ UNCHANGED <<round, decision>>
      /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsTimeout, receivedTimelyProposal, inspectedProposal>>
      /\ action' = "UponProposalInPrevoteOrCommitAndPrevote"


\* - UponQuorumOfPrecommitsAny: Triggered when a 2/3+ quorum of PRECOMMITs 
\* for anything is reached, but no specific value won. Advances the network 
\* to the next round.
\* @type: (PROCESS) => Bool;
UponQuorumOfPrecommitsAny(p) ==
    /\ \E MyEvidence \in SUBSET msgsPrecommit[round[p]]:
        \* find the unique committers in the evidence
        LET Committers == { m.src: m \in MyEvidence } IN
        \* compare the number of the unique committers against the threshold
        /\ Cardinality(Committers) >= THRESHOLD2 \* line 47
        /\ evidence' = MyEvidence \union evidence
        /\ round[p] + 1 \in Rounds
        /\ StartRound(p, round[p] + 1)
        /\ UNCHANGED <<localClock, realTime>> 
        /\ UNCHANGED <<fsmVars>>
        /\ UNCHANGED
            <<(*beginRound,*) endConsensus, (*lastBeginRound,*)
            proposalTime, proposalReceivedTime>>
        /\ UNCHANGED
            <<(*round, step,*) decision, lockedValue, 
            lockedRound, validValue, validRound>>
        /\ UNCHANGED 
            <<msgsPropose, msgsPrevote, msgsPrecommit,
            (*evidence,*) msgsTimeout, receivedTimelyProposal, inspectedProposal>>
        /\ UNCHANGED <<forced_tx_queue>>
        /\ action' = "UponQuorumOfPrecommitsAny"
                        


\* - UponProposalInPrecommitNoDecision: The ultimate "Commit" function. 
\* Triggered when the node observes a 2/3+ quorum of PRECOMMITs for a 
\* *specific* proposal. The node finalizes the block, updates its decision 
\* state, and halts voting for the current round.
\* @type: (PROCESS) => Bool;
UponProposalInPrecommitNoDecision(p) ==
  LET r == round[p] IN
  \E msg \in msgsPropose[r] :
      /\ msg.type = "PROPOSAL"
      /\ msg.src = Proposer[r]
      /\ decision[p] = NilDecision
      /\ inspectedProposal[r,p] /= NilTimestamp
      /\ LET prop == msg.proposal
             PV == { m \in msgsPrecommit[r]: m.id = Id(prop) }
         IN /\ Cardinality(PV) >= THRESHOLD2
            /\ evidence' = PV \union {msg} \union evidence
            /\ decision' = [decision EXCEPT ![p] = Decision(prop, r)]
      /\ endConsensus' = [endConsensus EXCEPT ![p] = localClock[p]]
      /\ step' = [step EXCEPT ![p] = "DECIDED"]
      /\ UNCHANGED <<temporalVars, fsmVars, censorVars>>
      /\ UNCHANGED <<round, lockedValue, lockedRound, validValue, validRound>>
      /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout, receivedTimelyProposal, inspectedProposal>>
      /\ UNCHANGED <<beginRound, lastBeginRound, proposalTime, proposalReceivedTime>>
      /\ action' = "UponProposalInPrecommitNoDecision"


\* - OnTimeoutPropose: Fallback mechanisms. If the 
\* leader is offline, malicious, or censoring transactions, the node times 
\* out and casts a Nil PREVOTE to force a round change.
\* @type: (PROCESS) => Bool;
OnTimeoutPropose(p) ==
    /\ step[p] = "PROPOSE"
    /\ p /= Proposer[round[p]]
    /\ BroadcastPrevote(p, round[p], NilProposal)
    /\ step' = [step EXCEPT ![p] = "PREVOTE"]
    /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
    /\ UNCHANGED
        <<round, (*step,*) decision, lockedValue, 
        lockedRound, validValue, validRound>>
    /\ UNCHANGED 
        <<msgsPropose, (*msgsPrevote,*) msgsPrecommit, msgsTimeout, 
        evidence, receivedTimelyProposal, inspectedProposal>>
    /\ action' = "OnTimeoutPropose"


\* - OnQuorumOfNilPrevotes: Handles the scenario where 2/3+ nodes voted Nil 
\* in the Prevote phase. Moves the node directly to Precommit Nil.
\* @type: (PROCESS) => Bool;
OnQuorumOfNilPrevotes(p) ==
    /\ step[p] = "PREVOTE"
    /\ LET PV == { m \in msgsPrevote[round[p]]: m.id = Id(NilProposal) } IN
        /\ Cardinality(PV) >= THRESHOLD2 \* line 36
        /\ evidence' = PV \union evidence
        /\ BroadcastPrecommit(p, round[p], Id(NilProposal))
        /\ step' = [step EXCEPT ![p] = "PRECOMMIT"]
        /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
        /\ UNCHANGED
            <<round, (*step,*) decision, lockedValue, 
            lockedRound, validValue, validRound>>
        /\ UNCHANGED 
            <<msgsPropose, msgsPrevote, (*msgsPrecommit,*)
            (*evidence,*) msgsTimeout, receivedTimelyProposal, inspectedProposal>>
        /\ action' = "OnQuorumOfNilPrevotes"


\* - OnRoundCatchup: Fast-forward synchronization. If a node falls offline 
\* and observes f+1 messages from a higher round, it abandons its current 
\* state and jumps to the higher round to catch up.
\* @type: (PROCESS) => Bool;
OnRoundCatchup(p) ==
  \E r \in {rr \in Rounds: rr > round[p]}:
    LET RoundMsgs == msgsPropose[r] \union msgsPrevote[r] \union msgsPrecommit[r] IN
    \E MyEvidence \in SUBSET RoundMsgs:
        LET Faster == { m.src: m \in MyEvidence } IN
        /\ Cardinality(Faster) >= THRESHOLD1
        /\ evidence' = MyEvidence \union evidence
        /\ StartRound(p, r)
        /\ UNCHANGED <<temporalVars, fsmVars>>
        /\ UNCHANGED
            <<(*beginRound,*) endConsensus, (*lastBeginRound,*)
            proposalTime, proposalReceivedTime>>
        /\ UNCHANGED
            <<(*round, step,*) decision, lockedValue, 
            lockedRound, validValue, validRound>>
        /\ UNCHANGED 
            <<msgsPropose, msgsPrevote, msgsPrecommit,
            (*evidence,*) msgsTimeout, receivedTimelyProposal, inspectedProposal>>
        /\ UNCHANGED <<forced_tx_queue>>
        /\ action' = "OnRoundCatchup"

(************************ IMPROVED PACEMAKER (f+1 TIMEOUTS) *********************)
\* @type: (PROCESS) => Bool;
UponfPlusOneTimeoutsAny(p) ==
    \E r \in {rr \in Rounds: rr > round[p]}:
        \E MyEvidence \in SUBSET msgsTimeout[r]:
            LET Timers == { m.src: m \in MyEvidence } IN
                /\ Cardinality(Timers) >= THRESHOLD1 
                /\ evidence' = MyEvidence \union evidence
                
                \* Call the round-forward function to fast-forward through other honest nodes.
                /\ StartRound(p, r)
                
                /\ UNCHANGED <<localClock, realTime>>
                /\ UNCHANGED <<endConsensus, proposalTime, proposalReceivedTime>>
                /\ UNCHANGED <<decision, lockedValue, lockedRound, validValue, validRound>>
                /\ UNCHANGED <<forced_tx_queue>>            
                /\ UNCHANGED <<fsmVars>>
                /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout, receivedTimelyProposal, inspectedProposal>>
                /\ action' = "UponfPlusOneTimeoutsAny"

\* @type: (PROCESS) => Bool;
OnLocalTimerExpire(p) ==
    /\ localRemTime[p] = 0
    /\ BroadcastTimeout(p, round[p])
    /\ UNCHANGED <<coreVars, temporalVars, fsmVars, invariantVars, censorVars>>
    /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, evidence, receivedTimelyProposal, inspectedProposal>>
    /\ action' = "OnLocalTimerExpire"


(********************* PROTOCOL TRANSITIONS ******************************)
\* advance the global clock
AdvanceRealTime ==
    /\ ValidTime(realTime)
    /\ \E t \in Timestamps:
        /\ t > realTime
        /\ realTime' = t
        /\ localClock' = [p \in Corr |-> localClock[p] + (t - realTime)]
        /\ localRemTime' = [p \in Corr |->
               IF localRemTime[p] > 0 /\ ~\E m \in msgsPropose[round[p]]: m.src = Proposer[round[p]]
               THEN localRemTime[p] - 1
               ELSE localRemTime[p]]
        /\ UNCHANGED <<coreVars, invariantVars, fsmVars, censorVars>>
        /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout, evidence, receivedTimelyProposal, inspectedProposal>>
        /\ action' = "AdvanceRealTime"
    

\* process timely messages
\* @type: (PROCESS) => Bool;
MessageProcessing(p) ==
    \* start round
    \* \/ InsertProposal(p)
    \* reception step
    \/ ReceiveProposal(p)
    \* processing step
    \/ UponProposalInPropose(p)
    \/ UponProposalInProposeAndPrevote(p)
    \/ UponQuorumOfPrevotesAny(p)
    \/ UponProposalInPrevoteOrCommitAndPrevote(p)
    \/ UponQuorumOfPrecommitsAny(p)
    \/ UponProposalInPrecommitNoDecision(p)
    \* the actions below are not essential for safety, but added for completeness
    \/ OnTimeoutPropose(p)
    \/ OnQuorumOfNilPrevotes(p)
    \/ OnRoundCatchup(p)
    \/ UponfPlusOneTimeoutsAny(p)
    \/ OnLocalTimerExpire(p)


(************************ BYZANTINE DATA WITHHOLDING ATTACK *********************)
Byzantine_Data_Withholding == 
    \E r \in Rounds:
        \* Only activated when the malicious Node is selected as the Leader of this round
        /\ Proposer[r] \in Faulty
        \* Ensure it hasn't sent any proposals before.
        /\ msgsPropose[r] = {} 
        \* Create a valid structured proposal but intentionally hide data (attestation = FALSE)
        /\ LET bad_da == [ blockHeight |-> 999, attestation |-> FALSE ] 
               bad_prop == Proposal("TX_NORMAL", MinTimestamp, r, state, bad_da, h_btc_current, FALSE)
               bad_msg == [ type |-> "PROPOSAL", src |-> Proposer[r], round |-> r, proposal |-> bad_prop, validRound |-> NilRound ]
           IN 
            /\ msgsPropose' = [msgsPropose EXCEPT ![r] = msgsPropose[r] \union {bad_msg}]
            /\ UNCHANGED <<coreVars, temporalVars, fsmVars, invariantVars, censorVars>>
            /\ UNCHANGED <<msgsPrevote, msgsPrecommit, msgsTimeout>>
            /\ UNCHANGED <<evidence, action, receivedTimelyProposal, inspectedProposal>>

(************************ CENSORSHIP RESISTANCE INJECTION *********************)
SubmitToCelestiaDA == 
    \E tx \in ValidValues \ forced_tx_queue :
        /\ forced_tx_queue' = forced_tx_queue \union {tx}
        /\ UNCHANGED <<coreVars, temporalVars, bookkeepingVars, invariantVars, fsmVars>>
        /\ UNCHANGED <<tx_ignored_rounds>>

(*
 * A system transition. In this specificatiom, the system may eventually deadlock,
 * e.g., when all processes decide. This is expected behavior, as we focus on safety.
 *)
TM_Next == 
    \/ AdvanceRealTime 
    \/ /\ SynchronizedLocalClocks 
       /\ \E p \in Corr: MessageProcessing(p)
    \/ Byzantine_Data_Withholding
    \/ SubmitToCelestiaDA

(* ======================== SAFETY INVARIANTS ============================== *)
\* I1: All correct nodes that decide must agree on value
AgreementOnValue ==
    \A p, q \in Corr:
        /\ decision[p] /= NilDecision
        /\ decision[q] /= NilDecision
        => decision[p].prop.value = decision[q].prop.value

\* I2: Decided timestamp must fall within consensus round interval
ConsensusTimeValid ==
    \A p \in Corr:
        decision[p] /= NilDecision
        => LET r == decision[p].prop.round
               t == decision[p].prop.timestamp
           IN /\ beginRound[r] - Precision - Delay <= t
              /\ t <= endConsensus[p] + Precision

\* I3: If proposer is correct, timestamp >= round begin time
ConsensusSafeValidCorrProp ==
    \A p \in Corr:
        decision[p] /= NilDecision
        => LET pr == decision[p].prop.round
               t == decision[p].prop.timestamp
           IN (Proposer[pr] \in Corr) => beginRound[pr] <= t

\* I4: Decided proposal must pass IsValid checks (core safety gate)
HybridSafety ==
    \A p \in Corr:
        decision[p] /= NilDecision => IsValidProposal(decision[p].prop)

\* I5: Only valid values (never invalid garbage) are decided
ExternalValidity ==
    \A p \in Corr:
        decision[p] /= NilDecision => decision[p].prop.value \in ValidValues

(* ======================== EOTS SLASHING MECHANISM ======================== *)
\* Double-Signing Evidence: Detects a node sending two different messages in the same round.
DoubleSigningEvidence == 
    \E r \in Rounds, p \in AllProcs :
        \* Double-sign at the Prevote step
        \/ \E m1, m2 \in msgsPrevote[r] : 
            /\ m1.src = p 
            /\ m2.src = p 
            /\ m1.id /= m2.id
        \* Double-sign at the Precommit step
        \/ \E m1, m2 \in msgsPrecommit[r] : 
            /\ m1.src = p 
            /\ m2.src = p 
            /\ m1.id /= m2.id
        \* Double-sign at the Propose step
        \/ \E m1, m2 \in msgsPropose[r] : 
            /\ m1.src = p 
            /\ m2.src = p 
            /\ m1.proposal /= m2.proposal

\* I6: Accountability: Fork => The double-signer has been found.
Accountability == 
    (~AgreementOnValue) => DoubleSigningEvidence

(* ======================== MASTER INVARIANTS =============================== *)
\* Core consensus invariants (App-agnostic safety properties)
CoreTendermintInv ==
    /\ AgreementOnValue
    /\ ConsensusTimeValid
    /\ ConsensusSafeValidCorrProp
    /\ HybridSafety \* Keep this as it now just checks generic IsValidProposal
    /\ ExternalValidity
    /\ Accountability

(* ======================== SPECIFICATION ==================================== *)
\* Pure safety specification: no independent liveness requirements
TM_Spec == TM_Init /\ [][TM_Next]_tendermintVars
=============================================================================