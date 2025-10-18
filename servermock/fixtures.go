package servermock

import "encoding/json"

type Call struct {
	Func    string          `json:"func"`
	Payload json.RawMessage `json:"payload"`
}

type Response struct {
	Status  string          `json:"status"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type Responses struct {
	CreateSessionResponse Response `json:"createSessionResponse"`
	ReportResponse        Response `json:"reportResponse"`
}

type Fixture struct {
	Calls     []Call    `json:"calls"`
	Responses Responses `json:"responses"`
}

func createFixtures() map[string]Fixture {
	return map[string]Fixture{
		"createSessionWithId": {
			Calls: []Call{
				{
					Func: "createSession",
					Payload: json.RawMessage(`{
						"id": "c209c477-d186-49a7-ab83-2ba6dcb409b4",
						"description": "some description",
						"baggage": {"a": "b"},
						"labels": "ab=2,cd"
					}`),
				},
			},
			Responses: Responses{
				CreateSessionResponse: Response{
					Status:  "success",
					Payload: json.RawMessage(`{"id": "16af52dc-3296-4249-be93-3aaef3a85845"}`),
				},
				ReportResponse: Response{
					Status: "success",
				},
			},
		},
		"createSessionWithoutId": {
			Calls: []Call{
				{
					Func: "createSession",
					Payload: json.RawMessage(`{
						"id": null,
						"description": null,
						"baggage": null,
						"labels": null
					}`),
				},
			},
			Responses: Responses{
				CreateSessionResponse: Response{
					Status:  "success",
					Payload: json.RawMessage(`{"id": "16af52dc-3296-4249-be93-3aaef3a85845"}`),
				},
				ReportResponse: Response{
					Status: "success",
				},
			},
		},
		"createSessionResponseError": {
			Calls: []Call{
				{
					Func: "createSession",
					Payload: json.RawMessage(`{
						"id": null,
						"description": null,
						"baggage": null,
						"labels": null
					}`),
				},
			},
			Responses: Responses{
				CreateSessionResponse: Response{
					Status: "error",
					Payload: json.RawMessage(`{
						"code": 3,
						"ingressCode": 400,
						"message": "error message"
					}`),
				},
				ReportResponse: Response{
					Status: "success",
				},
			},
		},
		"report": {
			Calls: []Call{
				{
					Func: "report",
					Payload: json.RawMessage(`{
						"testcases": [
							{
								"sessionId": "16af52dc-3296-4249-be93-3aaef3a85111",
								"testcaseName": "test_some_logic",
								"testcaseClassname": "my_class",
								"testcaseFile": "my_file.py",
								"testsuite": "some test suite",
								"status": "pass",
								"output": null,
								"baggage": null
							}
						]
					}`),
				},
			},
			Responses: Responses{
				CreateSessionResponse: Response{
					Status:  "success",
					Payload: json.RawMessage(`{"id": "16af52dc-3296-4249-be93-3aaef3a85845"}`),
				},
				ReportResponse: Response{
					Status: "success",
				},
			},
		},
		"reportNameOnly": {
			Calls: []Call{
				{
					Func: "report",
					Payload: json.RawMessage(`{
						"testcases": [
							{
								"sessionId": "16af52dc-3296-4249-be93-3aaef3a85878",
								"testcaseName": "test_some_logic",
								"testcaseClassname": null,
								"testcaseFile": null,
								"testsuite": null,
								"status": "skip",
								"output": null,
								"baggage": null
							}
						]
					}`),
				},
			},
			Responses: Responses{
				CreateSessionResponse: Response{
					Status:  "success",
					Payload: json.RawMessage(`{"id": "16af52dc-3296-4249-be93-3aaef3a85845"}`),
				},
				ReportResponse: Response{
					Status: "success",
				},
			},
		},
	}
}
