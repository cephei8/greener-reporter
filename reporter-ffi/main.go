package main

/*
#include <stdlib.h>
#include <stdint.h>

struct greener_reporter_session {
    const char *id;
};

struct greener_reporter_error {
    int code;
    int ingress_code;
    const char *message;
};

enum {
    GREENER_REPORTER_ERROR = 1,
    GREENER_REPORTER_ERROR_INVALID_ARGUMENT = 2,
    GREENER_REPORTER_ERROR_INGRESS = 3,
};
*/
import "C"
import (
	"encoding/json"
	"runtime/cgo"
	"strings"
	"unsafe"

	reporter "github.com/cephei8/greener-reporter/reporter"
)

//export greener_reporter_new
func greener_reporter_new(
	cEndpoint *C.char,
	cApiKey *C.char,
	cError **C.struct_greener_reporter_error,
) C.uintptr_t {
	*cError = nil

	if cEndpoint == nil {
		setError(reporter.NewInvalidArgumentError("endpoint pointer is null"), cError)
		return 0
	}

	if cApiKey == nil {
		setError(reporter.NewInvalidArgumentError("api_key pointer is null"), cError)
		return 0
	}

	endpoint := C.GoString(cEndpoint)
	apiKey := C.GoString(cApiKey)

	r, err := reporter.New(endpoint, apiKey)
	if err != nil {
		if reporterErr, ok := err.(*reporter.ReporterError); ok {
			setError(reporterErr, cError)
		} else {
			setError(reporter.NewUnknownError(err.Error()), cError)
		}
		return 0
	}

	return C.uintptr_t(cgo.NewHandle(r))
}

//export greener_reporter_delete
func greener_reporter_delete(
	cReporter C.uintptr_t,
	cError **C.struct_greener_reporter_error,
) {
	*cError = nil

	if cReporter == 0 {
		return
	}

	h := cgo.Handle(cReporter)
	r := h.Value().(*reporter.Reporter)

	if err := r.Shutdown(); err != nil {
		if reporterErr, ok := err.(*reporter.ReporterError); ok {
			setError(reporterErr, cError)
		} else {
			setError(reporter.NewUnknownError(err.Error()), cError)
		}
	}

	h.Delete()
}

//export greener_reporter_session_create
func greener_reporter_session_create(
	cReporter C.uintptr_t,
	cSessionId *C.char,
	cDescription *C.char,
	cBaggage *C.char,
	cLabels *C.char,
	cError **C.struct_greener_reporter_error,
) *C.struct_greener_reporter_session {
	*cError = nil

	if cReporter == 0 {
		setError(reporter.NewInvalidArgumentError("reporter pointer is null"), cError)
		return nil
	}

	h := cgo.Handle(cReporter)
	r := h.Value().(*reporter.Reporter)

	var sessionId *string
	if cSessionId != nil {
		s := C.GoString(cSessionId)
		sessionId = &s
	}

	var description *string
	if cDescription != nil {
		s := C.GoString(cDescription)
		description = &s
	}

	var baggage map[string]any
	if cBaggage != nil {
		baggageStr := C.GoString(cBaggage)
		if err := json.Unmarshal([]byte(baggageStr), &baggage); err != nil {
			setError(reporter.NewInvalidArgumentError("cannot parse baggage: "+err.Error()), cError)
			return nil
		}
	}

	var labels []reporter.Label
	if cLabels != nil {
		labelsStr := C.GoString(cLabels)
		parts := strings.SplitSeq(labelsStr, ",")
		for part := range parts {
			part = strings.TrimSpace(part)
			if part == "" {
				continue
			}
			kv := strings.SplitN(part, "=", 2)
			label := reporter.Label{Key: kv[0]}
			if len(kv) == 2 {
				label.Value = &kv[1]
			}
			labels = append(labels, label)
		}
	}

	sessionReq := reporter.SessionRequest{
		Id:          sessionId,
		Description: description,
		Baggage:     baggage,
		Labels:      labels,
	}

	s, err := r.CreateSession(sessionReq)
	if err != nil {
		if reporterErr, ok := err.(*reporter.ReporterError); ok {
			setError(reporterErr, cError)
		} else {
			setError(reporter.NewUnknownError(err.Error()), cError)
		}
		return nil
	}

	cSession := (*C.struct_greener_reporter_session)(C.malloc(C.size_t(unsafe.Sizeof(C.struct_greener_reporter_session{}))))
	cSession.id = C.CString(s.Id)

	return cSession
}

//export greener_reporter_testcase_create
func greener_reporter_testcase_create(
	cReporter C.uintptr_t,
	cSessionId *C.char,
	cTestcaseName *C.char,
	cTestcaseClassname *C.char,
	cTestcaseFile *C.char,
	cTestsuite *C.char,
	cStatus *C.char,
	cOutput *C.char,
	cBaggage *C.char,
	cError **C.struct_greener_reporter_error,
) {
	*cError = nil

	if cReporter == 0 {
		setError(reporter.NewInvalidArgumentError("reporter pointer is null"), cError)
		return
	}

	h := cgo.Handle(cReporter)
	r := h.Value().(*reporter.Reporter)

	sessionId := C.GoString(cSessionId)
	testcaseName := C.GoString(cTestcaseName)

	var testcaseClassname *string
	if cTestcaseClassname != nil {
		s := C.GoString(cTestcaseClassname)
		testcaseClassname = &s
	}

	var testcaseFile *string
	if cTestcaseFile != nil {
		s := C.GoString(cTestcaseFile)
		testcaseFile = &s
	}

	var testsuite *string
	if cTestsuite != nil {
		s := C.GoString(cTestsuite)
		testsuite = &s
	}

	var output *string
	if cOutput != nil {
		s := C.GoString(cOutput)
		output = &s
	}

	var baggage map[string]any
	if cBaggage != nil {
		baggageStr := C.GoString(cBaggage)
		if err := json.Unmarshal([]byte(baggageStr), &baggage); err != nil {
			setError(reporter.NewInvalidArgumentError("cannot parse baggage: "+err.Error()), cError)
			return
		}
	}

	statusStr := C.GoString(cStatus)
	var testcaseStatus reporter.TestcaseStatus
	switch statusStr {
	case "pass":
		testcaseStatus = reporter.TestcaseStatusPass
	case "fail":
		testcaseStatus = reporter.TestcaseStatusFail
	case "error":
		testcaseStatus = reporter.TestcaseStatusError
	case "skip":
		testcaseStatus = reporter.TestcaseStatusSkip
	default:
		setError(reporter.NewInvalidArgumentError("invalid testcase status: "+statusStr), cError)
		return
	}

	testcaseReq := reporter.TestcaseRequest{
		SessionId:         sessionId,
		TestcaseName:      testcaseName,
		TestcaseClassname: testcaseClassname,
		TestcaseFile:      testcaseFile,
		Testsuite:         testsuite,
		Status:            testcaseStatus,
		Output:            output,
		Baggage:           baggage,
	}

	if err := r.AddTestcase(testcaseReq); err != nil {
		if reporterErr, ok := err.(*reporter.ReporterError); ok {
			setError(reporterErr, cError)
		} else {
			setError(reporter.NewUnknownError(err.Error()), cError)
		}
	}
}

//export greener_reporter_session_delete
func greener_reporter_session_delete(cSession *C.struct_greener_reporter_session) {
	if cSession == nil {
		return
	}

	if cSession.id != nil {
		C.free(unsafe.Pointer(cSession.id))
	}
	C.free(unsafe.Pointer(cSession))
}

//export greener_reporter_error_delete
func greener_reporter_error_delete(cError *C.struct_greener_reporter_error) {
	if cError == nil {
		return
	}

	if cError.message != nil {
		C.free(unsafe.Pointer(cError.message))
	}
	C.free(unsafe.Pointer(cError))
}

//export greener_reporter_report_error_pop
func greener_reporter_report_error_pop(cReporter C.uintptr_t, cError **C.struct_greener_reporter_error) {
	*cError = nil

	if cReporter == 0 {
		setError(reporter.NewInvalidArgumentError("reporter pointer is null"), cError)
		return
	}

	h := cgo.Handle(cReporter)
	r := h.Value().(*reporter.Reporter)

	if err := r.PopError(); err != nil {
		if reporterErr, ok := err.(*reporter.ReporterError); ok {
			setError(reporterErr, cError)
		} else {
			setError(reporter.NewUnknownError(err.Error()), cError)
		}
	}
}

func setError(err *reporter.ReporterError, cError **C.struct_greener_reporter_error) {
	if cError == nil {
		return
	}

	*cError = (*C.struct_greener_reporter_error)(C.malloc(C.size_t(unsafe.Sizeof(C.struct_greener_reporter_error{}))))
	(*cError).code = C.int(err.Code)
	(*cError).ingress_code = C.int(err.IngressCode)
	(*cError).message = C.CString(err.Message)
}

func main() {}
