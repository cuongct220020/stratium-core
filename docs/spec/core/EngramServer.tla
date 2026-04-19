----------------------- MODULE EngramServer -----------------------
EXTENDS Naturals, FiniteSets, TendermintPBT_002_draft

VARIABLES qcs,           \* Tập hợp các Quorum Certificates (QC)
          tcs            \* Tập hợp các Timeout Certificates (TC)

\* Gộp chung không gian trạng thái của Tendermint gốc và Tầng 3
vars_server == <<coreVars, temporalVars, invariantVars, bookkeepingVars, qcs, tcs>>

(* 1. KHỞI TẠO TẦNG SERVER *)
InitServer == 
    /\ Init \* Gọi hàm Init gốc của hộp đen Tendermint
    /\ qcs = {}
    /\ tcs = {}

(* 2. GẮN MÓC (HOOKS) ĐỂ SINH CHỨNG CHỈ TỪ CÁC HÀNH ĐỘNG CỦA TENDERMINT *)

\* Hook 1: Đạt siêu đa số Prevote -> Tạo QC tạm thời
Server_UponQuorumOfPrevotesAny(p) == 
    /\ UponQuorumOfPrevotesAny(p) \* Chạy logic lõi của Tendermint
    /\ \E MyEvidence \in SUBSET msgsPrevote[round[p]]:
        LET Voters == { m.src: m \in MyEvidence } IN
        /\ Cardinality(Voters) >= THRESHOLD2
        /\ qcs' = qcs \cup {[type |-> "QC", round |-> round[p], signers |-> Voters]}
    /\ UNCHANGED tcs

\* Hook 2: Quyết định chốt block -> Tạo Commit QC chính thức
Server_UponProposalInPrecommitNoDecision(p) ==
    /\ UponProposalInPrecommitNoDecision(p)
    /\ \E v \in ValidValues, t \in Timestamps, r \in Rounds, pr \in Rounds, vr \in RoundsOrNil: 
        LET prop == Proposal(v,t,pr) 
            PV == { m \in msgsPrecommit[r]: m.id = Id(prop) } IN
        /\ Cardinality(PV) >= THRESHOLD2
        /\ qcs' = qcs \cup {[type |-> "COMMIT_QC", round |-> r, method |-> v, signers |-> {m.src: m \in PV}]}
    /\ UNCHANGED tcs

\* Hook 3: Đạt siêu đa số Precommit Timeout -> Tạo Timeout Certificate (TC)
Server_UponQuorumOfPrecommitsAny(p) ==
    /\ UponQuorumOfPrecommitsAny(p)
    /\ \E MyEvidence \in SUBSET msgsPrecommit[round[p]]:
        LET Committers == { m.src: m \in MyEvidence } IN
        /\ Cardinality(Committers) >= THRESHOLD2
        /\ tcs' = tcs \cup {[type |-> "TC", round |-> round[p], signers |-> Committers]}
    /\ UNCHANGED qcs

(* 3. BẮC CẦU (PASS-THROUGH) CÁC HÀNH ĐỘNG KHÔNG LIÊN QUAN ĐẾN CHỨNG CHỈ *)
Server_PassThrough(p) ==
    \/ ReceiveProposal(p)
    \/ UponProposalInPropose(p)
    \/ UponProposalInProposeAndPrevote(p)
    \/ UponProposalInPrevoteOrCommitAndPrevote(p)
    \/ OnTimeoutPropose(p)
    \/ OnQuorumOfNilPrevotes(p)
    \/ OnRoundCatchup(p)

(* 4. ĐÓNG GÓI CHU TRÌNH XỬ LÝ TIN NHẮN MỚI CHO TẦNG 3 *)
Server_MessageProcessing(p) ==
    \/ Server_PassThrough(p) /\ UNCHANGED <<qcs, tcs>>
    \/ Server_UponQuorumOfPrevotesAny(p)
    \/ Server_UponProposalInPrecommitNoDecision(p)
    \/ Server_UponQuorumOfPrecommitsAny(p)

(* 5. HÀM CHUYỂN TRẠNG THÁI TỔNG THỂ TẦNG SERVER *)
NextServer == 
    \/ AdvanceRealTime /\ UNCHANGED <<qcs, tcs>>
    \/ /\ SynchronizedLocalClocks 
       /\ \E p \in Corr: Server_MessageProcessing(p)

SpecServer == InitServer /\ [][NextServer]_vars_server

(* 6. ĐỊNH LÝ TINH CHỈNH: Chứng minh Tầng 3 tuân thủ tuyệt đối Tendermint gốc *)
Tendermint_Refinement == INSTANCE TendermintPBT_002_draft
THEOREM SpecServer => Tendermint_Refinement!Spec
===================================================================