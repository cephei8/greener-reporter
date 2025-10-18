package reporter

type Reporter struct {
	ingress *IngressClient
	batcher *Batcher
}

func New(endpoint, apiKey string) (*Reporter, error) {
	if endpoint == "" {
		return nil, NewInvalidArgumentError("endpoint cannot be empty")
	}
	if apiKey == "" {
		return nil, NewInvalidArgumentError("api_key cannot be empty")
	}

	ingress := NewIngressClient(endpoint, apiKey)
	batcher := NewBatcher(ingress)

	return &Reporter{
		ingress: ingress,
		batcher: batcher,
	}, nil
}

func (r *Reporter) CreateSession(session SessionRequest) (*Session, error) {
	id, err := r.ingress.CreateSession(session)
	if err != nil {
		return nil, err
	}

	return &Session{Id: id}, nil
}

func (r *Reporter) AddTestcase(testcase TestcaseRequest) error {
	return r.batcher.Add(testcase)
}

func (r *Reporter) Shutdown() error {
	return r.batcher.Shutdown()
}

func (r *Reporter) PopError() error {
	return r.batcher.PopError()
}
