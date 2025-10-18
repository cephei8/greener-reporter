package reporter

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

type IngressClient struct {
	client   *http.Client
	endpoint string
	apiKey   string
}

func NewIngressClient(endpoint, apiKey string) *IngressClient {
	return &IngressClient{
		client:   &http.Client{},
		endpoint: endpoint,
		apiKey:   apiKey,
	}
}

func (c *IngressClient) CreateSession(session SessionRequest) (string, error) {
	url := fmt.Sprintf("%s/api/v1/ingress/sessions", c.endpoint)

	body, err := json.Marshal(session)
	if err != nil {
		return "", NewUnknownError(fmt.Sprintf("error marshaling session request: %v", err))
	}

	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return "", NewUnknownError(fmt.Sprintf("error creating session request: %v", err))
	}

	req.Header.Set("X-API-Key", c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return "", NewUnknownError(fmt.Sprintf("error sending session request: %v", err))
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		errorMsg := string(bodyBytes)

		var errResp ErrorResponse
		if err := json.Unmarshal(bodyBytes, &errResp); err == nil {
			errorMsg = errResp.Message
		}

		return "", NewIngressError(fmt.Sprintf("failed session request: %s", errorMsg), resp.StatusCode)
	}

	var sessionResp SessionResponse
	if err := json.NewDecoder(resp.Body).Decode(&sessionResp); err != nil {
		return "", NewUnknownError(fmt.Sprintf("error parsing session response: %v", err))
	}

	return sessionResp.Id, nil
}

func (c *IngressClient) CreateTestcases(testcases []TestcaseRequest) error {
	url := fmt.Sprintf("%s/api/v1/ingress/testcases", c.endpoint)

	reqBody := TestcasesRequest{Testcases: testcases}
	body, err := json.Marshal(reqBody)
	if err != nil {
		return NewUnknownError(fmt.Sprintf("error marshaling testcase request: %v", err))
	}

	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return NewUnknownError(fmt.Sprintf("error creating testcase request: %v", err))
	}

	req.Header.Set("X-API-KEY", c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return NewUnknownError(fmt.Sprintf("error sending testcase request: %v", err))
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		errorMsg := string(bodyBytes)

		var errResp ErrorResponse
		if err := json.Unmarshal(bodyBytes, &errResp); err == nil {
			errorMsg = errResp.Message
		}

		return NewIngressError(fmt.Sprintf("failed testcase request: %s", errorMsg), resp.StatusCode)
	}

	return nil
}
