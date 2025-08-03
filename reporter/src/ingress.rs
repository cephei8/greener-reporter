use crate::errors::ReporterError;
use crate::models::{
    ErrorResponse, SessionRequest, SessionResponse, TestcaseRequest, TestcasesRequest,
};
use reqwest::Client;

#[derive(Clone)]
pub struct IngressClient {
    client: Client,
    endpoint: String,
    api_key: String,
}

impl IngressClient {
    pub fn new() -> Result<Self, ReporterError> {
        let client = Client::new();
        let endpoint = match std::env::var("GREENER_INGRESS_ENDPOINT") {
            Ok(x) => x,
            Err(e) => {
                return Err(ReporterError::InvalidArgument(format!(
                    "cannot get GREENER_INGRESS_ENDPOINT: {}",
                    e
                )));
            }
        };

        let api_key = match std::env::var("GREENER_INGRESS_API_KEY") {
            Ok(x) => x,
            Err(e) => {
                return Err(ReporterError::InvalidArgument(format!(
                    "cannot get GREENER_INGRESS_API_KEY: {}",
                    e
                )));
            }
        };

        Ok(IngressClient {
            client,
            endpoint,
            api_key,
        })
    }

    pub async fn create_session(&self, session: SessionRequest) -> Result<String, ReporterError> {
        let resp = self
            .client
            .post(format!("{}/ingress/sessions", self.endpoint))
            .header("X-API-Key", &self.api_key)
            .json(&session)
            .send()
            .await
            .map_err(|e| ReporterError::Unknown(format!("error sending session request: {}", e)))?;

        let status = resp.status();
        if !status.is_success() {
            let error_msg = match resp.text().await {
                Ok(x) => match serde_json::from_str::<ErrorResponse>(&x) {
                    Ok(err_resp) => err_resp.message,
                    Err(_) => x,
                },
                Err(_) => "".to_string(),
            };
            return Err(ReporterError::Ingress(
                format!("failed session request: {}", error_msg),
                status.as_u16(),
            ));
        }

        let session = resp.json::<SessionResponse>().await.map_err(|e| {
            ReporterError::Unknown(format!("error parsing session response: {}", e))
        })?;

        Ok(session.id)
    }

    pub async fn create_testcases(
        &self,
        testcases: Vec<TestcaseRequest>,
    ) -> Result<(), ReporterError> {
        let resp = self
            .client
            .post(format!("{}/ingress/testcases", self.endpoint))
            .header("X-API-KEY", &self.api_key)
            .json(&TestcasesRequest { testcases })
            .send()
            .await
            .map_err(|e| {
                eprintln!("ERROR: {}", e);
                ReporterError::Unknown(format!("error sending testcase request: {}", e))
            })?;

        let status = resp.status();
        if !status.is_success() {
            let error_msg = match resp.text().await {
                Ok(x) => match serde_json::from_str::<ErrorResponse>(&x) {
                    Ok(err_resp) => err_resp.message,
                    Err(_) => x,
                },
                Err(_) => "".to_string(),
            };
            return Err(ReporterError::Ingress(
                format!("failed testcase request: {}", error_msg),
                status.as_u16(),
            ));
        }

        Ok(())
    }
}
