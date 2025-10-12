package ffi_test

import (
	"encoding/json"
	"fmt"
	"os"
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

	os.Unsetenv("GREENER_INGRESS_ENDPOINT")
	os.Unsetenv("GREENER_INGRESS_API_KEY")
	os.Unsetenv("GREENER_DEVSETTINGS_GRPC_CHANNEL_TYPE")
	os.Setenv("GREENER_INGRESS_ENDPOINT", fmt.Sprintf("http://127.0.0.1:%d", port))
	os.Setenv("GREENER_INGRESS_API_KEY", "some-api-token")
	defer os.Unsetenv("GREENER_INGRESS_ENDPOINT")
	defer os.Unsetenv("GREENER_INGRESS_API_KEY")
	defer os.Unsetenv("GREENER_DEVSETTINGS_GRPC_CHANNEL_TYPE")

	a, reporterErr := ffi.NewGreenerReporter()
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

		os.Unsetenv("GREENER_SESSION_ID")
		os.Unsetenv("GREENER_SESSION_DESCRIPTION")
		os.Unsetenv("GREENER_SESSION_BAGGAGE")
		os.Unsetenv("GREENER_SESSION_LABELS")
		if id, exists := cPayload["id"]; exists && id != nil {
			if idStr, ok := id.(string); ok {
				os.Setenv("GREENER_SESSION_ID", idStr)
			} else {
				t.Fatal("id is not a string")
			}
		}
		if description, exists := cPayload["description"]; exists && description != nil {
			if descStr, ok := description.(string); ok {
				os.Setenv("GREENER_SESSION_DESCRIPTION", descStr)
			} else {
				t.Fatal("description is not a string")
			}
		}
		if baggage, exists := cPayload["baggage"]; exists && baggage != nil {
			baggageBytes, err := json.Marshal(baggage)
			if err != nil {
				t.Fatal(err)
			}
			os.Setenv("GREENER_SESSION_BAGGAGE", string(baggageBytes))
		}
		if labels, exists := cPayload["labels"]; exists && labels != nil {
			if labelsStr, ok := labels.(string); ok {
				os.Setenv("GREENER_SESSION_LABELS", labelsStr)
			} else {
				t.Fatal("labels is not a string")
			}
		}
		defer os.Unsetenv("GREENER_SESSION_ID")
		defer os.Unsetenv("GREENER_SESSION_DESCRIPTION")
		defer os.Unsetenv("GREENER_SESSION_BAGGAGE")
		defer os.Unsetenv("GREENER_SESSION_LABELS")

		se, err := a.CreateSession()
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
