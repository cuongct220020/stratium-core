-------------------- MODULE EngramTendermint ---------------------------
(*
 A TLA+ specification of a simplified Tendermint consensus, with added clocks 
 and proposer-based timestamps. This TLA+ specification extends and modifies 
 the Tendermint TLA+ specification for fork accountability: 
    https://github.com/tendermint/spec/blob/master/spec/light-client/accountability/TendermintAcc_004_draft.tla
 
 * Version 2. A preliminary specification.

 Zarko Milosevic, Igor Konnov, Informal Systems, 2019-2020.
 Ilina Stoilkovska, Josef Widder, Informal Systems, 2021.
 Jure Kukovec, Informal Systems, 2022.
 *)

\* EXTENDS Integers, FiniteSets, Apalache, typedefs
EXTENDS Integers, FiniteSets

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
  \* @type: Set(VALUE);  
  ValidValues,   \* the set of valid values, proposed both by correct and faulty
  \* @type: Set(VALUE);  
  InvalidValues, \* the set of invalid values, never proposed by the correct ones
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
  Precision     \* clock precision: the maximal difference between two local clocks  

ASSUME(N = Cardinality(Corr \union Faulty))

(*************************** DEFINITIONS ************************************)
\* @type: Set(PROCESS);
AllProcs == Corr \union Faulty      \* the set of all processes
\* @type: Set(ROUND);
Rounds == 0..MaxRound               \* the set of potential rounds
\* @type: Set(TIME);
Timestamps == 0..MaxTimestamp       \* the set of clock ticks
\* @type: ROUND;
NilRound == -1   \* a special value to denote a nil round, outside of Rounds
\* @type: TIME;
NilTimestamp == -1 \* a special value to denote a nil timestamp, outside of Ticks
\* @type: Set(ROUND);
RoundsOrNil == Rounds \union {NilRound}
\* @type: Set(VALUE);
Values == ValidValues \union InvalidValues \* the set of all values
\* @type: VALUE;
NilValue == "None"  \* a special value for a nil round, outside of Values
\* @type: Set(PROPOSAL);
Proposals == Values \X Timestamps \X Rounds

NilProposal == [ 
    value        |-> NilValue, 
    timestamp    |-> NilTimestamp, 
    round        |-> NilRound, 
    fsm_state    |-> "NONE", 
    da_receipt   |-> FALSE, 
    btc_anchored |-> -1 
]


\* @type: Set(VALUE);
ValuesOrNil == Values \union {NilValue}
\* @type: Set(DECISION);
Decisions == Proposals \X Rounds
\* @type: DECISION;
NilDecision == <<NilProposal, NilRound>>

ValidProposals ==
[ 
    value               : ValidValues,
    timestamp           : MinTimestamp..MaxTimestamp,
    round               : Rounds,
    fsm_state           : {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"},
    da_receipt          : BOOLEAN,
    btc_anchored        : Nat 
]

\* a value hash is modeled as identity
\* @type: (t) => t;
Id(v) == v

\* Time validity check. If we want MaxTimestamp = \infty, set ValidTime(t) == TRUE
ValidTime(t) == t < MaxTimestamp

\* @type: (PROPMESSAGE) => VALUE;
MessageValue(msg) == msg.proposal.value
\* @type: (PROPMESSAGE) => TIME;
MessageTime(msg) == msg.proposal.timestamp
\* @type: (PROPMESSAGE) => ROUND;
MessageRound(msg) == msg.proposal.round
\* @type: (PROPMESSAGE) => FSM_STATE;
MessageFSM(msg)   == msg.proposal.fsm_state
\* @type: (PROPMESSAGE) => DA_RECEIPT;
MessageDA(msg)    == msg.proposal.da_receipt
\* @type: (PROPMESSAGE) => BTC_ANCHORED;
MessageBTC(msg)   == msg.proposal.btc_anchored

\* @type: (TIME, TIME) => Bool;
IsTimely(processTime, messageTime) ==
  /\ processTime >= messageTime - Precision
  /\ processTime <= messageTime + Precision + Delay

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

(********************* PROTOCOL STATE VARIABLES ******************************)
VARIABLES
    \* @type: PROCESS -> ROUND;
    round,    \* a process round number
    \* @type: PROCESS -> STEP;
    step,     \* a process step
    \* @type: PROCESS -> DECISION;
    decision, \* process decision
    \* @type: PROCESS -> VALUE;
    lockedValue,  \* a locked value
    \* @type: PROCESS -> ROUND;
    lockedRound,  \* a locked round
    \* @type: PROCESS -> PROPOSAL;
    validValue,   \* a valid value
    \* @type: PROCESS -> ROUND;
    validRound    \* a valid round

coreVars == 
  <<round, step, decision, lockedValue, 
  lockedRound, validValue, validRound>>

\* time-related variables
VARIABLES  
  \* @type: PROCESS -> TIME;
  localClock, \* a process local clock: Corr -> Ticks
  \* @type: TIME;
  realTime   \* a reference Newtonian real time

temporalVars == <<localClock, realTime>>

\* book-keeping variables
VARIABLES
  \* @type: ROUND -> Set(PROPMESSAGE);
  msgsPropose,   \* PROPOSE messages broadcast in the system, Rounds -> Messages
  \* @type: ROUND -> Set(PREMESSAGE);
  msgsPrevote,   \* PREVOTE messages broadcast in the system, Rounds -> Messages
  \* @type: ROUND -> Set(PREMESSAGE);
  msgsPrecommit, \* PRECOMMIT messages broadcast in the system, Rounds -> Messages
  \* @type: Set(MESSAGE);
  evidence, \* the messages that were used by the correct processes to make transitions
  \* @type: ACTION;
  action,       \* we use this variable to see which action was taken
  \* @type: PROCESS -> Set(PROPMESSAGE);
  receivedTimelyProposal, \* used to keep track when a process receives a timely PROPOSAL message
  \* @type: <<ROUND,PROCESS>> -> TIME;
  inspectedProposal \* used to keep track when a process tries to receive a message
  
\* Action is excluded from the tuple, because it always changes
bookkeepingVars == 
  <<msgsPropose, msgsPrevote, msgsPrecommit, 
  evidence, (*action,*) receivedTimelyProposal, 
  inspectedProposal>>

\* Invariant support
VARIABLES
  \* @type: ROUND -> TIME;
  beginRound, \* the minimum of the local clocks at the time any process entered a new round
  \* @type: PROCESS -> TIME;
  endConsensus, \* the local time when a decision is made
  \* @type: ROUND -> TIME;
  lastBeginRound, \* the maximum of the local clocks in each round
  \* @type: ROUND -> TIME;
  proposalTime, \* the real time when a proposer proposes in a round
  \* @type: ROUND -> TIME;
  proposalReceivedTime \* the real time when a correct process first receives a proposal message in a round

invariantVars == 
  <<beginRound, endConsensus, lastBeginRound,
  proposalTime, proposalReceivedTime>>

VARIABLE 
    state,                   \* Trạng thái FSM (ANCHORED, SUSPICIOUS,...)
    h_btc_current,           \* Chiều cao khối BTC hiện tại
    h_btc_submitted,         \* Chiều cao BTC đã submit
    h_btc_anchored,          \* Chiều cao BTC đã chốt an toàn
    h_da_local,              \* Chiều cao DA local
    h_da_verified,           \* Chiều cao DA đã xác thực
    is_das_failed,           \* Trạng thái lỗi lấy mẫu DA
    peer_count,              \* Số lượng node peer
    safe_blocks,             \* Bộ đếm khối an toàn (phục hồi)
    reanchoring_proof_valid  \* Bằng chứng ZK hợp lệ

fsmVars == <<state, h_btc_current, h_btc_submitted, h_btc_anchored, h_da_local, h_da_verified, is_das_failed, peer_count, safe_blocks, reanchoring_proof_valid>>

IsDAHealthy == ~is_das_failed
vars == <<coreVars, temporalVars, bookkeepingVars, action, invariantVars, fsmVars>>

ContainsWithdrawal(p) == FALSE

\* The validity predicate
\* @type: (PROPOSAL) => Bool;
IsValid(p) == 
    /\ p \in ValidProposals
    \* Luật 1: Leader không được nói dối về trạng thái chuỗi ngoại biên
    /\ p.fsm_state = state
    /\ p.btc_anchored = h_btc_anchored
    /\ p.da_receipt = IsDAHealthy
    \* Luật 2: Đòi hỏi an ninh ngoại sinh (DA)
    /\ (p.fsm_state \in {"ANCHORED", "RECOVERING"}) => (p.da_receipt = TRUE)
    \* Luật 3: Kích hoạt ngắt mạch kinh tế (Circuit Breaker)
    /\ (p.fsm_state = "SOVEREIGN") => ~ContainsWithdrawal(p.value)

(********************* PROTOCOL INITIALIZATION ******************************)
\* @type: (ROUND) => Set(PROPMESSAGE);
FaultyProposals(r) ==
  [
    type      : {"PROPOSAL"}, 
    src       : Faulty,
    round     : {r}, 
    proposal  : Proposals, 
    validRound: RoundsOrNil
  ]

\* @type: Set(PROPMESSAGE);
AllFaultyProposals ==
  [
    type      : {"PROPOSAL"}, 
    src       : Faulty,
    round     : Rounds, 
    proposal  : Proposals, 
    validRound: RoundsOrNil
  ]

\* @type: (ROUND) => Set(PREMESSAGE);
FaultyPrevotes(r) ==
  [
    type : {"PREVOTE"}, 
    src  : Faulty, 
    round: {r}, 
    id   : Proposals
  ]

\* @type: Set(PREMESSAGE);
AllFaultyPrevotes ==    
  [
    type : {"PREVOTE"}, 
    src  : Faulty, 
    round: Rounds, 
    id   : Proposals
  ]

\* @type: (ROUND) => Set(PREMESSAGE);
FaultyPrecommits(r) ==
  [
    type : {"PRECOMMIT"}, 
    src  : Faulty, 
    round: {r}, 
    id   : Proposals
  ]

\* @type: Set(PREMESSAGE);
AllFaultyPrecommits ==
  [
    type : {"PRECOMMIT"}, 
    src  : Faulty, 
    round: Rounds, 
    id   : Proposals
  ]

\* @type: Set(PROPMESSAGE);
AllProposals ==
  [
    type      : {"PROPOSAL"}, 
    src       : AllProcs,
    round     : Rounds, 
    proposal  : Proposals, 
    validRound: RoundsOrNil
  ]    

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
Init ==
    /\ round = [p \in Corr |-> 0]
    /\ localClock \in [Corr -> MinTimestamp..(MinTimestamp + Precision)]
    /\ realTime = 0
    /\ step = [p \in Corr |-> "PROPOSE"]
    /\ decision = [p \in Corr |-> NilDecision]
    /\ lockedValue = [p \in Corr |-> NilValue]
    /\ lockedRound = [p \in Corr |-> NilRound]
    /\ validValue = [p \in Corr |-> NilProposal]
    /\ validRound = [p \in Corr |-> NilRound]
    /\ msgsPropose = [r \in Rounds |-> {}]
    /\ msgsPrevote = [r \in Rounds |-> {}]
    /\ msgsPrecommit = [r \in Rounds |-> {}]
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

(***************************** TIME **************************************)

\* [PBTS-CLOCK-PRECISION.0]
\* @type: Bool;
SynchronizedLocalClocks ==
    \A p \in Corr : \A q \in Corr : 
        p /= q => 
            \/ /\ localClock[p] >= localClock[q]
               /\ localClock[p] - localClock[q] < Precision 
            \/ /\ localClock[p] < localClock[q]
               /\ localClock[q] - localClock[p] < Precision
    
\* [PBTS-PROPOSE.0]
\* @type: (VALUE, TIME, ROUND) => PROPOSAL;
Proposal(v, t, r, fsm, da, h_btc) == 
    [ 
        value             |-> v,
        timestamp         |-> t,
        round             |-> r,
        fsm_state         |-> fsm,
        da_receipt        |-> da,
        btc_anchored      |-> h_btc 
    ]

\* [PBTS-DECISION-ROUND.0]
\* @type: (PROPOSAL, ROUND) => DECISION;
Decision(p, r) ==
    <<p, r>>

(**************** MESSAGE PROCESSING TRANSITIONS *************************)
\* lines 12-13
\* @type: (PROCESS, ROUND) => Bool;
StartRound(p, r) ==
   /\ step[p] /= "DECIDED" \* a decided process does not participate in consensus
   /\ round' = [round EXCEPT ![p] = r]
   /\ step' = [step EXCEPT ![p] = "PROPOSE"]
   \* We only need to update (last)beginRound[r] once a process enters round `r`
   /\ beginRound' = [beginRound EXCEPT ![r] = Min2(@, localClock[p])]
   /\ lastBeginRound' = [lastBeginRound EXCEPT ![r] = Max2(@, localClock[p])]

\* lines 14-19, a proposal may be sent later
\* @type: (PROCESS) => Bool;
InsertProposal(p) == 
  LET r == round[p] IN
  /\ p = Proposer[r]
  /\ step[p] = "PROPOSE"
  /\ \A m \in msgsPropose[r]: m.src /= p
  /\ \E v \in ValidValues:
       LET prop == IF validValue[p] /= NilProposal THEN validValue[p] 
                   ELSE [ value |-> v, timestamp |-> localClock[p], round |-> r, fsm_state |-> state, da_receipt |-> IsDAHealthy, btc_anchored |-> h_btc_anchored ]
       IN BroadcastProposal(p, r, prop, validRound[p])
  /\ proposalTime' = [proposalTime EXCEPT ![r] = realTime]
  /\ UNCHANGED <<temporalVars, coreVars, fsmVars>>
  /\ UNCHANGED <<msgsPrevote, msgsPrecommit, evidence, receivedTimelyProposal, inspectedProposal>>
  /\ UNCHANGED <<beginRound, endConsensus, lastBeginRound, proposalReceivedTime>>
  /\ action' = "InsertProposal"


\* a new action used to filter messages that are not on time
\* [PBTS-RECEPTION-STEP.0]
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
      /\ UNCHANGED <<temporalVars, coreVars, fsmVars>>
      /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, evidence>>
      /\ UNCHANGED <<beginRound, endConsensus, lastBeginRound, proposalTime>>
      /\ action' = "ReceiveProposal"


\* lines 22-27
\* @type: (PROCESS) => Bool;
UponProposalInPropose(p) ==
  LET r == round[p] IN
  \E msg \in receivedTimelyProposal[p] :
      /\ msg.type = "PROPOSAL"
      /\ msg.src = Proposer[r]
      /\ msg.validRound = NilRound
      /\ step[p] = "PROPOSE"
      /\ evidence' = {msg} \union evidence
      /\ LET prop == msg.proposal
             mid == IF IsValid(prop) /\ (lockedRound[p] = NilRound \/ lockedValue[p] = prop.value)
                    THEN Id(prop) ELSE NilProposal
         IN BroadcastPrevote(p, r, mid)
      /\ step' = [step EXCEPT ![p] = "PREVOTE"]
      /\ UNCHANGED <<temporalVars, invariantVars, fsmVars>>
      /\ UNCHANGED <<round, decision, lockedValue, lockedRound, validValue, validRound>>
      /\ UNCHANGED <<msgsPropose, msgsPrecommit, receivedTimelyProposal, inspectedProposal>>
      /\ action' = "UponProposalInPropose"

\* lines 28-33        
\* [PBTS-ALG-OLD-PREVOTE.0]
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
            /\ LET mid == IF IsValid(prop) /\ (lockedRound[p] <= vr \/ lockedValue[p] = prop.value)
                          THEN Id(prop) ELSE NilProposal
               IN BroadcastPrevote(p, r, mid)
      /\ step' = [step EXCEPT ![p] = "PREVOTE"]
      /\ UNCHANGED <<temporalVars, invariantVars, fsmVars>>
      /\ UNCHANGED <<round, decision, lockedValue, lockedRound, validValue, validRound>>
      /\ UNCHANGED <<msgsPropose, msgsPrecommit, receivedTimelyProposal, inspectedProposal>>
      /\ action' = "UponProposalInProposeAndPrevote"


\* lines 34-35 + lines 61-64 (onTimeoutPrevote)
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
      /\ UNCHANGED <<temporalVars, invariantVars, fsmVars>>
      /\ UNCHANGED
        <<round, (*step,*) decision, lockedValue, 
        lockedRound, validValue, validRound>>
      /\ UNCHANGED 
        <<msgsPropose, msgsPrevote, (*msgsPrecommit, *)
        (*evidence,*) receivedTimelyProposal, inspectedProposal>>
      /\ action' = "UponQuorumOfPrevotesAny"
                     
\* lines 36-46
\* [PBTS-ALG-NEW-PREVOTE.0]
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
      /\ UNCHANGED <<temporalVars, invariantVars, fsmVars>>
      /\ UNCHANGED <<round, decision>>
      /\ UNCHANGED <<msgsPropose, msgsPrevote, receivedTimelyProposal, inspectedProposal>>
      /\ action' = "UponProposalInPrevoteOrCommitAndPrevote"


\* lines 47-48 + 65-67 (onTimeoutPrecommit)
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
      /\ UNCHANGED <<temporalVars, fsmVars>>
      /\ UNCHANGED
        <<(*beginRound,*) endConsensus, (*lastBeginRound,*)
        proposalTime, proposalReceivedTime>>
      /\ UNCHANGED
        <<(*round, step,*) decision, lockedValue, 
        lockedRound, validValue, validRound>>
      /\ UNCHANGED 
        <<msgsPropose, msgsPrevote, msgsPrecommit,
        (*evidence,*) receivedTimelyProposal, inspectedProposal>>
      /\ action' = "UponQuorumOfPrecommitsAny"
                     
\* lines 49-54        
\* [PBTS-ALG-DECIDE.0]
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
      /\ UNCHANGED <<temporalVars, fsmVars>>
      /\ UNCHANGED <<round, lockedValue, lockedRound, validValue, validRound>>
      /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, receivedTimelyProposal, inspectedProposal>>
      /\ UNCHANGED <<beginRound, lastBeginRound, proposalTime, proposalReceivedTime>>
      /\ action' = "UponProposalInPrecommitNoDecision"


                    
\* the actions below are not essential for safety, but added for completeness

\* lines 20-21 + 57-60
\* @type: (PROCESS) => Bool;
OnTimeoutPropose(p) ==
  /\ step[p] = "PROPOSE"
  /\ p /= Proposer[round[p]]
  /\ BroadcastPrevote(p, round[p], NilProposal)
  /\ step' = [step EXCEPT ![p] = "PREVOTE"]
  /\ UNCHANGED <<temporalVars, invariantVars, fsmVars>>
  /\ UNCHANGED
    <<round, (*step,*) decision, lockedValue, 
    lockedRound, validValue, validRound>>
  /\ UNCHANGED 
    <<msgsPropose, (*msgsPrevote,*) msgsPrecommit,
    evidence, receivedTimelyProposal, inspectedProposal>>
  /\ action' = "OnTimeoutPropose"

\* lines 44-46
\* @type: (PROCESS) => Bool;
OnQuorumOfNilPrevotes(p) ==
  /\ step[p] = "PREVOTE"
  /\ LET PV == { m \in msgsPrevote[round[p]]: m.id = Id(NilProposal) } IN
    /\ Cardinality(PV) >= THRESHOLD2 \* line 36
    /\ evidence' = PV \union evidence
    /\ BroadcastPrecommit(p, round[p], Id(NilProposal))
    /\ step' = [step EXCEPT ![p] = "PRECOMMIT"]
    /\ UNCHANGED <<temporalVars, invariantVars, fsmVars>>
    /\ UNCHANGED
      <<round, (*step,*) decision, lockedValue, 
      lockedRound, validValue, validRound>>
    /\ UNCHANGED 
      <<msgsPropose, msgsPrevote, (*msgsPrecommit,*)
      (*evidence,*) receivedTimelyProposal, inspectedProposal>>
    /\ action' = "OnQuorumOfNilPrevotes"

\* lines 55-56
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
          (*evidence,*) receivedTimelyProposal, inspectedProposal>>
        /\ action' = "OnRoundCatchup"


(********************* PROTOCOL TRANSITIONS ******************************)
\* advance the global clock
\* @type: Bool;
AdvanceRealTime == 
    /\ ValidTime(realTime)
    /\ \E t \in Timestamps:
      /\ t > realTime
      /\ realTime' = t
      /\ localClock' = [p \in Corr |-> localClock[p] + (t - realTime)]  
    /\ UNCHANGED <<coreVars, bookkeepingVars, invariantVars, fsmVars>>
    /\ action' = "AdvanceRealTime"
    
\* advance the local clock of node p to some larger time t, not necessarily by 1
\* #type: (PROCESS) => Bool;
\* AdvanceLocalClock(p) ==
\*     /\ ValidTime(localClock[p])
\*     /\ \E t \in Timestamps:
\*       /\ t > localClock[p] 
\*       /\ localClock' = [localClock EXCEPT ![p] = t]
\*     /\ UNCHANGED <<coreVars, bookkeepingVars, invariantVars>>
\*     /\ UNCHANGED realTime
\*     /\ action' = "AdvanceLocalClock"

\* process timely messages
\* @type: (PROCESS) => Bool;
MessageProcessing(p) ==
    \* start round
    \/ InsertProposal(p)
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

(*
 * A system transition. In this specificatiom, the system may eventually deadlock,
 * e.g., when all processes decide. This is expected behavior, as we focus on safety.
 *)
Next == 
    \/ AdvanceRealTime 
    \/ /\ SynchronizedLocalClocks 
       /\ \E p \in Corr: MessageProcessing(p)


(*************************** INVARIANTS *************************************)
\* [PBTS-INV-AGREEMENT.0]
AgreementOnValue ==
    \A p, q \in Corr:
        /\ decision[p] /= NilDecision
        /\ decision[q] /= NilDecision
        => decision[p][1].value = decision[q][1].value

\* [PBTS-CONSENSUS-TIME-VALID.0]
ConsensusTimeValid ==
    \A p \in Corr:
        decision[p] /= NilDecision
        => LET pr == decision[p][1].round
               t == decision[p][1].timestamp
           IN (/\ beginRound[pr] - Precision - Delay <= t
               /\ t <= endConsensus[p] + Precision)

\* [PBTS-CONSENSUS-SAFE-VALID-CORR-PROP.0]
ConsensusSafeValidCorrProp ==
    \A p \in Corr:
        decision[p] /= NilDecision
        => LET pr == decision[p][1].round
               t == decision[p][1].timestamp
           IN (Proposer[pr] \in Corr)
              => beginRound[pr] <= t

\* [PBTS-CONSENSUS-REALTIME-VALID-CORR.0]
ConsensusRealTimeValidCorr ==
  \A r \in Rounds :
    \E p \in Corr: 
     (/\ decision[p] /= NilDecision 
      /\ decision[p][2] = r
      /\ proposalTime[r] /= NilTimestamp)
        => LET t == decision[p][1].timestamp
           IN (/\ proposalTime[r] - Precision <= t
               /\ t <= proposalTime[r] + Precision)

\* [PBTS-CONSENSUS-REALTIME-VALID.0]
ConsensusRealTimeValid ==
    \A t \in Timestamps, r \in Rounds :
       (\E p \in Corr : 
        decision[p] /= NilDecision /\ decision[p][2] = r /\ decision[p][1].timestamp = t) 
        => /\ proposalReceivedTime[r] - Precision < t
           /\ t < proposalReceivedTime[r] + Precision + Delay

DecideAfterMin == TRUE

\* [PBTS-MSG-FAIR.0]
BoundedDelay ==
    \A r \in Rounds : 
        (/\ proposalTime[r] /= NilTimestamp
         /\ proposalTime[r] + Delay < realTime)
            => \A p \in Corr: inspectedProposal[r,p] /= NilTimestamp

\* [PBTS-CONSENSUS-TIME-LIVE.0]
ConsensusTimeLive ==
    \A r \in Rounds, p \in Corr : 
       (/\ proposalTime[r] /= NilTimestamp
        /\ proposalTime[r] + Delay < realTime 
        /\ Proposer[r] \in Corr
        /\ round[p] <= r)
            => \E msg \in RoundProposals(r) : msg \in receivedTimelyProposal[p]

\* [HYBRID-SAFETY]
HybridSafety == 
    \A p \in Corr:
        decision[p] /= NilDecision => IsValid(decision[p][1])

Inv ==
    /\ AgreementOnValue 
    /\ ConsensusTimeValid
    /\ ConsensusSafeValidCorrProp
    /\ HybridSafety
    \* /\ ConsensusRealTimeValid
    \* /\ ConsensusRealTimeValidCorr
    \* /\ BoundedDelay

\* Liveness ==
\*     ConsensusTimeLive

\* [LIVENESS] Hệ thống cuối cùng phải chốt được một block hợp lệ
EventualDecision == <> (\E p \in Corr : step[p] = "DECIDED")

\* Yêu cầu tính công bằng (Fairness) để hệ thống thực sự chạy thay vì đứng im
Fairness == 
    /\ \A p \in Corr : WF_vars(MessageProcessing(p))
    /\ WF_vars(AdvanceRealTime)

LivenessSpec == Init /\ [][Next]_vars /\ Fairness
=============================================================================    
