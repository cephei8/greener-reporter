package main

/*
#include <stdlib.h>
#include <stdint.h>

struct greener_servermock_error {
    const char *message;
};
*/
import "C"
import (
	"runtime/cgo"
	"unsafe"

	servermock "github.com/cephei8/greener-reporter/servermock"
)

//export greener_servermock_new
func greener_servermock_new() C.uintptr_t {
	s := servermock.New()
	return C.uintptr_t(cgo.NewHandle(s))
}

//export greener_servermock_delete
func greener_servermock_delete(
	cServermock C.uintptr_t,
	cError **C.struct_greener_servermock_error,
) {
	*cError = nil

	if cServermock == 0 {
		return
	}

	h := cgo.Handle(cServermock)
	h.Delete()
}

//export greener_servermock_serve
func greener_servermock_serve(
	cServermock C.uintptr_t,
	cResponses *C.char,
	cError **C.struct_greener_servermock_error,
) {
	*cError = nil

	if cServermock == 0 || cResponses == nil {
		*cError = createError("context or responses pointer is null")
		return
	}

	h := cgo.Handle(cServermock)
	s := h.Value().(*servermock.GreenerServermock)

	responses := C.GoString(cResponses)
	if err := s.Serve(responses); err != nil {
		*cError = createError(err.Error())
		return
	}
}

//export greener_servermock_get_port
func greener_servermock_get_port(
	cServermock C.uintptr_t,
	cError **C.struct_greener_servermock_error,
) C.int {
	*cError = nil

	if cServermock == 0 {
		*cError = createError("context pointer is null")
		return -1
	}

	h := cgo.Handle(cServermock)
	s := h.Value().(*servermock.GreenerServermock)

	return C.int(s.Port())
}

//export greener_servermock_assert
func greener_servermock_assert(
	cServermock C.uintptr_t,
	cCalls *C.char,
	cError **C.struct_greener_servermock_error,
) bool {
	*cError = nil

	if cServermock == 0 || cCalls == nil {
		*cError = createError("context or calls pointer is null")
		return false
	}

	h := cgo.Handle(cServermock)
	s := h.Value().(*servermock.GreenerServermock)

	calls := C.GoString(cCalls)
	if err := s.Assert(calls); err != nil {
		*cError = createError(err.Error())
		return false
	}

	return true
}

//export greener_servermock_fixture_names
func greener_servermock_fixture_names(
	cServermock C.uintptr_t,
	cNames ***C.char,
	cNumNames *C.uint,
	cError **C.struct_greener_servermock_error,
) {
	*cError = nil

	if cServermock == 0 || cNames == nil || cNumNames == nil {
		*cError = createError("context, names, or num_names pointer is null")
		return
	}

	h := cgo.Handle(cServermock)
	s := h.Value().(*servermock.GreenerServermock)

	fixtureNames := s.FixtureNames()
	*cNumNames = C.uint(len(fixtureNames))

	if len(fixtureNames) == 0 {
		*cNames = nil
		return
	}

	namesPtr := C.malloc(C.size_t(len(fixtureNames)) * C.size_t(unsafe.Sizeof((*C.char)(nil))))
	namesArr := (*[1 << 30]*C.char)(namesPtr)

	for i, name := range fixtureNames {
		namesArr[i] = C.CString(name)
	}

	*cNames = (**C.char)(namesPtr)
}

//export greener_servermock_fixture_calls
func greener_servermock_fixture_calls(
	cServermock C.uintptr_t,
	cFixtureName *C.char,
	cCalls **C.char,
	cError **C.struct_greener_servermock_error,
) {
	*cError = nil

	if cServermock == 0 || cFixtureName == nil || cCalls == nil {
		*cError = createError("context, fixture_name, or calls pointer is null")
		return
	}

	h := cgo.Handle(cServermock)
	s := h.Value().(*servermock.GreenerServermock)

	fixtureName := C.GoString(cFixtureName)
	callsJSON, err := s.FixtureCalls(fixtureName)
	if err != nil {
		*cError = createError(err.Error())
		return
	}

	*cCalls = C.CString(callsJSON)
}

//export greener_servermock_fixture_responses
func greener_servermock_fixture_responses(
	cServermock C.uintptr_t,
	cFixtureName *C.char,
	cResponses **C.char,
	cError **C.struct_greener_servermock_error,
) {
	*cError = nil

	if cServermock == 0 || cFixtureName == nil || cResponses == nil {
		*cError = createError("context, fixture_name, or responses pointer is null")
		return
	}

	h := cgo.Handle(cServermock)
	s := h.Value().(*servermock.GreenerServermock)

	fixtureName := C.GoString(cFixtureName)
	responsesJSON, err := s.FixtureResponses(fixtureName)
	if err != nil {
		*cError = createError(err.Error())
		return
	}

	*cResponses = C.CString(responsesJSON)
}

//export greener_servermock_error_delete
func greener_servermock_error_delete(cError *C.struct_greener_servermock_error) {
	if cError == nil {
		return
	}

	C.free(unsafe.Pointer(cError.message))
	C.free(unsafe.Pointer(cError))
}

func createError(message string) *C.struct_greener_servermock_error {
	cMessage := C.CString(message)
	cError := (*C.struct_greener_servermock_error)(C.malloc(C.size_t(unsafe.Sizeof(C.struct_greener_servermock_error{}))))
	cError.message = cMessage
	return cError
}

func main() {}
