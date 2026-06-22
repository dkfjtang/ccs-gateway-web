use serde::Deserialize;
use std::collections::HashMap;
use std::path::PathBuf;
use url::Url;

#[derive(Debug, Deserialize)]
struct TokenVaultFile {
    #[serde(default)]
    sites: HashMap<String, SiteVaultEntry>,
    #[serde(default)]
    #[serde(rename = "tokenVault")]
    token_vault: HashMap<String, TokenVaultEntry>,
}

#[derive(Debug, Deserialize)]
struct SiteVaultEntry {
    #[serde(rename = "authToken")]
    auth_token: Option<String>,
    #[serde(rename = "cookieHeader")]
    cookie_header: Option<String>,
}

#[derive(Debug, Deserialize)]
struct TokenVaultEntry {
    value: String,
}

fn default_vault_path() -> PathBuf {
    crate::config::get_app_config_dir()
        .join("auth-vault")
        .join("tokens.json")
}

fn vault_path() -> PathBuf {
    std::env::var("CCS_USAGE_TOKEN_VAULT_PATH")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(default_vault_path)
}

fn load_vault_file() -> Option<TokenVaultFile> {
    let path = vault_path();
    let Ok(raw) = std::fs::read_to_string(path) else {
        return None;
    };
    let Ok(file) = serde_json::from_str::<TokenVaultFile>(&raw) else {
        return None;
    };
    Some(file)
}

pub(crate) fn load_tokens() -> HashMap<String, String> {
    let Some(file) = load_vault_file() else {
        return HashMap::new();
    };
    file.token_vault
        .into_iter()
        .filter_map(|(name, entry)| {
            let value = entry.value.trim().to_string();
            if name.is_empty() || value.is_empty() {
                None
            } else {
                Some((name, value))
            }
        })
        .collect()
}

pub(crate) fn replace_vault_tokens(value: &str, tokens: &HashMap<String, String>) -> String {
    tokens.iter().fold(value.to_string(), |acc, (name, token)| {
        acc.replace(&format!("{{{{{name}}}}}"), token)
    })
}

pub(crate) fn replace_site_vault_vars(value: &str, request_url: &str) -> String {
    let Some(file) = load_vault_file() else {
        return value.to_string();
    };
    let tokens = file
        .token_vault
        .iter()
        .filter_map(|(name, entry)| {
            let value = entry.value.trim();
            if name.is_empty() || value.is_empty() {
                None
            } else {
                Some((name.clone(), value.to_string()))
            }
        })
        .collect::<HashMap<_, _>>();
    let mut replaced = replace_vault_tokens(value, &tokens);

    let host = Url::parse(request_url)
        .ok()
        .and_then(|url| url.host_str().map(|host| host.to_lowercase()));
    let Some(host) = host else {
        return replaced;
    };

    let Some(site) = file.sites.get(&host) else {
        return replaced;
    };

    if let Some(auth_token) = site
        .auth_token
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        replaced = replaced.replace("{{authToken}}", auth_token);
    }
    if let Some(cookie_header) = site
        .cookie_header
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        replaced = replaced.replace("{{cookieHeader}}", cookie_header);
    }

    replaced
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replaces_named_vault_token_placeholders() {
        let tokens = HashMap::from([(
            "sub2_congmingai_com__auth_token".to_string(),
            "secret-token".to_string(),
        )]);

        let replaced = replace_vault_tokens("Bearer {{sub2_congmingai_com__auth_token}}", &tokens);

        assert_eq!(replaced, "Bearer secret-token");
    }

    #[test]
    fn leaves_unknown_placeholders_unchanged() {
        let tokens = HashMap::new();

        let replaced = replace_vault_tokens("Bearer {{missing_token}}", &tokens);

        assert_eq!(replaced, "Bearer {{missing_token}}");
    }

    #[test]
    fn replaces_site_scoped_auth_placeholders() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = dir.path().join("tokens.json");
        std::fs::write(
            &path,
            r#"{
              "schemaVersion": 1,
              "sites": {
                "sub2.congmingai.com": {
                  "origin": "https://sub2.congmingai.com",
                  "host": "sub2.congmingai.com",
                  "authToken": "site-token",
                  "cookieHeader": "session=site-cookie; csrf=token"
                }
              },
              "tokenVault": {}
            }"#,
        )
        .expect("write vault");
        std::env::set_var("CCS_USAGE_TOKEN_VAULT_PATH", &path);

        let replaced = replace_site_vault_vars(
            "Bearer {{authToken}} | {{cookieHeader}}",
            "https://sub2.congmingai.com/api/user/self",
        );

        std::env::remove_var("CCS_USAGE_TOKEN_VAULT_PATH");
        assert_eq!(
            replaced,
            "Bearer site-token | session=site-cookie; csrf=token"
        );
    }

    #[test]
    fn does_not_cross_site_replace_fixed_placeholders() {
        let dir = tempfile::tempdir().expect("temp dir");
        let path = dir.path().join("tokens.json");
        std::fs::write(
            &path,
            r#"{
              "schemaVersion": 1,
              "sites": {
                "sub2.congmingai.com": {
                  "origin": "https://sub2.congmingai.com",
                  "host": "sub2.congmingai.com",
                  "authToken": "site-token",
                  "cookieHeader": "session=site-cookie"
                }
              },
              "tokenVault": {}
            }"#,
        )
        .expect("write vault");
        std::env::set_var("CCS_USAGE_TOKEN_VAULT_PATH", &path);

        let replaced = replace_site_vault_vars(
            "Bearer {{authToken}} | {{cookieHeader}}",
            "https://other.example.com/api/user/self",
        );

        std::env::remove_var("CCS_USAGE_TOKEN_VAULT_PATH");
        assert_eq!(replaced, "Bearer {{authToken}} | {{cookieHeader}}");
    }
}
