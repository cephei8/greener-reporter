package reporter

import (
	"sync"
	"sync/atomic"
	"time"
)

const (
	batcherChannelCap = 100
	batchSize         = 100
	batchTimeout      = 5 * time.Second
)

type batcherMessage struct {
	testcase *TestcaseRequest
	shutdown bool
}

type Batcher struct {
	ingress     *IngressClient
	messages    chan batcherMessage
	isAccepting atomic.Bool
	errors      []error
	errorsMu    sync.Mutex
	done        chan struct{}
	wg          sync.WaitGroup
}

func NewBatcher(ingress *IngressClient) *Batcher {
	b := &Batcher{
		ingress:  ingress,
		messages: make(chan batcherMessage, batcherChannelCap),
		errors:   make([]error, 0),
		done:     make(chan struct{}),
	}
	b.isAccepting.Store(true)

	b.wg.Add(1)
	go b.worker()

	return b
}

func (b *Batcher) worker() {
	defer b.wg.Done()

	batch := make([]TestcaseRequest, 0, batchSize)
	ticker := time.NewTicker(batchTimeout)
	defer ticker.Stop()

	for {
		select {
		case msg := <-b.messages:
			if msg.shutdown {
				if len(batch) > 0 {
					if err := b.ingress.CreateTestcases(batch); err != nil {
						b.addError(err)
					}
				}
				return
			}

			if msg.testcase != nil {
				batch = append(batch, *msg.testcase)
				if len(batch) >= batchSize {
					if err := b.ingress.CreateTestcases(batch); err != nil {
						b.addError(err)
					}
					batch = make([]TestcaseRequest, 0, batchSize)
					ticker.Reset(batchTimeout)
				}
			}

		case <-ticker.C:
			if len(batch) > 0 {
				if err := b.ingress.CreateTestcases(batch); err != nil {
					b.addError(err)
				}
				batch = make([]TestcaseRequest, 0, batchSize)
			}
		}
	}
}

func (b *Batcher) addError(err error) {
	b.errorsMu.Lock()
	defer b.errorsMu.Unlock()
	b.errors = append(b.errors, err)
}

func (b *Batcher) Add(testcase TestcaseRequest) error {
	if !b.isAccepting.Load() {
		return nil
	}

	select {
	case b.messages <- batcherMessage{testcase: &testcase}:
		return nil
	default:
		return NewUnknownError("batcher queue is full")
	}
}

func (b *Batcher) Shutdown() error {
	b.isAccepting.Store(false)
	b.messages <- batcherMessage{shutdown: true}
	b.wg.Wait()
	close(b.done)
	return nil
}

func (b *Batcher) PopError() error {
	b.errorsMu.Lock()
	defer b.errorsMu.Unlock()

	if len(b.errors) == 0 {
		return nil
	}

	err := b.errors[0]
	b.errors = b.errors[1:]
	return err
}
