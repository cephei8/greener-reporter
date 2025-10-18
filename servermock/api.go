package servermock

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
)

type serverState struct {
	responses     map[string]any
	recordedCalls []Call
	mu            sync.Mutex
}

func startServer(responses string) (int, *serverState, error) {
	var responsesMap map[string]any
	if err := json.Unmarshal([]byte(responses), &responsesMap); err != nil {
		return 0, nil, fmt.Errorf("failed to parse responses: %w", err)
	}

	state := &serverState{
		responses:     responsesMap,
		recordedCalls: make([]Call, 0),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/ingress/sessions", state.createSession)
	mux.HandleFunc("/api/v1/ingress/testcases", state.createTestcases)

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, nil, fmt.Errorf("failed to bind to address: %w", err)
	}

	port := listener.Addr().(*net.TCPAddr).Port

	go func() {
		http.Serve(listener, mux)
	}()

	return port, state, nil
}

func (s *serverState) createSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var session map[string]any
	if err := json.NewDecoder(r.Body).Decode(&session); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if labels, ok := session["labels"]; ok && labels != nil {
		if labelsArray, ok := labels.([]any); ok {
			var labelStrs []string
			for _, label := range labelsArray {
				if labelMap, ok := label.(map[string]any); ok {
					if key, ok := labelMap["key"].(string); ok {
						if value, ok := labelMap["value"].(string); ok && value != "" {
							labelStrs = append(labelStrs, fmt.Sprintf("%s=%s", key, value))
						} else {
							labelStrs = append(labelStrs, key)
						}
					}
				}
			}
			session["labels"] = strings.Join(labelStrs, ",")
		}
	}

	payloadBytes, _ := json.Marshal(session)

	s.mu.Lock()
	s.recordedCalls = append(s.recordedCalls, Call{
		Func:    "createSession",
		Payload: payloadBytes,
	})
	s.mu.Unlock()

	createSessionResponse, ok := s.responses["createSessionResponse"].(map[string]any)
	if !ok {
		http.Error(w, "Invalid createSessionResponse", http.StatusInternalServerError)
		return
	}

	status, _ := createSessionResponse["status"].(string)
	payload := createSessionResponse["payload"]

	w.Header().Set("Content-Type", "application/json")

	switch status {
	case "success":
		w.WriteHeader(http.StatusOK)
		if payloadMap, ok := payload.(map[string]any); ok {
			if id, ok := payloadMap["id"]; ok {
				json.NewEncoder(w).Encode(map[string]any{"id": id})
				return
			}
		}
		json.NewEncoder(w).Encode(payload)
	case "error":
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(payload)
	default:
		http.Error(w, "Invalid status", http.StatusInternalServerError)
	}
}

func (s *serverState) createTestcases(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var testcase map[string]any
	if err := json.NewDecoder(r.Body).Decode(&testcase); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	payloadBytes, _ := json.Marshal(testcase)

	s.mu.Lock()
	s.recordedCalls = append(s.recordedCalls, Call{
		Func:    "report",
		Payload: payloadBytes,
	})
	s.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")

	status := "success"
	if statusVal, ok := s.responses["status"].(string); ok {
		status = statusVal
	}

	switch status {
	case "success":
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{})
	case "error":
		reportResponse, ok := s.responses["reportResponse"].(map[string]any)
		if !ok {
			http.Error(w, "Invalid reportResponse", http.StatusInternalServerError)
			return
		}
		payload := reportResponse["payload"]
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(payload)
	default:
		http.Error(w, "Invalid status", http.StatusInternalServerError)
	}
}
