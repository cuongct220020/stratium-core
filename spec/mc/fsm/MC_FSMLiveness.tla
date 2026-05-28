---------------- MODULE MC_FSMLiveness ----------------
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

MC_FSMTransition == 
    /\ state' = CalculateNextFSMState
    /\ ExecuteFSMTransition(state')
    /\  \/ state' /= state 
        \/ suspicious_duration' /= suspicious_duration 
        \/ safe_blocks' /= safe_blocks
    /\ UNCHANGED <<coreVars, temporalVars, envVars>> 
    /\ UNCHANGED <<bookkeepingVars, invariantVars, censorVars>>
    /\ UNCHANGED <<qcs, tcs>>

MC_FSMUpdateSensors == 
    /\ h_btc_current' \in {0, 5}
    /\ h_btc_submitted' \in {0, h_btc_current'}
    /\ h_btc_anchored' \in {0, h_btc_submitted'}
    /\ h_engram_current' \in {0, 5}
    /\ h_engram_verified' \in {0, h_engram_current'}
    /\ is_das_failed' \in BOOLEAN
    \* Mô phỏng xáo trộn P2P
    /\ active_peers' \in { anchor_peers, anchor_peers \cup {"honest_n1"}, {"sybil_n1"} }
    /\ peer_churn_rate' \in {0, MAX_CHURN_RATE + 1}
    /\ avg_peer_tenure' \in {0, MIN_AVG_TENURE + 1}
    /\ peer_latency'    \in {0, MAX_PEER_LATENCY + 1}
    /\ UNCHANGED <<anchor_peers, blacklisted_peers>>
    /\ UNCHANGED <<state, safe_blocks, suspicious_duration, reanchoring_proof_valid>>
    /\ UNCHANGED <<coreVars, temporalVars, bookkeepingVars, invariantVars>>
    /\ UNCHANGED <<censorVars>>
    /\ UNCHANGED <<qcs, tcs>>

MC_GenerateZKProof == 
    /\ state = "RECOVERING"             
    /\ IsHealthyCondition               
    /\ reanchoring_proof_valid = FALSE  
    /\ reanchoring_proof_valid' = TRUE  
    /\ UNCHANGED <<state, safe_blocks, suspicious_duration>>
    /\ UNCHANGED <<btcSensorVars, daSensorVars, p2pSensorVars>>
    /\ UNCHANGED <<coreVars, temporalVars, bookkeepingVars, invariantVars, censorVars, qcs, tcs, anchor_peers, blacklisted_peers>>

MC_FSMLivenessNext == 
    \/ MC_FSMTransition
    \/ MC_FSMUpdateSensors
    \* \/ MC_GenerateZKProof

MC_FSMLivenessFairness == 
    /\ WF_fsmVars(MC_FSMTransition)
    \* /\ SF_serverVars(MC_GenerateZKProof)

MC_FSMLivenessSpec == 
    /\ MC_FSMInit
    /\ [][MC_FSMLivenessNext]_serverVars 
    /\ MC_FSMLivenessFairness

=========================================================
