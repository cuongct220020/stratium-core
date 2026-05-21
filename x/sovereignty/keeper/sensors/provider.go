package sensors

import "context"

type SensorProvider interface {
    GetMetric(ctx context.Context) (uint64, error)
}