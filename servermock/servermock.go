package servermock

import (
	"encoding/json"
	"fmt"
	"sync"
)

type ApiCalls struct {
	Calls []Call `json:"calls"`
}

type GreenerServermock struct {
	port          int
	responses     string
	fixtures      map[string]Fixture
	recordedCalls *[]Call
	mu            *sync.Mutex
	stopServer    func()
}

func New() *GreenerServermock {
	recordedCalls := make([]Call, 0)
	mu := &sync.Mutex{}

	return &GreenerServermock{
		port:          -1,
		responses:     "",
		fixtures:      createFixtures(),
		recordedCalls: &recordedCalls,
		mu:            mu,
	}
}

func (s *GreenerServermock) Port() int {
	return s.port
}

func (s *GreenerServermock) Serve(responses string) error {
	s.responses = responses

	port, state, err := startServer(responses)
	if err != nil {
		return fmt.Errorf("failed to start server: %w", err)
	}

	s.port = port
	s.recordedCalls = &state.recordedCalls
	s.mu = &state.mu

	return nil
}

func (s *GreenerServermock) Assert(expectedCalls string) error {
	s.mu.Lock()
	recorded := make([]Call, len(*s.recordedCalls))
	copy(recorded, *s.recordedCalls)
	s.mu.Unlock()

	var expected ApiCalls
	if err := json.Unmarshal([]byte(expectedCalls), &expected); err != nil {
		return fmt.Errorf("failed to parse expected calls: %w", err)
	}

	if len(recorded) != len(expected.Calls) {
		return fmt.Errorf("call count mismatch. expected %d calls but got %d.\nexpected: %#v\nactual: %#v",
			len(expected.Calls), len(recorded), expected, recorded)
	}

	for i, expectedCall := range expected.Calls {
		actualCall := recorded[i]

		if expectedCall.Func != actualCall.Func {
			return fmt.Errorf("call %d function mismatch. Expected '%s' but got '%s'",
				i, expectedCall.Func, actualCall.Func)
		}

		expectedPayload := expectedCall.Payload
		actualPayload := actualCall.Payload

		var expectedJSON, actualJSON interface{}
		if err := json.Unmarshal(expectedPayload, &expectedJSON); err != nil {
			return fmt.Errorf("failed to parse expected payload: %w", err)
		}
		if err := json.Unmarshal(actualPayload, &actualJSON); err != nil {
			return fmt.Errorf("failed to parse actual payload: %w", err)
		}

		expectedBytes, _ := json.Marshal(expectedJSON)
		actualBytes, _ := json.Marshal(actualJSON)

		if string(expectedBytes) != string(actualBytes) {
			expectedPretty, _ := json.MarshalIndent(expectedJSON, "", "  ")
			actualPretty, _ := json.MarshalIndent(actualJSON, "", "  ")
			return fmt.Errorf("call %d payload mismatch.\nexpected: %s\nactual: %s",
				i, string(expectedPretty), string(actualPretty))
		}
	}

	return nil
}

func (s *GreenerServermock) FixtureNames() []string {
	names := make([]string, 0, len(s.fixtures))
	for name := range s.fixtures {
		names = append(names, name)
	}
	return names
}

func (s *GreenerServermock) FixtureCalls(name string) (string, error) {
	fixture, ok := s.fixtures[name]
	if !ok {
		return "", fmt.Errorf("fixture not found: %s", name)
	}

	calls := ApiCalls{Calls: fixture.Calls}
	callsJSON, err := json.Marshal(calls)
	if err != nil {
		return "", fmt.Errorf("failed to marshal fixture calls: %w", err)
	}

	return string(callsJSON), nil
}

func (s *GreenerServermock) FixtureResponses(name string) (string, error) {
	fixture, ok := s.fixtures[name]
	if !ok {
		return "", fmt.Errorf("fixture not found: %s", name)
	}

	responses := map[string]Response{
		"createSessionResponse": fixture.Responses.CreateSessionResponse,
		"reportResponse":        fixture.Responses.ReportResponse,
	}

	responsesJSON, err := json.Marshal(responses)
	if err != nil {
		return "", fmt.Errorf("failed to marshal fixture responses: %w", err)
	}

	return string(responsesJSON), nil
}
