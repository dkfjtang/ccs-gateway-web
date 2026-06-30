use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Serialize)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

impl RpcError {
    pub fn parse_error() -> Self {
        Self {
            code: -32700,
            message: "Parse error".into(),
            data: None,
        }
    }

    pub fn invalid_request(msg: impl Into<String>) -> Self {
        Self {
            code: -32600,
            message: msg.into(),
            data: None,
        }
    }

    pub fn method_not_found(method: &str) -> Self {
        Self {
            code: -32601,
            message: format!("Method not found: {}", method),
            data: None,
        }
    }

    pub fn invalid_params(msg: impl Into<String>) -> Self {
        Self {
            code: -32602,
            message: msg.into(),
            data: None,
        }
    }

    pub fn internal_error(msg: impl Into<String>) -> Self {
        Self {
            code: -32603,
            message: msg.into(),
            data: None,
        }
    }

    pub fn app_error(msg: impl Into<String>) -> Self {
        Self {
            code: -32001,
            message: msg.into(),
            data: None,
        }
    }

    pub fn capability_disabled(capability: &str, command: Option<&str>) -> Self {
        let mut data = serde_json::json!({
            "error": "capability_disabled",
            "capability": capability,
            "message": "This capability is disabled in the current ccs-web profile."
        });
        if let Some(command) = command {
            data["command"] = serde_json::json!(command);
        }
        Self {
            code: -32043,
            message: "capability_disabled".into(),
            data: Some(data),
        }
    }
}
