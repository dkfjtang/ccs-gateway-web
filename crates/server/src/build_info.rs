use serde::Serialize;

use crate::profile::{CapabilityManifest, CcsWebProfile, ProfileConfig};

#[derive(Debug, Clone, Serialize)]
pub struct BuildInfo {
    pub build_id: String,
    pub assets: Vec<String>,
    pub profile: CcsWebProfile,
    pub capabilities: CapabilityManifest,
}

pub fn build_info_from_assets(
    profile: &ProfileConfig,
    mut assets: Vec<String>,
    fallback_build_id: &str,
) -> BuildInfo {
    assets.sort();
    assets.dedup();
    let build_id = if assets.is_empty() {
        fallback_build_id.to_string()
    } else {
        assets.join(",")
    };

    BuildInfo {
        build_id,
        assets,
        profile: profile.profile,
        capabilities: profile.manifest(),
    }
}

pub fn build_id_from_index_html(html: &str) -> String {
    index_assets_from_html(html).join(",")
}

pub fn index_assets_from_html(html: &str) -> Vec<String> {
    let mut assets = Vec::new();
    let mut remaining = html;

    while let Some(start) = remaining.find("assets/index-") {
        let candidate = &remaining[start..];
        let end = candidate
            .find(|ch| matches!(ch, '"' | '\'' | '<' | '>' | ' ' | '\n' | '\r' | '\t'))
            .unwrap_or(candidate.len());
        let asset = candidate[..end].trim_start_matches('/').to_string();
        if !assets.contains(&asset) {
            assets.push(asset);
        }
        remaining = &candidate[end..];
    }

    assets.sort();
    assets
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::profile::CapabilityGroup;

    #[test]
    fn build_id_from_index_html_uses_main_assets() {
        let html = r#"<!doctype html>
<script type="module" crossorigin src="./assets/index-BTaiIF1Z.js"></script>
<link rel="stylesheet" crossorigin href="./assets/index-CY8IdWrI.css">
<script type="module" crossorigin src="./assets/vendor-react.js"></script>"#;

        let build_id = build_id_from_index_html(html);

        assert_eq!(
            build_id,
            "assets/index-BTaiIF1Z.js,assets/index-CY8IdWrI.css"
        );
    }

    #[test]
    fn build_info_exposes_profile_and_capabilities_without_runtime_paths() {
        let profile = ProfileConfig::from_env_value(Some("slim")).unwrap();
        let info = build_info_from_assets(
            &profile,
            vec!["assets/index-BTaiIF1Z.js".to_string()],
            "fallback",
        );
        let json = serde_json::to_string(&info).unwrap();

        assert_eq!(info.profile, CcsWebProfile::Slim);
        assert!(info
            .capabilities
            .disabled_groups
            .contains(&CapabilityGroup::AuthVault));
        assert!(json.contains(r#""profile":"slim""#));
        assert!(!json.contains(":\\"));
        assert!(!json.contains("/home/"));
        assert!(!json.contains("/Users/"));
    }
}
