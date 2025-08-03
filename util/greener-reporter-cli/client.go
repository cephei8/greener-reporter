package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
)

type Client struct {
	httpClient *http.Client
	endpoint   string
	apiKey     string
}

func NewClient(endpoint, apiKey string) Client {
	return Client{
		httpClient: &http.Client{},
		endpoint:   endpoint,
		apiKey:     apiKey,
	}
}

type TestcaseStatus string

const (
	StatusPass TestcaseStatus = "pass"
	StatusFail TestcaseStatus = "fail"
	StatusErr  TestcaseStatus = "error"
	StatusSkip TestcaseStatus = "skip"
)

type TestcaseRequest struct {
	SessionID         string         `json:"sessionId"`
	TestcaseName      string         `json:"testcaseName"`
	TestcaseClassname *string        `json:"testcaseClassname,omitempty"`
	TestcaseFile      *string        `json:"testcaseFile,omitempty"`
	Testsuite         *string        `json:"testsuite,omitempty"`
	Status            TestcaseStatus `json:"status"`
	Output            *string        `json:"output,omitempty"`
	Baggage           map[string]any `json:"baggage,omitempty"`
}

type TestcasesRequest struct {
	Testcases []TestcaseRequest `json:"testcases"`
}

type SessionRequest struct {
	ID          *string        `json:"id,omitempty"`
	Description *string        `json:"description,omitempty"`
	Baggage     map[string]any `json:"baggage,omitempty"`
	Labels      []Label        `json:"labels,omitempty"`
}

type Label struct {
	Key   string  `json:"key"`
	Value *string `json:"value,omitempty"`
}

type SessionResponse struct {
	ID string `json:"id"`
}

type ErrorResponse struct {
	Detail string `json:"detail"`
}

func (c *Client) CreateSession(req SessionRequest) (string, error) {
	url := fmt.Sprintf("%s/api/v1/ingress/sessions", c.endpoint)

	jsonData, err := json.Marshal(req)
	if err != nil {
		return "", fmt.Errorf("error marshaling session request: %w", err)
	}

	httpReq, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("error creating session request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("X-API-Key", c.apiKey)

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("error sending session request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var errorResp ErrorResponse
		if err := json.NewDecoder(resp.Body).Decode(&errorResp); err != nil {
			return "", fmt.Errorf("failed session request (%d)", resp.StatusCode)
		}
		return "", fmt.Errorf("failed session request (%d): %s", resp.StatusCode, errorResp.Detail)
	}

	var sessionResp SessionResponse
	if err := json.NewDecoder(resp.Body).Decode(&sessionResp); err != nil {
		return "", fmt.Errorf("error parsing session response: %w", err)
	}

	return sessionResp.ID, nil
}

func (c *Client) CreateTestcases(testcases []TestcaseRequest) error {
	url := fmt.Sprintf("%s/api/v1/ingress/testcases", c.endpoint)

	req := TestcasesRequest{Testcases: testcases}
	jsonData, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("error marshaling testcases request: %w", err)
	}

	httpReq, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("error creating testcases request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("X-API-Key", c.apiKey)

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return fmt.Errorf("error sending testcases request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var errorResp ErrorResponse
		if err := json.NewDecoder(resp.Body).Decode(&errorResp); err != nil {
			return fmt.Errorf("failed testcases request (%d)", resp.StatusCode)
		}
		return fmt.Errorf("failed testcases request (%d): %s", resp.StatusCode, errorResp.Detail)
	}

	return nil
}
