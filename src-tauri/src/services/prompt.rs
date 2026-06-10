use indexmap::IndexMap;

use crate::app_config::AppType;
use crate::config::write_text_file;
use crate::error::AppError;
use crate::prompt::{caveman_prompt, CavemanStyleProfile, Prompt};
use crate::prompt_files::prompt_file_path;
use crate::store::AppState;

/// 安全地获取当前 Unix 时间戳
fn get_unix_timestamp() -> Result<i64, AppError> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .map_err(|e| AppError::Message(format!("Failed to get system time: {e}")))
}

pub struct PromptService;

impl PromptService {
    pub fn create_caveman_style_profile(
        state: &AppState,
        app: AppType,
        profile: CavemanStyleProfile,
    ) -> Result<String, AppError> {
        let prompt = caveman_prompt(profile);
        let id = prompt.id.clone();
        let existing = state.db.get_prompts(app.as_str())?;
        if existing.contains_key(&id) {
            return Ok(id);
        }

        state.db.save_prompt(app.as_str(), &prompt)?;
        Ok(id)
    }
    pub fn get_prompts(
        state: &AppState,
        app: AppType,
    ) -> Result<IndexMap<String, Prompt>, AppError> {
        state.db.get_prompts(app.as_str())
    }

    pub fn upsert_prompt(
        state: &AppState,
        app: AppType,
        _id: &str,
        prompt: Prompt,
    ) -> Result<(), AppError> {
        // 检查是否为已启用的提示词
        let is_enabled = prompt.enabled;

        state.db.save_prompt(app.as_str(), &prompt)?;

        if is_enabled {
            // 启用提示词：写入内容到文件
            let target_path = prompt_file_path(&app)?;
            write_text_file(&target_path, &prompt.content)?;
        } else {
            // 禁用提示词：如果还有其他已启用项，live 文件应跟随剩余启用项
            let prompts = state.db.get_prompts(app.as_str())?;
            let enabled_prompt = prompts.values().find(|p| p.enabled);
            let target_path = prompt_file_path(&app)?;

            if let Some(enabled_prompt) = enabled_prompt {
                write_text_file(&target_path, &enabled_prompt.content)?;
            } else if target_path.exists() {
                // 所有提示词都已禁用，清空文件
                write_text_file(&target_path, "")?;
            }
        }

        Ok(())
    }

    pub fn delete_prompt(state: &AppState, app: AppType, id: &str) -> Result<(), AppError> {
        let prompts = state.db.get_prompts(app.as_str())?;

        if let Some(prompt) = prompts.get(id) {
            if prompt.enabled {
                return Err(AppError::InvalidInput("无法删除已启用的提示词".to_string()));
            }
        }

        state.db.delete_prompt(app.as_str(), id)?;
        Ok(())
    }

    pub fn enable_prompt(state: &AppState, app: AppType, id: &str) -> Result<(), AppError> {
        // 回填当前 live 文件内容到已启用的提示词，或创建备份
        let target_path = prompt_file_path(&app)?;
        if target_path.exists() {
            if let Ok(live_content) = std::fs::read_to_string(&target_path) {
                if !live_content.trim().is_empty() {
                    let mut prompts = state.db.get_prompts(app.as_str())?;

                    // 尝试回填到当前已启用的提示词
                    if let Some((enabled_id, enabled_prompt)) = prompts
                        .iter_mut()
                        .find(|(_, p)| p.enabled)
                        .map(|(id, p)| (id.clone(), p))
                    {
                        let timestamp = get_unix_timestamp()?;
                        enabled_prompt.content = live_content.clone();
                        enabled_prompt.updated_at = Some(timestamp);
                        log::info!("回填 live 提示词内容到已启用项: {enabled_id}");
                        state.db.save_prompt(app.as_str(), enabled_prompt)?;
                    } else {
                        // 没有已启用的提示词，则创建一次备份（避免重复备份）
                        let content_exists = prompts
                            .values()
                            .any(|p| p.content.trim() == live_content.trim());
                        if !content_exists {
                            let timestamp = std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .unwrap_or_default()
                                .as_secs() as i64;
                            let backup_id = format!("backup-{timestamp}");
                            let backup_prompt = Prompt {
                                id: backup_id.clone(),
                                name: format!(
                                    "原始提示词 {}",
                                    chrono::Local::now().format("%Y-%m-%d %H:%M")
                                ),
                                content: live_content,
                                description: Some("自动备份的原始提示词".to_string()),
                                enabled: false,
                                created_at: Some(timestamp),
                                updated_at: Some(timestamp),
                            };
                            log::info!("回填 live 提示词内容，创建备份: {backup_id}");
                            state.db.save_prompt(app.as_str(), &backup_prompt)?;
                        }
                    }
                }
            }
        }

        // 启用目标提示词并写入文件
        let mut prompts = state.db.get_prompts(app.as_str())?;

        for prompt in prompts.values_mut() {
            prompt.enabled = false;
        }

        if let Some(prompt) = prompts.get_mut(id) {
            prompt.enabled = true;
            write_text_file(&target_path, &prompt.content)?; // 原子写入
            state.db.save_prompt(app.as_str(), prompt)?;
        } else {
            return Err(AppError::InvalidInput(format!("提示词 {id} 不存在")));
        }

        // Save all prompts to disable others
        for (_, prompt) in prompts.iter() {
            state.db.save_prompt(app.as_str(), prompt)?;
        }

        Ok(())
    }

    pub fn import_from_file(state: &AppState, app: AppType) -> Result<String, AppError> {
        let file_path = prompt_file_path(&app)?;

        if !file_path.exists() {
            return Err(AppError::Message("提示词文件不存在".to_string()));
        }

        let content =
            std::fs::read_to_string(&file_path).map_err(|e| AppError::io(&file_path, e))?;
        let timestamp = get_unix_timestamp()?;

        let id = format!("imported-{timestamp}");
        let prompt = Prompt {
            id: id.clone(),
            name: format!(
                "导入的提示词 {}",
                chrono::Local::now().format("%Y-%m-%d %H:%M")
            ),
            content,
            description: Some("从现有配置文件导入".to_string()),
            enabled: false,
            created_at: Some(timestamp),
            updated_at: Some(timestamp),
        };

        Self::upsert_prompt(state, app, &id, prompt)?;
        Ok(id)
    }

    pub fn get_current_file_content(app: AppType) -> Result<Option<String>, AppError> {
        let file_path = prompt_file_path(&app)?;
        if !file_path.exists() {
            return Ok(None);
        }
        let content =
            std::fs::read_to_string(&file_path).map_err(|e| AppError::io(&file_path, e))?;
        Ok(Some(content))
    }

    /// 首次启动时从现有提示词文件自动导入（如果存在）
    /// 返回导入的数量
    pub fn import_from_file_on_first_launch(
        state: &AppState,
        app: AppType,
    ) -> Result<usize, AppError> {
        // 幂等性保护：该应用已有提示词则跳过
        let existing = state.db.get_prompts(app.as_str())?;
        if !existing.is_empty() {
            return Ok(0);
        }

        let file_path = prompt_file_path(&app)?;

        // 检查文件是否存在
        if !file_path.exists() {
            return Ok(0);
        }

        // 读取文件内容
        let content = match std::fs::read_to_string(&file_path) {
            Ok(c) => c,
            Err(e) => {
                log::warn!("读取提示词文件失败: {file_path:?}, 错误: {e}");
                return Ok(0);
            }
        };

        // 检查内容是否为空
        if content.trim().is_empty() {
            return Ok(0);
        }

        log::info!("发现提示词文件，自动导入: {file_path:?}");

        // 创建提示词对象
        let timestamp = get_unix_timestamp()?;
        let id = format!("auto-imported-{timestamp}");
        let prompt = Prompt {
            id: id.clone(),
            name: format!(
                "Auto-imported Prompt {}",
                chrono::Local::now().format("%Y-%m-%d %H:%M")
            ),
            content,
            description: Some("Automatically imported on first launch".to_string()),
            enabled: true, // 首次导入时自动启用
            created_at: Some(timestamp),
            updated_at: Some(timestamp),
        };

        // 保存到数据库
        state.db.save_prompt(app.as_str(), &prompt)?;

        log::info!("自动导入完成: {}", app.as_str());
        Ok(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::database::Database;
    use std::sync::{Arc, Mutex};
    use tempfile::tempdir;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    struct TestHome {
        _guard: std::sync::MutexGuard<'static, ()>,
        dir: tempfile::TempDir,
        old_test_home: Option<std::ffi::OsString>,
        old_home: Option<std::ffi::OsString>,
    }

    impl TestHome {
        fn new() -> Self {
            let guard = ENV_LOCK.lock().expect("env lock");
            let dir = tempdir().expect("tempdir");
            let old_test_home = std::env::var_os("CC_SWITCH_TEST_HOME");
            let old_home = std::env::var_os("HOME");
            std::env::set_var("CC_SWITCH_TEST_HOME", dir.path());
            std::env::set_var("HOME", dir.path());
            Self {
                _guard: guard,
                dir,
                old_test_home,
                old_home,
            }
        }

        fn path(&self) -> &std::path::Path {
            self.dir.path()
        }
    }

    impl Drop for TestHome {
        fn drop(&mut self) {
            match &self.old_test_home {
                Some(value) => std::env::set_var("CC_SWITCH_TEST_HOME", value),
                None => std::env::remove_var("CC_SWITCH_TEST_HOME"),
            }
            match &self.old_home {
                Some(value) => std::env::set_var("HOME", value),
                None => std::env::remove_var("HOME"),
            }
        }
    }

    fn test_state() -> AppState {
        let db = Arc::new(Database::memory().expect("memory db"));
        AppState::new(db)
    }

    #[test]
    fn caveman_enable_switches_from_normal_prompt_and_writes_prompt_file() {
        let home = TestHome::new();
        let state = test_state();
        let app = AppType::OpenClaw;
        let normal_prompt = Prompt {
            id: "normal".to_string(),
            name: "Normal prompt".to_string(),
            content: "normal prompt body".to_string(),
            description: None,
            enabled: true,
            created_at: Some(1),
            updated_at: Some(1),
        };

        PromptService::upsert_prompt(&state, app.clone(), "normal", normal_prompt)
            .expect("save normal prompt");
        PromptService::create_caveman_style_profile(&state, app.clone(), CavemanStyleProfile::Full)
            .expect("create caveman full");
        PromptService::enable_prompt(&state, app.clone(), "caveman-full")
            .expect("enable caveman full");

        let prompts = state.db.get_prompts(app.as_str()).expect("get prompts");
        assert_eq!(prompts["normal"].enabled, false);
        assert_eq!(prompts["caveman-full"].enabled, true);

        let live_path = home.path().join(".openclaw").join("AGENTS.md");
        let live = std::fs::read_to_string(&live_path)
            .unwrap_or_else(|err| panic!("read {}: {err}", live_path.display()));
        assert!(live.contains("Mode: full"));
        assert!(live.contains("Auto-clarity exits"));
    }

    #[test]
    fn caveman_can_be_turned_off_without_deleting_the_preset() {
        let home = TestHome::new();
        let state = test_state();
        let app = AppType::OpenClaw;

        PromptService::create_caveman_style_profile(&state, app.clone(), CavemanStyleProfile::Lite)
            .expect("create caveman lite");
        PromptService::enable_prompt(&state, app.clone(), "caveman-lite")
            .expect("enable caveman lite");

        let mut prompt =
            state.db.get_prompts(app.as_str()).expect("get prompts")["caveman-lite"].clone();
        prompt.enabled = false;
        PromptService::upsert_prompt(&state, app.clone(), "caveman-lite", prompt)
            .expect("disable caveman lite");

        let prompts = state.db.get_prompts(app.as_str()).expect("get prompts");
        assert!(prompts.contains_key("caveman-lite"));
        assert_eq!(prompts["caveman-lite"].enabled, false);

        let live_path = home.path().join(".openclaw").join("AGENTS.md");
        let live = std::fs::read_to_string(&live_path)
            .unwrap_or_else(|err| panic!("read {}: {err}", live_path.display()));
        assert_eq!(live, "");
    }

    #[test]
    fn caveman_turn_off_restores_remaining_enabled_prompt() {
        let home = TestHome::new();
        let state = test_state();
        let app = AppType::OpenClaw;

        PromptService::create_caveman_style_profile(&state, app.clone(), CavemanStyleProfile::Lite)
            .expect("create caveman lite");
        PromptService::enable_prompt(&state, app.clone(), "caveman-lite")
            .expect("enable caveman lite");

        let normal_prompt = Prompt {
            id: "normal".to_string(),
            name: "Normal prompt".to_string(),
            content: "normal prompt body".to_string(),
            description: None,
            enabled: true,
            created_at: Some(1),
            updated_at: Some(1),
        };
        state
            .db
            .save_prompt(app.as_str(), &normal_prompt)
            .expect("insert abnormal enabled normal prompt");

        let mut caveman_prompt =
            state.db.get_prompts(app.as_str()).expect("get prompts")["caveman-lite"].clone();
        caveman_prompt.enabled = false;
        PromptService::upsert_prompt(&state, app.clone(), "caveman-lite", caveman_prompt)
            .expect("disable caveman lite");

        let prompts = state.db.get_prompts(app.as_str()).expect("get prompts");
        assert_eq!(prompts["caveman-lite"].enabled, false);
        assert_eq!(prompts["normal"].enabled, true);

        let live_path = home.path().join(".openclaw").join("AGENTS.md");
        let live = std::fs::read_to_string(&live_path)
            .unwrap_or_else(|err| panic!("read {}: {err}", live_path.display()));
        assert_eq!(live, "normal prompt body");
    }
}
