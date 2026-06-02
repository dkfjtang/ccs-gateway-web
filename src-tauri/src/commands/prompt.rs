use indexmap::IndexMap;
use std::str::FromStr;

use tauri::State;

use crate::app_config::AppType;
use crate::prompt::{CavemanStyleProfile, Prompt};
use crate::services::PromptService;
use crate::store::AppState;

fn parse_caveman_style_profile(profile: &str) -> Result<CavemanStyleProfile, String> {
    match profile {
        "lite" => Ok(CavemanStyleProfile::Lite),
        "full" => Ok(CavemanStyleProfile::Full),
        "ultra" => Ok(CavemanStyleProfile::Ultra),
        other => Err(format!("Invalid Caveman style profile: {other}")),
    }
}

#[tauri::command]
pub async fn get_prompts(
    app: String,
    state: State<'_, AppState>,
) -> Result<IndexMap<String, Prompt>, String> {
    let app_type = AppType::from_str(&app).map_err(|e| e.to_string())?;
    PromptService::get_prompts(&state, app_type).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn upsert_prompt(
    app: String,
    id: String,
    prompt: Prompt,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let app_type = AppType::from_str(&app).map_err(|e| e.to_string())?;
    PromptService::upsert_prompt(&state, app_type, &id, prompt).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_prompt(
    app: String,
    id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let app_type = AppType::from_str(&app).map_err(|e| e.to_string())?;
    PromptService::delete_prompt(&state, app_type, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn enable_prompt(
    app: String,
    id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let app_type = AppType::from_str(&app).map_err(|e| e.to_string())?;
    PromptService::enable_prompt(&state, app_type, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn import_prompt_from_file(
    app: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let app_type = AppType::from_str(&app).map_err(|e| e.to_string())?;
    PromptService::import_from_file(&state, app_type).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_current_prompt_file_content(app: String) -> Result<Option<String>, String> {
    let app_type = AppType::from_str(&app).map_err(|e| e.to_string())?;
    PromptService::get_current_file_content(app_type).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_caveman_style_profile(
    state: tauri::State<'_, AppState>,
    app: String,
    profile: String,
) -> Result<String, String> {
    let app_type = AppType::from_str(&app).map_err(|e| e.to_string())?;
    let profile = parse_caveman_style_profile(profile.as_str())?;
    PromptService::create_caveman_style_profile(&state, app_type, profile)
        .map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn caveman_style_profile_parser_rejects_unknown_modes() {
        assert!(matches!(
            parse_caveman_style_profile("lite"),
            Ok(CavemanStyleProfile::Lite)
        ));
        assert!(matches!(
            parse_caveman_style_profile("full"),
            Ok(CavemanStyleProfile::Full)
        ));
        assert!(matches!(
            parse_caveman_style_profile("ultra"),
            Ok(CavemanStyleProfile::Ultra)
        ));

        let err = parse_caveman_style_profile("custom").expect_err("custom mode rejected");
        assert!(err.contains("Invalid Caveman style profile: custom"));
    }
}
