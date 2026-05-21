type BTCSensor struct {
    mockGap uint64 // Dùng để ép kịch bản E4/E5
}

func (s *BTCSensor) GetMetric(ctx context.Context) (uint64, error) {
    // Nếu ở chế độ test, trả về mockGap. Nếu ở production, call RPC của Bitcoin.
    return s.mockGap, nil 
}