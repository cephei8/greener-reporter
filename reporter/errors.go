package reporter

import "fmt"

type ErrorCode int

const (
	ErrorCodeUnknown ErrorCode = iota + 1
	ErrorCodeInvalidArgument
	ErrorCodeIngress
)

type ReporterError struct {
	Code        ErrorCode
	IngressCode int
	Message     string
}

func (e *ReporterError) Error() string {
	switch e.Code {
	case ErrorCodeInvalidArgument:
		return fmt.Sprintf("InvalidArgument error: %s", e.Message)
	case ErrorCodeIngress:
		return fmt.Sprintf("Ingress error: code=%d, %s", e.IngressCode, e.Message)
	default:
		return fmt.Sprintf("Unknown error: %s", e.Message)
	}
}

func NewInvalidArgumentError(message string) *ReporterError {
	return &ReporterError{
		Code:        ErrorCodeInvalidArgument,
		IngressCode: 0,
		Message:     message,
	}
}

func NewIngressError(message string, statusCode int) *ReporterError {
	return &ReporterError{
		Code:        ErrorCodeIngress,
		IngressCode: statusCode,
		Message:     message,
	}
}

func NewUnknownError(message string) *ReporterError {
	return &ReporterError{
		Code:        ErrorCodeUnknown,
		IngressCode: 0,
		Message:     message,
	}
}
