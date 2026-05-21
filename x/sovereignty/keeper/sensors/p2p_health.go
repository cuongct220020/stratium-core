type P2PSensor struct {
    node p2p.Switch // Reference đến P2P Switch của CometBFT
}

func (s *P2PSensor) GetMetric(ctx context.Context) (uint64, error) {
    // Đọc số lượng peer đang kết nối hoặc độ trễ ping
    peers := s.node.Peers().Size()
    if peers < MIN_PEERS { return 1, nil } // P2P unhealthy
    return 0, nil
}