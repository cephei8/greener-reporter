package reporter

type TestcaseStatus string

const (
	TestcaseStatusPass  TestcaseStatus = "pass"
	TestcaseStatusFail  TestcaseStatus = "fail"
	TestcaseStatusError TestcaseStatus = "error"
	TestcaseStatusSkip  TestcaseStatus = "skip"
)

type Label struct {
	Key   string  `json:"key"`
	Value *string `json:"value,omitempty"`
}

type SessionRequest struct {
	Id          *string        `json:"id"`
	Description *string        `json:"description"`
	Baggage     map[string]any `json:"baggage"`
	Labels      []Label        `json:"labels"`
}

type SessionResponse struct {
	Id string `json:"id"`
}

type ErrorResponse struct {
	Message string `json:"message"`
}

type TestcaseRequest struct {
	SessionId         string         `json:"sessionId"`
	TestcaseName      string         `json:"testcaseName"`
	TestcaseClassname *string        `json:"testcaseClassname"`
	TestcaseFile      *string        `json:"testcaseFile"`
	Testsuite         *string        `json:"testsuite"`
	Status            TestcaseStatus `json:"status"`
	Output            *string        `json:"output"`
	Baggage           map[string]any `json:"baggage"`
}

type TestcasesRequest struct {
	Testcases []TestcaseRequest `json:"testcases"`
}

type Session struct {
	Id string
}
