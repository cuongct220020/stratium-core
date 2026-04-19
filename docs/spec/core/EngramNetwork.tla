----------------------- MODULE EngramNetwork -----------------------
EXTENDS Naturals, FiniteSets

\* KHAI BÁO BIẾN ĐỘC LẬP
\* 1. Biến của riêng tầng Network
VARIABLES sent_msgs, deliv_msgs
\* 2. Khai báo lại các biến của tầng Voting để chứa trạng thái (Không dùng EXTENDS)
VARIABLES round, step, decision, lockedValue, lockedRound, validValue, validRound, 
          localClock, realTime, msgsPropose, msgsPrevote, msgsPrecommit, evidence, 
          action, receivedTimelyProposal, inspectedProposal, beginRound, endConsensus, 
          lastBeginRound, proposalTime, proposalReceivedTime, qcs, tcs, btc_connection

vars_voting == <<round, step, decision, lockedValue, lockedRound, validValue, validRound, localClock, realTime, msgsPropose, msgsPrevote, msgsPrecommit, evidence, action, receivedTimelyProposal, inspectedProposal, beginRound, endConsensus, lastBeginRound, proposalTime, proposalReceivedTime, qcs, tcs, btc_connection>>
vars_net == <<sent_msgs, deliv_msgs, vars_voting>>

(* BEST PRACTICE 1: DÙNG INSTANCE THAY VÌ EXTENDS *)
\* TLA+ sẽ tự động ánh xạ các biến cùng tên xuống tầng Voting (Implicit Substitution) [1].
Voting == INSTANCE EngramVoting

(* KHỞI TẠO MẠNG *)
InitNetwork == 
    /\ Voting!Init 
    /\ sent_msgs = {}
    /\ deliv_msgs = {}

(* CÁC HÀNH ĐỘNG MẠNG *)
Send(msg) == 
    /\ sent_msgs' = sent_msgs \cup {msg}
    /\ UNCHANGED <<deliv_msgs, vars_voting>>

Deliver(msg, dest) == 
    /\ msg \in sent_msgs
    /\ <<msg, dest>> \notin deliv_msgs
    /\ deliv_msgs' = deliv_msgs \cup {<<msg, dest>>}
    /\ Voting!MessageProcessing(dest) \* Tích hợp logic xử lý của Tendermint
    /\ UNCHANGED sent_msgs

NextNetwork == 
    \/ \E msg \in Voting!Messages : Send(msg)
    \/ \E msg \in sent_msgs, dest \in Voting!Corr : Deliver(msg, dest)
    \/ Voting!AdvanceRealTime /\ UNCHANGED <<sent_msgs, deliv_msgs>>

(* BEST PRACTICE 2: BỔ SUNG FAIRNESS CHO LIVENESS *)
SpecNetwork == 
    /\ InitNetwork 
    /\ [][NextNetwork]_vars_net 
    /\ WF_vars_net(NextNetwork) \* Đảm bảo hệ thống luôn tiến lên phía trước [2]

(* BEST PRACTICE 3: KHAI BÁO THEOREM CHỨNG MINH REFINEMENT *)
THEOREM SpecNetwork => Voting!Spec \* Ép TLC kiểm chứng mọi lỗi mạng đều an toàn với Tendermint [3]
======================================================================