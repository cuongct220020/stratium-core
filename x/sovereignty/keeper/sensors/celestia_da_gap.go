package sensors

type DASensor struct {
	isAvailable bool
}

func (s *DASensor) GetMetric(ctx context.Context) (uint64, error) {
	if s.isAvailable {
		return 0, nil
	} // 0 = No gap
	return 1, nil // 1 = DA Gap detected
}
