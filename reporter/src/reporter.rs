use crate::batcher::Batcher;
use crate::errors::ReporterError;
use crate::ingress::IngressClient;
use crate::models::{Label, SessionRequest, TestcaseRequest};
use std::sync::Arc;
use tokio::runtime::Runtime;
use tokio::sync::Mutex;

#[repr(C)]
pub struct Reporter {
    runtime: Arc<Runtime>,
    ingress: Arc<IngressClient>,
    batcher: Arc<Mutex<Batcher>>,
}

impl Reporter {
    pub fn new() -> Result<Self, ReporterError> {
        let runtime = Arc::new(
            Runtime::new()
                .map_err(|e| ReporterError::Unknown(format!("error creating runtime: {}", e)))?,
        );
        let ingress = Arc::new(IngressClient::new().map_err(|e| {
            ReporterError::Unknown(format!("error creating ingress client: {}", e))
        })?);
        let batcher = Arc::new(Mutex::new(Batcher::new(runtime.clone(), ingress.clone())));

        Ok(Reporter {
            runtime,
            ingress,
            batcher,
        })
    }

    pub fn add_testcase(&self, testcase: TestcaseRequest) -> Result<(), ReporterError> {
        let batcher = self.runtime.block_on(self.batcher.lock());
        self.runtime.block_on(batcher.add(testcase))
    }

    pub fn shutdown(&self) -> Result<(), ReporterError> {
        let mut batcher = self.runtime.block_on(self.batcher.lock());
        self.runtime.block_on(batcher.shutdown())
    }

    pub fn pop_error(&self) -> Option<ReporterError> {
        let batcher = self.runtime.block_on(self.batcher.lock());
        self.runtime.block_on(batcher.pop_error())
    }

    pub fn create_session(&self) -> Result<String, ReporterError> {
        let session_id = match std::env::var("GREENER_SESSION_ID") {
            Ok(x) => Some(x),
            Err(err) => match err {
                std::env::VarError::NotPresent => None,
                std::env::VarError::NotUnicode(_) => {
                    return Err(ReporterError::InvalidArgument(format!(
                        "cannot read non-unicode GREENER_SESSION_ID"
                    )));
                }
            },
        };

        let description = match std::env::var("GREENER_SESSION_DESCRIPTION") {
            Ok(x) => Some(x),
            Err(err) => match err {
                std::env::VarError::NotPresent => None,
                std::env::VarError::NotUnicode(_) => {
                    return Err(ReporterError::InvalidArgument(format!(
                        "cannot read non-unicode GREENER_SESSION_DESCRIPTION"
                    )));
                }
            },
        };

        let baggage = match std::env::var("GREENER_SESSION_BAGGAGE") {
            Ok(x) => Some(x),
            Err(err) => match err {
                std::env::VarError::NotPresent => None,
                std::env::VarError::NotUnicode(_) => {
                    return Err(ReporterError::InvalidArgument(format!(
                        "cannot read non-unicode GREENER_SESSION_BAGGAGE"
                    )));
                }
            },
        };
        let baggage = baggage.and_then(|s| serde_json::from_str(&s).ok());

        let labels = match std::env::var("GREENER_SESSION_LABELS") {
            Ok(x) => Some(x),
            Err(err) => match err {
                std::env::VarError::NotPresent => None,
                std::env::VarError::NotUnicode(_) => {
                    return Err(ReporterError::InvalidArgument(format!(
                        "cannot read non-unicode GREENER_SESSION_LABELS"
                    )));
                }
            },
        };
        let labels: Vec<Label> = labels
            .map(|s| {
                s.split(',')
                    .filter(|s| !s.is_empty())
                    .map(|s| {
                        let parts: Vec<&str> = s.split('=').collect();
                        Label {
                            key: parts[0].to_string(),
                            value: parts.get(1).map(|v| v.to_string()),
                        }
                    })
                    .collect()
            })
            .unwrap_or_default();
        let labels = if labels.is_empty() {
            None
        } else {
            Some(labels)
        };

        let session = SessionRequest {
            id: session_id,
            description,
            baggage,
            labels,
        };

        self.runtime.block_on(self.ingress.create_session(session))
    }
}
