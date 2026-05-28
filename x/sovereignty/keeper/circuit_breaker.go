package keeper

import (
	"github.com/cuongct220020/engram-sovereign-fsm/x/sovereignty/types"
)

// CalculateNextState thực thi logic chuyển trạng thái FSM (The "Brain")
func CalculateNextState(currentState string, m types.PeripheralMetrics) string {
	// 1. HIGH-PRIORITY FALLBACK:
	// Nếu vi phạm điều kiện an toàn cốt lõi, bất kể đang ở trạng thái nào cũng phải về SOVEREIGN.
	if m.BitcoinFinalityGap >= 6 || !m.DaReceiptValid {
		return types.StateSovereign
	}

	// 2. FSM TRANSITIONS
	switch currentState {

	case types.StateAnchored:
		// Chuyển sang SUSPICIOUS nếu bắt đầu thấy dấu hiệu BTC gap
		if m.BitcoinFinalityGap >= 2 {
			return types.StateSuspicious
		}

	case types.StateSuspicious:
		// Hồi phục về ANCHORED nếu mạng ổn định trở lại
		if m.BitcoinFinalityGap < 2 {
			return types.StateAnchored
		}

	case types.StateSovereign:
		// Bắt đầu quá trình hồi phục nếu mạng lưới P2P ổn định
		if m.P2PQualityHealthy {
			return types.StateRecovering
		}

	case types.StateRecovering:
		// Hoàn tất phục hồi: P2P tốt + ZK Proof đã được xác thực (hợp lệ)
		// Lưu ý: Bạn cần đảm bảo m.IsReanchoringProofValid được cập nhật từ module ZK/Reanchor
		if m.P2PQualityHealthy && m.IsReanchoringProofValid {
			return types.StateAnchored
		}
		// Nếu đang hồi phục mà P2P hỏng, quay lại SOVEREIGN
		if !m.P2PQualityHealthy {
			return types.StateSovereign
		}
	}

	// Mặc định giữ nguyên trạng thái nếu không có điều kiện nào thỏa mãn
	return currentState
}
