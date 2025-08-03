package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/google/uuid"
	"github.com/urfave/cli/v3"
)

const (
	envVarIngress = "GREENER_INGRESS_ENDPOINT"
	envVarAPIKey  = "GREENER_INGRESS_API_KEY"

	flagIngress   = "ingress"
	flagAPIKey    = "api-key"
	flagID        = "id"
	flagLabel     = "label"
	flagSessionID = "session-id"
	flagName      = "name"
	flagOutput    = "output"
	flagClassname = "classname"
	flagFile      = "file"
	flagTestsuite = "testsuite"
	flagStatus    = "status"
	flagBaggage   = "baggage"
)

func main() {
	cmd := &cli.Command{
		Name:  "greener-reporter-cli",
		Usage: "CLI tool for Greener reporting",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:     flagIngress,
				Usage:    "Greener ingress endpoint URL",
				Sources:  cli.EnvVars(envVarIngress),
				Required: true,
			},
			&cli.StringFlag{
				Name:     flagAPIKey,
				Usage:    "API key for authentication",
				Sources:  cli.EnvVars(envVarAPIKey),
				Required: true,
			},
		},
		Commands: []*cli.Command{
			{
				Name:  "create",
				Usage: "Create results",
				Commands: []*cli.Command{
					{
						Name:  "session",
						Usage: "Create session",
						Flags: []cli.Flag{
							&cli.StringFlag{
								Name:  flagID,
								Usage: "ID for the sesison",
							},
							&cli.StringFlag{
								Name:  flagBaggage,
								Usage: "Additional metadata as JSON",
							},
							&cli.StringSliceFlag{
								Name:  flagLabel,
								Usage: "Labels in `key` or `key=value` format",
							},
						},
						Action: createSession,
					},
					{
						Name:  "testcase",
						Usage: "Create test case",
						Flags: []cli.Flag{
							&cli.StringFlag{
								Name:     flagSessionID,
								Usage:    "Session ID for the test case",
								Required: true,
							},
							&cli.StringFlag{
								Name:     flagName,
								Usage:    "Name of the test case",
								Required: true,
							},
							&cli.StringFlag{
								Name:  flagOutput,
								Usage: "Output from the test case",
							},
							&cli.StringFlag{
								Name:  flagClassname,
								Usage: "Class name of the test case",
							},
							&cli.StringFlag{
								Name:  flagFile,
								Usage: "File path of the test case",
							},
							&cli.StringFlag{
								Name:  flagTestsuite,
								Usage: "Test suite name",
							},
							&cli.StringFlag{
								Name:  flagStatus,
								Usage: "Test case status (pass, fail, err, skip)",
								Value: "pass",
							},
							&cli.StringFlag{
								Name:  flagBaggage,
								Usage: "Additional metadata as JSON",
							},
						},
						Action: createTestcase,
					},
				},
			},
		},
	}

	if err := cmd.Run(context.Background(), os.Args); err != nil {
		log.Fatal(err)
	}
}

func createSession(ctx context.Context, cmd *cli.Command) error {
	endpoint := cmd.String(flagIngress)
	apiKey := cmd.String(flagAPIKey)
	id := getOptArg(cmd, flagID)
	baggageStr := getOptArg(cmd, flagBaggage)
	labelStrings := cmd.StringSlice(flagLabel)

	var baggage map[string]any
	if baggageStr != nil {
		if err := json.Unmarshal([]byte(*baggageStr), &baggage); err != nil {
			return fmt.Errorf("invalid baggage JSON: %w", err)
		}
	}

	labels, err := parseLabels(labelStrings)
	if err != nil {
		return fmt.Errorf("invalid labels: %w", err)
	}

	client := NewClient(endpoint, apiKey)

	sessionReq := SessionRequest{
		ID:      id,
		Baggage: baggage,
		Labels:  labels,
	}
	sessionID, err := client.CreateSession(sessionReq)
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}

	fmt.Printf("Created session ID: %s\n", sessionID)
	return nil
}

func createTestcase(ctx context.Context, cmd *cli.Command) error {
	sessionIdStr := cmd.String(flagSessionID)
	sessionId, err := uuid.Parse(sessionIdStr)
	if err != nil {
		return fmt.Errorf("invalid session ID: %w", err)
	}

	endpoint := cmd.String(flagIngress)
	apiKey := cmd.String(flagAPIKey)
	name := cmd.String(flagName)
	output := getOptArg(cmd, flagOutput)
	classname := getOptArg(cmd, flagClassname)
	file := getOptArg(cmd, flagFile)
	testsuite := getOptArg(cmd, flagTestsuite)
	status := cmd.String(flagStatus)
	baggageStr := getOptArg(cmd, flagBaggage)

	var testcaseStatus TestcaseStatus
	switch status {
	case "pass":
		testcaseStatus = StatusPass
	case "fail":
		testcaseStatus = StatusFail
	case "err":
		testcaseStatus = StatusErr
	case "skip":
		testcaseStatus = StatusSkip
	default:
		return fmt.Errorf("invalid status: %s. Valid values: pass, fail, err, skip", status)
	}

	var baggage map[string]any
	if baggageStr != nil {
		if err := json.Unmarshal([]byte(*baggageStr), &baggage); err != nil {
			return fmt.Errorf("invalid baggage JSON: %w", err)
		}
	}

	client := NewClient(endpoint, apiKey)

	testcase := TestcaseRequest{
		SessionID:         sessionId.String(),
		TestcaseName:      name,
		TestcaseClassname: classname,
		TestcaseFile:      file,
		Testsuite:         testsuite,
		Status:            testcaseStatus,
		Output:            output,
		Baggage:           baggage,
	}

	err = client.CreateTestcases([]TestcaseRequest{testcase})
	if err != nil {
		return fmt.Errorf("failed to create testcase: %w", err)
	}

	return nil
}

func getOptArg(cmd *cli.Command, flag string) *string {
	if !cmd.IsSet(flag) {
		return nil
	}

	value := cmd.String(flag)
	return &value
}

func parseLabels(labelStrings []string) ([]Label, error) {
	if len(labelStrings) == 0 {
		return nil, nil
	}

	labels := make([]Label, 0, len(labelStrings))
	keysSet := make(map[string]bool)

	for _, labelStr := range labelStrings {
		var key string
		var valuePtr *string

		if parts := strings.SplitN(labelStr, "=", 2); len(parts) == 2 {
			key = parts[0]
			valuePtr = &parts[1]
		} else {
			key = labelStr
		}

		if key == "" {
			return nil, fmt.Errorf("label key cannot be empty")
		}

		if keysSet[key] {
			return nil, fmt.Errorf("duplicate label key: %s", key)
		}
		keysSet[key] = true

		labels = append(labels, Label{
			Key:   key,
			Value: valuePtr,
		})
	}

	return labels, nil
}
