package ffi

/*

#cgo CFLAGS: -I../dist/include
#cgo linux LDFLAGS: -L../target/debug -lgreener_reporter -lgreener_servermock -Wl,-rpath,../target/debug
#cgo darwin LDFLAGS: -L../target/debug -lgreener_reporter -lgreener_servermock -Wl,-rpath,../target/debug
#cgo windows LDFLAGS: -L../target/debug -lgreener_reporter -lgreener_servermock

#include <greener_reporter/greener_reporter.h>
#include <greener_servermock/greener_servermock.h>

#include <stdlib.h>

*/
import "C"
import (
	"errors"
	"fmt"
	"unsafe"
)

func GetFixtureNames() ([]string, error) {
	s := C.greener_servermock_new()

	errC := (*C.struct_greener_servermock_error)(nil)
	var namesc **C.char
	var numNamesc C.uint32_t
	C.greener_servermock_fixture_names(s, &namesc, &numNamesc, &errC)

	if errC != nil {
		return nil, fmt.Errorf("cannot get fixture names: %s", C.GoString(errC.message))
	}
	if numNamesc == 0 {
		return nil, errors.New("no fixtures found")
	}

	names := make([]string, numNamesc)
	for i := range numNamesc {
		s := *(**C.char)(unsafe.Pointer(
			uintptr(unsafe.Pointer(namesc)) + uintptr(i)*unsafe.Sizeof(namesc)))
		names[i] = C.GoString(s)
	}

	C.greener_servermock_delete(s, &errC)
	if errC != nil {
		return nil, fmt.Errorf("cannot delete servermock: %s", C.GoString(errC.message))
	}

	return names, nil
}

type GreenerReporter struct {
	h *C.struct_greener_reporter
}

func NewGreenerReporter(endpoint string, apiKey string) (*GreenerReporter, *GreenerReporterError) {
	var errC *C.struct_greener_reporter_error
	endpointC := C.CString(endpoint)
	apiKeyC := C.CString(apiKey)
	defer C.free(unsafe.Pointer(endpointC))
	defer C.free(unsafe.Pointer(apiKeyC))

	h := C.greener_reporter_new(endpointC, apiKeyC, &errC)
	if errC != nil {
		return nil, &GreenerReporterError{h: errC}
	}
	return &GreenerReporter{h: h}, nil
}

func (a *GreenerReporter) Delete() *GreenerReporterError {
	errC := (*C.struct_greener_reporter_error)(nil)
	C.greener_reporter_delete(a.h, &errC)
	if errC != nil {
		return &GreenerReporterError{h: errC}
	}
	a.h = nil

	return nil
}

type GreenerReporterError struct {
	h *C.struct_greener_reporter_error
}

func (s *GreenerReporterError) Delete() {
	C.greener_reporter_error_delete(s.h)
}

func (s *GreenerReporterError) Code() int64 {
	return int64(s.h.code)
}

func (s *GreenerReporterError) IngressCode() int64 {
	return int64(s.h.ingress_code)
}

func (s *GreenerReporterError) Message() string {
	return C.GoString(s.h.message)
}

type GreenerReporterSession struct {
	h *C.struct_greener_reporter_session
}

func (s *GreenerReporterSession) Delete() {
	C.greener_reporter_session_delete(s.h)
}

func (s *GreenerReporterSession) Id() string {
	return C.GoString(s.h.id)
}

func (a *GreenerReporter) CreateSession(sessionId *string, description *string, baggage *string, labels *string) (*GreenerReporterSession, *GreenerReporterError) {
	errC := (*C.struct_greener_reporter_error)(nil)

	sessionIdC := (*C.char)(nil)
	descriptionC := (*C.char)(nil)
	baggageC := (*C.char)(nil)
	labelsC := (*C.char)(nil)

	if sessionId != nil {
		sessionIdC = C.CString(*sessionId)
		defer C.free(unsafe.Pointer(sessionIdC))
	}
	if description != nil {
		descriptionC = C.CString(*description)
		defer C.free(unsafe.Pointer(descriptionC))
	}
	if baggage != nil {
		baggageC = C.CString(*baggage)
		defer C.free(unsafe.Pointer(baggageC))
	}
	if labels != nil {
		labelsC = C.CString(*labels)
		defer C.free(unsafe.Pointer(labelsC))
	}

	sessionC := C.greener_reporter_session_create(a.h, sessionIdC, descriptionC, baggageC, labelsC, &errC)
	if errC != nil {
		return nil, &GreenerReporterError{h: errC}
	}
	return &GreenerReporterSession{h: sessionC}, nil
}

func (a *GreenerReporter) CreateTestcase(
	sessionId string,
	testcaseName string,
	testcaseClassname *string,
	testcaseFile *string,
	testsuite *string,
	status string,
	baggage *string,

) *GreenerReporterError {
	testcaseClassnameC := (*C.char)(nil)
	testcaseFileC := (*C.char)(nil)
	testsuiteC := (*C.char)(nil)
	baggageC := (*C.char)(nil)

	if testcaseClassname != nil {
		testcaseClassnameC = C.CString(*testcaseClassname)
	}
	if testcaseFile != nil {
		testcaseFileC = C.CString(*testcaseFile)
	}
	if testsuite != nil {
		testsuiteC = C.CString(*testsuite)
	}
	if baggage != nil {
		baggageC = C.CString(*baggage)
	}

	errC := (*C.struct_greener_reporter_error)(nil)
	C.greener_reporter_testcase_create(
		a.h,
		C.CString(sessionId),
		C.CString(testcaseName),
		testcaseClassnameC,
		testcaseFileC,
		testsuiteC,
		C.CString(status),
		nil, // stdout
		baggageC,
		&errC,
	)
	if errC != nil {
		return &GreenerReporterError{h: errC}
	}
	return nil
}

type GreenerServermock struct {
	h *C.struct_greener_servermock
}

func NewGreenerServermock() *GreenerServermock {
	h := C.greener_servermock_new()

	return &GreenerServermock{h: h}
}

func (s *GreenerServermock) Delete() error {
	errC := (*C.struct_greener_servermock_error)(nil)
	C.greener_servermock_delete(s.h, &errC)
	if errC != nil {
		return fmt.Errorf("cannot delete servermock: %s", C.GoString(errC.message))
	}
	s.h = nil

	return nil
}

func (s *GreenerServermock) FixtureCalls(name string) (string, error) {
	callsC := (*C.char)(nil)
	errC := (*C.struct_greener_servermock_error)(nil)
	C.greener_servermock_fixture_calls(s.h, C.CString(name), &callsC, &errC)
	if errC != nil {
		return "", fmt.Errorf("cannot get servermock fixture calls: %s", C.GoString(errC.message))
	}

	calls := C.GoString(callsC)
	return calls, nil
}

func (s *GreenerServermock) FixtureResponses(name string) (string, error) {
	respsC := (*C.char)(nil)
	errC := (*C.struct_greener_servermock_error)(nil)
	C.greener_servermock_fixture_responses(s.h, C.CString(name), &respsC, &errC)
	if errC != nil {
		return "", fmt.Errorf("cannot get servermock fixture responses: %s", C.GoString(errC.message))
	}

	resps := C.GoString(respsC)
	return resps, nil
}

func (s *GreenerServermock) Serve(resps string) error {
	errC := (*C.struct_greener_servermock_error)(nil)
	C.greener_servermock_serve(s.h, C.CString(resps), &errC)
	if errC != nil {
		return fmt.Errorf("cannot servermock serve: %s", C.GoString(errC.message))
	}
	return nil
}

func (s *GreenerServermock) GetPort() (int, error) {
	errC := (*C.struct_greener_servermock_error)(nil)
	portC := C.greener_servermock_get_port(s.h, &errC)
	if errC != nil {
		return -1, fmt.Errorf("cannot get servermock port: %s", C.GoString(errC.message))
	}

	return int(portC), nil
}

func (s *GreenerServermock) Assert(calls string) error {
	errC := (*C.struct_greener_servermock_error)(nil)
	C.greener_servermock_assert(s.h, C.CString(calls), &errC)
	if errC != nil {
		return fmt.Errorf("servermock assert failed: %s", C.GoString(errC.message))
	}
	return nil
}
