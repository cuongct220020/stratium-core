package sovereignty

import (
    "context"
    "fmt"

    sdk "github.com/cosmos/cosmos-sdk/types"
    "github.com/cuongct220020/engram-sovereign-fsm/x/sovereignty/keeper"
    "github.com/cuongct220020/engram-sovereign-fsm/x/sovereignty/types"
)


func BeginBlocker(ctx context.Context, k *keeper.Keeper) error {
    sdkCtx := sdk.UnwrapSDKContext(ctx)

    // 1. Lấy dữ liệu ngoại vi hiện tại từ Storage (đã đồng thuận qua các block trước)
    metrics, err := k.Metrics.Get(ctx)
    if err != nil {
        // Nếu chưa có dữ liệu, coi như ANCHORED
        metrics = types.PeripheralMetrics{BitcoinFinalityGap: 0, DaReceiptValid: true, P2PQualityHealthy: true}
    }

    currState, err := k.FSMState.Get(ctx)
    if err != nil {
        currState = types.StateAnchored // Default State
    }

    // 2. Tính toán trạng thái tiếp theo dựa trên logic FSM (TLA+ Refinement)
    nextState := keeper.CalculateNextState(currState, metrics)

    // 3. Nếu có sự thay đổi trạng thái, thực hiện cập nhật và emit event
    if nextState != currState {
        err := k.FSMState.Set(ctx, nextState)
        if err != nil {
            return err
        }

        // Emit event để log lại timeline thực nghiệm (RQ4)
        sdkCtx.EventManager().EmitEvent(
            sdk.NewEvent(
                types.EventTypeFSMTransition,
                sdk.NewAttribute(types.AttributeKeyOldState, currState),
                sdk.NewAttribute(types.AttributeKeyNewState, nextState),
                sdk.NewAttribute(types.AttributeKeyBTCGap, fmt.Sprintf("%d", metrics.BitcoinFinalityGap)),
            ),
        )

        // Log ra console để tiện theo dõi lúc chạy test
        sdkCtx.Logger().Info("Engram FSM Transition", 
            "from", currState, 
            "to", nextState, 
            "height", sdkCtx.BlockHeight(),
        )
    }

    // 4. Nếu đang ở trạng thái RECOVERING, tăng bộ đếm SafeBlocks để chuẩn bị Re-anchoring
    if nextState == types.StateRecovering {
        currentSafeBlocks, _ := k.SafeBlocks.Get(ctx)
        k.SafeBlocks.Set(ctx, currentSafeBlocks + 1)
    } else {
        // Reset nếu không ở trạng thái RECOVERING
        k.SafeBlocks.Set(ctx, 0)
    }

    return nil
}