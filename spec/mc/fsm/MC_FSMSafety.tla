------------------- MODULE MC_FSMSafety -------------------
EXTENDS EngramFSM, TLC

MC_MockInit == 
    /\ round = 0 /\ step = 0 /\ decision = 0 /\ locked_value = 0 /\ locked_round = 0 /\ valid_value = 0 /\ valid_round = 0
    /\ local_clock = 0 /\ real_time = 0 /\ local_rem_time = 0
    /\ msgs_propose = 0 /\ msgs_prevote = 0 /\ msgs_precommit = 0 /\ msgs_timeout = 0 /\ evidence = 0 /\ action = "mock" /\ received_timely_proposal = 0 /\ inspected_proposal = 0
    /\ begin_round = 0 /\ end_consensus = 0 /\ last_begin_round = 0 /\ proposal_time = 0 /\ proposal_received_time = 0
    /\ forced_tx_queue = 0 /\ tx_ignored_rounds = 0
    /\ qcs = {} /\ tcs = {}

MC_FSMInit == 
    /\ FSMInit 
    /\ MC_MockInit

MC_FSMNext == 
    /\ FSMNext
    /\ UNCHANGED <<coreVars, temporalVars>>
    /\ UNCHANGED <<bookkeepingVars, invariantVars, censorVars>>
    /\ UNCHANGED <<qcs, tcs>>

StateSpaceLimit == 
    /\ h_btc_current < 10 
    /\ h_engram_current < 10

=========================================================