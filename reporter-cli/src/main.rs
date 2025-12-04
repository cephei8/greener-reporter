use clap::{Args, Parser, Subcommand};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::error::Error;
use std::fmt;
use uuid::Uuid;

const ENVVAR_ENDPOINT: &str = "GREENER_INGRESS_ENDPOINT";
const ENVVAR_API_KEY: &str = "GREENER_INGRESS_API_KEY";

#[derive(Parser)]
#[command(name = "greener-reporter-cli")]
#[command(about = "CLI tool for Greener reporting", long_about = None)]
struct Cli {
    #[arg(
        long = "endpoint",
        env = ENVVAR_ENDPOINT,
        help = "Greener ingress endpoint URL",
    )]
    endpoint: String,

    #[arg(
        long = "api-key",
        env = ENVVAR_API_KEY,
        help = "API key for authentication",
    )]
    api_key: String,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    #[command(about = "Create results")]
    Create {
        #[command(subcommand)]
        command: CreateCommands,
    },
}

#[derive(Subcommand)]
enum CreateCommands {
    #[command(about = "Create session")]
    Session(SessionArgs),
    #[command(about = "Create test case")]
    Testcase(TestcaseArgs),
}

#[derive(Args, Clone)]
struct SessionArgs {
    #[arg(long = "id", help = "ID for the session")]
    id: Option<String>,

    #[arg(long = "baggage", help = "Additional metadata as JSON")]
    baggage: Option<String>,

    #[arg(
        long = "label",
        help = "Labels in `key` or `key=value` format",
        value_name = "LABEL"
    )]
    label: Vec<String>,
}

#[derive(Args, Clone)]
struct TestcaseArgs {
    #[arg(long = "session-id", help = "Session ID for the test case")]
    session_id: String,

    #[arg(long = "name", help = "Name of the test case")]
    name: String,

    #[arg(long = "output", help = "Output from the test case")]
    output: Option<String>,

    #[arg(long = "classname", help = "Class name of the test case")]
    classname: Option<String>,

    #[arg(long = "file", help = "File path of the test case")]
    file: Option<String>,

    #[arg(long = "testsuite", help = "Test suite name")]
    testsuite: Option<String>,

    #[arg(
        long = "status",
        help = "Test case status (pass, fail, error, skip)",
        default_value = "pass"
    )]
    status: String,

    #[arg(long = "baggage", help = "Additional metadata as JSON")]
    baggage: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "lowercase")]
enum TestcaseStatus {
    Pass,
    Fail,
    Error,
    Skip,
}

#[derive(Debug)]
struct CliError(String);

impl fmt::Display for CliError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl Error for CliError {}

impl TestcaseStatus {
    fn from_str(s: &str) -> Result<Self, CliError> {
        match s {
            "pass" => Ok(Self::Pass),
            "fail" => Ok(Self::Fail),
            "error" => Ok(Self::Error),
            "skip" => Ok(Self::Skip),
            _ => Err(CliError(format!(
                "Invalid status: {}. Valid values: pass, fail, error, skip",
                s
            ))),
        }
    }
}

#[derive(Debug, Serialize)]
struct Label {
    key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    value: Option<String>,
}

#[derive(Debug, Serialize)]
struct SessionRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    baggage: Option<HashMap<String, serde_json::Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    labels: Option<Vec<Label>>,
}

#[derive(Debug, Deserialize)]
struct SessionResponse {
    id: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct TestcaseRequest {
    session_id: String,
    testcase_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    testcase_classname: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    testcase_file: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    testsuite: Option<String>,
    status: TestcaseStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    output: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    baggage: Option<HashMap<String, serde_json::Value>>,
}

#[derive(Debug, Serialize)]
struct TestcasesRequest {
    testcases: Vec<TestcaseRequest>,
}

#[derive(Debug, Deserialize)]
struct ErrorResponse {
    detail: String,
}

struct Client {
    client: reqwest::blocking::Client,
    endpoint: String,
    api_key: String,
}

impl Client {
    fn new(endpoint: String, api_key: String) -> Self {
        Self {
            client: reqwest::blocking::Client::new(),
            endpoint,
            api_key,
        }
    }

    fn create_session(&self, req: SessionRequest) -> Result<String, Box<dyn Error>> {
        let url = format!("{}/api/v1/ingress/sessions", self.endpoint);

        let response = self
            .client
            .post(&url)
            .header("Content-Type", "application/json")
            .header("X-API-Key", &self.api_key)
            .json(&req)
            .send()
            .map_err(|e| {
                Box::new(CliError(format!("Failed to send session request: {}", e)))
                    as Box<dyn Error>
            })?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response
                .json::<ErrorResponse>()
                .map(|e| e.detail)
                .unwrap_or_else(|_| "Unknown error".to_string());
            return Err(Box::new(CliError(format!(
                "Failed session request ({}): {}",
                status.as_u16(),
                error_text
            ))));
        }

        let session_resp = response.json::<SessionResponse>().map_err(|e| {
            Box::new(CliError(format!("Failed to parse session response: {}", e))) as Box<dyn Error>
        })?;

        Ok(session_resp.id)
    }

    fn create_testcases(&self, testcases: Vec<TestcaseRequest>) -> Result<(), Box<dyn Error>> {
        let url = format!("{}/api/v1/ingress/testcases", self.endpoint);

        let req = TestcasesRequest { testcases };

        let response = self
            .client
            .post(&url)
            .header("Content-Type", "application/json")
            .header("X-API-Key", &self.api_key)
            .json(&req)
            .send()
            .map_err(|e| {
                Box::new(CliError(format!("Failed to send testcases request: {}", e)))
                    as Box<dyn Error>
            })?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response
                .json::<ErrorResponse>()
                .map(|e| e.detail)
                .unwrap_or_else(|_| "Unknown error".to_string());
            return Err(Box::new(CliError(format!(
                "Failed testcases request ({}): {}",
                status.as_u16(),
                error_text
            ))));
        }

        Ok(())
    }
}

fn parse_labels(label_strings: Vec<String>) -> Result<Option<Vec<Label>>, Box<dyn Error>> {
    if label_strings.is_empty() {
        return Ok(None);
    }

    let mut labels = Vec::new();
    let mut keys_set = std::collections::HashSet::new();

    for label_str in label_strings {
        let (key, value) = if let Some(idx) = label_str.find('=') {
            let (k, v) = label_str.split_at(idx);
            (k.to_string(), Some(v[1..].to_string()))
        } else {
            (label_str.clone(), None)
        };

        if key.is_empty() {
            return Err(Box::new(CliError("Label key cannot be empty".to_string())));
        }

        if keys_set.contains(&key) {
            return Err(Box::new(CliError(format!("Duplicate label key: {}", key))));
        }
        keys_set.insert(key.clone());

        labels.push(Label { key, value });
    }

    Ok(Some(labels))
}

fn parse_baggage(
    baggage_str: Option<String>,
) -> Result<Option<HashMap<String, serde_json::Value>>, Box<dyn Error>> {
    match baggage_str {
        Some(s) => {
            let baggage: HashMap<String, serde_json::Value> =
                serde_json::from_str(&s).map_err(|e| {
                    Box::new(CliError(format!("Invalid baggage JSON: {}", e))) as Box<dyn Error>
                })?;
            Ok(Some(baggage))
        }
        None => Ok(None),
    }
}

fn create_session(cli: &Cli, args: SessionArgs) -> Result<(), Box<dyn Error>> {
    let client = Client::new(cli.endpoint.clone(), cli.api_key.clone());

    let baggage = parse_baggage(args.baggage)?;
    let labels = parse_labels(args.label)?;

    let session_req = SessionRequest {
        id: args.id,
        baggage,
        labels,
    };

    let session_id = client.create_session(session_req)?;

    println!("Created session ID: {}", session_id);
    Ok(())
}

fn create_testcase(cli: &Cli, args: TestcaseArgs) -> Result<(), Box<dyn Error>> {
    let session_id = Uuid::parse_str(&args.session_id).map_err(|e| {
        Box::new(CliError(format!("Invalid session ID format: {}", e))) as Box<dyn Error>
    })?;

    let status = TestcaseStatus::from_str(&args.status)?;
    let baggage = parse_baggage(args.baggage)?;

    let client = Client::new(cli.endpoint.clone(), cli.api_key.clone());

    let testcase = TestcaseRequest {
        session_id: session_id.to_string(),
        testcase_name: args.name,
        testcase_classname: args.classname,
        testcase_file: args.file,
        testsuite: args.testsuite,
        status,
        output: args.output,
        baggage,
    };

    client.create_testcases(vec![testcase])?;

    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let cli = Cli::parse();

    match &cli.command {
        Commands::Create { command } => match command {
            CreateCommands::Session(args) => create_session(&cli, args.clone()),
            CreateCommands::Testcase(args) => create_testcase(&cli, args.clone()),
        },
    }
}
