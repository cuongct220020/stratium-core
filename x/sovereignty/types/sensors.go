package types

type PeripheralSnapshot struct {
	BitcoinFinalityGap uint64 // T_delta (số block BTC chưa có anchor)
	DAReceiptValidated bool   // Celestia DA attestation
	P2PQualityHealthy  bool   // Kết quả từ Tri-interface Profiler
}

type PeripheralSensorEngine interface {
	GetLocalSnapshot() (PeripheralSnapshot, error)
	InjectFaultScenario(scenarioID string) // Phục vụ trực tiếp cho E2-E9
}