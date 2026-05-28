package keeper

import (
	"context"
	"github.com/cuongct220020/engram-sovereign-fsm/x/sovereignty/types"
)

type MsgServerImpl struct {
	*Keeper
}

func NewMsgServerImpl(k *Keeper) types.MsgServer {
	return &MsgServerImpl{Keeper: k}
}

// InjectFault: Dành cho test/thực nghiệm
func (k *MsgServerImpl) InjectFault(ctx context.Context, msg *types.MsgInjectFault) (*types.MsgInjectFaultResponse, error) {
	k.Metrics.Set(ctx, msg.FaultInputs)
	return &types.MsgInjectFaultResponse{}, nil
}

// SubmitRecoveryProof: Gắn kết mạch Noir với hệ thống
func (k *MsgServerImpl) SubmitRecoveryProof(ctx context.Context, msg *types.MsgSubmitRecoveryProof) (*types.MsgSubmitRecoveryProofResponse, error) {
	// 1. Verify ZK Proof
	if !k.VerifyZKProof(msg.Proof, msg.PublicInputs) {
		return nil, types.ErrInvalidZKProof
	}

	// 2. Chuyển FSM về ANCHORED (Hoàn tất phục hồi)
	k.FSMState.Set(ctx, types.StateAnchored)
	return &types.MsgSubmitRecoveryProofResponse{}, nil
}
