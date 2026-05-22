package types

type PeripheralSnapshot struct {
	BitcoinFinalityGap uint64 // T_delta (số block BTC chưa có anchor)
	DAReceiptValidated bool   // Celestia DA attestation
	P2PQualityHealthy  bool   // Kết quả từ Tri-interface Profiler
}

type PeripheralMetrics struct {
    BitcoinFinalityGap      uint64 `json:"btc_finality_gap"`
    DaReceiptValid          bool   `json:"da_receipt_valid"`
    P2PQualityHealthy       bool   `json:"p2p_quality_healthy"`
    IsReanchoringProofValid bool   `json:"is_reanchoring_proof_valid"` // Thêm field này
}

type PeripheralSensorEngine interface {
	GetLocalSnapshot() (PeripheralSnapshot, error)
	InjectFaultScenario(scenarioID string) // Phục vụ trực tiếp cho E2-E9
}