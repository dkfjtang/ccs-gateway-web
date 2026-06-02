use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Prompt {
    pub id: String,
    pub name: String,
    pub content: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default)]
    pub enabled: bool,
    #[serde(rename = "createdAt", skip_serializing_if = "Option::is_none")]
    pub created_at: Option<i64>,
    #[serde(rename = "updatedAt", skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CavemanStyleProfile {
    Lite,
    Full,
    Ultra,
}

impl CavemanStyleProfile {
    pub fn id(self) -> &'static str {
        match self {
            Self::Lite => "lite",
            Self::Full => "full",
            Self::Ultra => "ultra",
        }
    }

    fn title(self) -> &'static str {
        match self {
            Self::Lite => "Caveman Lite",
            Self::Full => "Caveman Full",
            Self::Ultra => "Caveman Ultra",
        }
    }
}

pub fn caveman_prompt(profile: CavemanStyleProfile) -> Prompt {
    let id = format!("caveman-{}", profile.id());
    Prompt {
        id,
        name: format!("{} Style Profile", profile.title()),
        description: Some(
            "Opt-in Caveman response style. Does not rewrite proxy responses; enable manually per app."
                .to_string(),
        ),
        content: caveman_prompt_content(profile),
        enabled: false,
        created_at: None,
        updated_at: None,
    }
}

pub fn caveman_prompt_content(profile: CavemanStyleProfile) -> String {
    let mode_line = match profile {
        CavemanStyleProfile::Lite => {
            "Mode: lite. Lightly shorten prose while keeping normal clarity. Keep complete sentences when helpful."
        }
        CavemanStyleProfile::Full => {
            "Mode: full. Use compact fragments by default and remove filler aggressively. Pattern: [thing] [action] [reason]. [next step]."
        }
        CavemanStyleProfile::Ultra => {
            "Mode: ultra. Use the shortest clear wording possible; prefer terse fragments. Do not sacrifice safety, exactness, or user comprehension."
        }
    };
    format!("{CAVEMAN_BASE_RULES}\n{mode_line}\n")
}

const CAVEMAN_BASE_RULES: &str = r#"# Caveman Style Profile

You may use a terse Caveman-inspired response style when it improves token efficiency.

Core rules:
- Remove filler, pleasantries, hedging, and repeated setup.
- Keep technical terms, commands, code identifiers, paths, URLs, numbers, versions, and error text exact.
- Prefer short active fragments over long prose.
- Keep code blocks, diffs, commits, PR text, and error messages normal/exact.

Auto-clarity exits:
- Use normal clear prose for security warnings, destructive or irreversible actions, permission/auth changes, ambiguous multi-step instructions, user confusion, legal/safety-sensitive content, or anything where brevity could change meaning.
- After the clear section, you may resume the terse style.

Never:
- Do not hide risk or uncertainty.
- Do not omit required confirmation questions.
- Do not rewrite quoted code, logs, commands, JSON, YAML, TOML, SQL, XML, or env/config snippets.
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn caveman_prompt_is_disabled_by_default() {
        let prompt = caveman_prompt(CavemanStyleProfile::Full);
        assert_eq!(prompt.id, "caveman-full");
        assert!(!prompt.enabled);
        assert!(prompt
            .description
            .as_deref()
            .unwrap()
            .contains("enable manually per app"));
        assert!(prompt.content.contains("Auto-clarity exits"));
        assert!(prompt.content.contains("Do not rewrite quoted code"));
    }

    #[test]
    fn caveman_profiles_have_distinct_modes() {
        let lite = caveman_prompt_content(CavemanStyleProfile::Lite);
        let full = caveman_prompt_content(CavemanStyleProfile::Full);
        let ultra = caveman_prompt_content(CavemanStyleProfile::Ultra);
        assert!(lite.contains("Mode: lite"));
        assert!(full.contains("Mode: full"));
        assert!(ultra.contains("Mode: ultra"));
    }
}
