package ffi_test

import (
	"encoding/json"
	"fmt"
	"testing"

	ffi "github.com/cephei8/greener-reporter/tests-ffi-go"
)

func getFixtureNames(t *testing.T) []string {
	t.Helper()

	names, err := ffi.GetFixtureNames()
	if err != nil {
		t.Fatal(err)
	}

	if names == nil {
		t.Fatal("names are nil")
	}
	if len(names) == 0 {
		t.Fatal("names are empty list")
	}

	t.Log("Fixture names:")
	for _, n := range names {
		t.Logf("- %s", n)
	}

	return names
}

func TestIntegration(t *testing.T) {
	fixtureNames := getFixtureNames(t)

	for _, fixtureName := range fixtureNames {
		t.Logf("Processing fixture %s", fixtureName)
		processFixture(t, fixtureName)
	}
}

func processFixture(t *testing.T, fixtureName string) {
	t.Helper()

	s := ffi.NewGreenerServermock()
	defer func() {
		if err := s.Delete(); err != nil {
			t.Error(err)
		}
	}()

	calls, err := s.FixtureCalls(fixtureName)
	if err != nil {
		t.Fatal(err)
	}
	resps, err := s.FixtureResponses(fixtureName)
	if err != nil {
		t.Fatal(err)
	}

	err = s.Serve(resps)
	if err != nil {
		t.Fatal(err)
	}

	port, err := s.GetPort()
	if err != nil {
		t.Fatal(err)
	}

	endpoint := fmt.Sprintf("http://127.0.0.1:%d", port)
	apiKey := "some-api-token"

	a, reporterErr := ffi.NewGreenerReporter(endpoint, apiKey)
	if reporterErr != nil {
		t.Fatal(reporterErr)
	}

	var callsData map[string]any
	if err := json.Unmarshal([]byte(calls), &callsData); err != nil {
		t.Fatal(err)
	}

	callsList, ok := callsData["calls"].([]any)
	if !ok {
		t.Fatal("calls is not an array")
	}

	for _, c := range callsList {
		makeCall(t, a, c, resps)
	}

	reporterErr = a.Delete()
	if reporterErr != nil {
		t.Error(reporterErr)
	}

	err = s.Assert(calls)
	if err != nil {
		t.Error(err)
	}
}

func makeCall(t *testing.T, a *ffi.GreenerReporter, c any, resps string) {
	t.Helper()

	call, ok := c.(map[string]any)
	if !ok {
		t.Fatal("call is not a map")
	}

	cFunc, ok := call["func"].(string)
	if !ok {
		t.Fatal("call func is not a string")
	}

	cPayload, ok := call["payload"].(map[string]any)
	if !ok {
		t.Fatal("call payload is not a map")
	}

	switch cFunc {
	case "createSession":
		var respsData map[string]any
		if err := json.Unmarshal([]byte(resps), &respsData); err != nil {
			t.Fatal(err)
		}

		r, ok := respsData["createSessionResponse"].(map[string]any)
		if !ok {
			t.Fatal("createSessionResponse is not a map")
		}

		rStatus, ok := r["status"].(string)
		if !ok {
			t.Fatal("status is not a string")
		}

		var sessionId *string
		var description *string
		var baggage *string
		var labels *string

		if id, exists := cPayload["id"]; exists && id != nil {
			if idStr, ok := id.(string); ok {
				sessionId = &idStr
			} else {
				t.Fatal("id is not a string")
			}
		}
		if desc, exists := cPayload["description"]; exists && desc != nil {
			if descStr, ok := desc.(string); ok {
				description = &descStr
			} else {
				t.Fatal("description is not a string")
			}
		}
		if bag, exists := cPayload["baggage"]; exists && bag != nil {
			baggageBytes, err := json.Marshal(bag)
			if err != nil {
				t.Fatal(err)
			}
			baggageStr := string(baggageBytes)
			baggage = &baggageStr
		}
		if lab, exists := cPayload["labels"]; exists && lab != nil {
			if labelsStr, ok := lab.(string); ok {
				labels = &labelsStr
			} else {
				t.Fatal("labels is not a string")
			}
		}

		se, err := a.CreateSession(sessionId, description, baggage, labels)
		defer func() {
			if err == nil {
				se.Delete()
			} else {
				err.Delete()
			}
		}()

		switch rStatus {
		case "success":
			if err != nil {
				t.Errorf("session creation failed: %v", err)
			} else {
				rPayload, ok := r["payload"].(map[string]any)
				if !ok {
					t.Fatal("payload is not a map")
				}
				expectedId, ok := rPayload["id"].(string)
				if !ok {
					t.Fatal("payload id is not a string")
				}
				if se.Id() != expectedId {
					t.Errorf(
						"incorrect session id: actual %s, expected %s",
						se.Id(), expectedId)
				}
			}
		case "error":
			if err == nil {
				t.Errorf("session creation succeeded, should've failed")
			}

			rPayload, ok := r["payload"].(map[string]any)
			if !ok {
				t.Fatal("payload is not a map")
			}

			expectedCode, ok := rPayload["code"].(float64)
			if !ok {
				t.Fatal("payload code is not a number")
			}
			if err.Code() != int64(expectedCode) {
				t.Errorf("incorrect error code: actual %d, expected %d",
					err.Code(), int64(expectedCode))
			}

			expectedIngressCode, ok := rPayload["ingressCode"].(float64)
			if !ok {
				t.Fatal("payload ingressCode is not a number")
			}
			if err.IngressCode() != int64(expectedIngressCode) {
				t.Errorf("incorrect error ingress code: actual %d, expected %d",
					err.IngressCode(), int64(expectedIngressCode))
			}

			expectedMessage, ok := rPayload["message"].(string)
			if !ok {
				t.Fatal("payload message is not a string")
			}
			if err.Message() != fmt.Sprintf("failed session request: %s", expectedMessage) {
				t.Errorf("incorrect error message: actual %s, expected %s",
					err.Message(), expectedMessage)
			}

		default:
			t.Fatalf("unknown resp 'status': %s", rStatus)
		}

	case "report":
		var respsData map[string]any
		if err := json.Unmarshal([]byte(resps), &respsData); err != nil {
			t.Fatal(err)
		}

		r, ok := respsData["reportResponse"].(map[string]any)
		if !ok {
			t.Fatal("reportResponse is not a map")
		}

		rStatus, ok := r["status"].(string)
		if !ok {
			t.Fatal("status is not a string")
		}

		errs := []*ffi.GreenerReporterError{}
		testcases, ok := cPayload["testcases"].([]any)
		if !ok {
			t.Fatal("testcases is not an array")
		}
		for _, cTestcasePayload := range testcases {
			cTestcase, ok := cTestcasePayload.(map[string]any)
			if !ok {
				t.Fatal("testcase is not a map")
			}
			testcaseClassname := (*string)(nil)
			testcaseFile := (*string)(nil)
			testsuite := (*string)(nil)

			if v, exists := cTestcase["testcaseClassname"]; exists && v != nil {
				if vStr, ok := v.(string); ok {
					testcaseClassname = &vStr
				}
			}
			if v, exists := cTestcase["testcaseFile"]; exists && v != nil {
				if vStr, ok := v.(string); ok {
					testcaseFile = &vStr
				}
			}
			if v, exists := cTestcase["testsuite"]; exists && v != nil {
				if vStr, ok := v.(string); ok {
					testsuite = &vStr
				}
			}

			sessionId, ok := cTestcase["sessionId"].(string)
			if !ok {
				t.Fatal("sessionId is not a string")
			}
			testcaseName, ok := cTestcase["testcaseName"].(string)
			if !ok {
				t.Fatal("testcaseName is not a string")
			}
			status, ok := cTestcase["status"].(string)
			if !ok {
				t.Fatal("status is not a string")
			}

			err := a.CreateTestcase(
				sessionId,
				testcaseName,
				testcaseClassname,
				testcaseFile,
				testsuite,
				status,
				nil,
			)
			errs = append(errs, err)

			defer func() {
				if err != nil {
					err.Delete()
				}
			}()
		}

		var err *ffi.GreenerReporterError = nil
		if len(errs) > 0 {
			// server responses are stubbed, so take the first one
			err = errs[0]
		}

		switch rStatus {
		case "success":
			if err != nil {
				t.Errorf("testcase creation failed: %v", err)
			}
		case "error":
			if err == nil {
				t.Errorf("testcase creation succeeded, should've failed")
			}

			rPayload, ok := r["payload"].(map[string]any)
			if !ok {
				t.Fatal("payload is not a map")
			}

			expectedCode, ok := rPayload["code"].(float64)
			if !ok {
				t.Fatal("payload code is not a number")
			}
			if err.Code() != int64(expectedCode) {
				t.Errorf("incorrect error code: actual %d, expected %d",
					err.Code(), int64(expectedCode))
			}

			expectedIngressCode, ok := rPayload["ingressCode"].(float64)
			if !ok {
				t.Fatal("payload ingressCode is not a number")
			}
			if err.IngressCode() != int64(expectedIngressCode) {
				t.Errorf("incorrect error ingress code: actual %d, expected %d",
					err.IngressCode(), int64(expectedIngressCode))
			}

			expectedMessage, ok := rPayload["message"].(string)
			if !ok {
				t.Fatal("payload message is not a string")
			}
			if err.Message() != expectedMessage {
				t.Errorf("incorrect error message: actual %s, expected %s",
					err.Message(), expectedMessage)
			}

		default:
			t.Fatalf("unknown resp 'status': %s", rStatus)
		}

	default:
		t.Fatalf("unknown call 'func': %s", cFunc)
	}
}
