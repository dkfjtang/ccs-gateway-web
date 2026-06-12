#![allow(non_snake_case)]

use tauri::AppHandle;

fn merge_settings_for_save(
    mut incoming: crate::settings::AppSettings,
    existing: &crate::settings::AppSettings,
) -> crate::settings::AppSettings {
    match (&mut incoming.webdav_sync, &existing.webdav_sync) {
        // incoming 没有 webdav → 保留现有
        (None, _) => {
            incoming.webdav_sync = existing.webdav_sync.clone();
        }
        // incoming 有 webdav 但密码为空，且现有有密码 → 填回现有密码
        // （get_settings_for_frontend 总是清空密码，所以通过 save_settings
        //   传入的空密码意味着"保持现有"而非"用户主动清空"）
        (Some(incoming_sync), Some(existing_sync))
            if incoming_sync.password.is_empty() && !existing_sync.password.is_empty() =>
        {
            incoming_sync.password = existing_sync.password.clone();
        }
        _ => {}
    }
    match (&mut incoming.s3_sync, &existing.s3_sync) {
        // incoming 没有 s3 → 保留现有
        (None, _) => {
            incoming.s3_sync = existing.s3_sync.clone();
        }
        // get_settings_for_frontend 总是清空 secret_access_key；通用 save_settings
        // 传入空 secret 表示保持现有，而不是主动清空。
        (Some(incoming_sync), Some(existing_sync))
            if incoming_sync.secret_access_key.is_empty()
                && !existing_sync.secret_access_key.is_empty() =>
        {
            incoming_sync.secret_access_key = existing_sync.secret_access_key.clone();
        }
        _ => {}
    }
    incoming
}

/// 获取设置
#[tauri::command]
pub async fn get_settings() -> Result<crate::settings::AppSettings, String> {
    Ok(crate::settings::get_settings_for_frontend())
}

/// 保存设置
#[tauri::command]
pub async fn save_settings(settings: crate::settings::AppSettings) -> Result<bool, String> {
    let existing = crate::settings::get_settings();
    let merged = merge_settings_for_save(settings, &existing);
    crate::settings::update_settings(merged).map_err(|e| e.to_string())?;
    Ok(true)
}

/// 重启应用程序（当 app_config_dir 变更后使用）
#[tauri::command]
pub async fn restart_app(app: AppHandle) -> Result<bool, String> {
    crate::save_window_state_before_exit(&app);

    // 在后台延迟重启，让函数有时间返回响应
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        app.restart();
    });
    Ok(true)
}

/// 获取 app_config_dir 覆盖配置 (从 Store)
#[tauri::command]
pub async fn get_app_config_dir_override(app: AppHandle) -> Result<Option<String>, String> {
    Ok(crate::app_store::refresh_app_config_dir_override(&app)
        .map(|p| p.to_string_lossy().to_string()))
}

/// 设置 app_config_dir 覆盖配置 (到 Store)
#[tauri::command]
pub async fn set_app_config_dir_override(
    app: AppHandle,
    path: Option<String>,
) -> Result<bool, String> {
    crate::app_store::set_app_config_dir_to_store(&app, path.as_deref())?;
    Ok(true)
}

/// 设置开机自启
#[tauri::command]
pub async fn set_auto_launch(enabled: bool) -> Result<bool, String> {
    if enabled {
        crate::auto_launch::enable_auto_launch().map_err(|e| format!("启用开机自启失败: {e}"))?;
    } else {
        crate::auto_launch::disable_auto_launch().map_err(|e| format!("禁用开机自启失败: {e}"))?;
    }
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::merge_settings_for_save;
    use crate::settings::{AppSettings, S3SyncSettings, WebDavSyncSettings};

    #[test]
    fn save_settings_should_preserve_existing_webdav_when_payload_omits_it() {
        let mut existing = AppSettings::default();
        existing.webdav_sync = Some(WebDavSyncSettings {
            base_url: "https://dav.example.com".to_string(),
            username: "alice".to_string(),
            password: "secret".to_string(),
            ..WebDavSyncSettings::default()
        });

        let incoming = AppSettings::default();
        let merged = merge_settings_for_save(incoming, &existing);

        assert!(merged.webdav_sync.is_some());
        assert_eq!(
            merged.webdav_sync.as_ref().map(|v| v.base_url.as_str()),
            Some("https://dav.example.com")
        );
    }

    #[test]
    fn save_settings_should_keep_incoming_webdav_when_present() {
        let mut existing = AppSettings::default();
        existing.webdav_sync = Some(WebDavSyncSettings {
            base_url: "https://dav.old.example.com".to_string(),
            username: "old".to_string(),
            password: "old-pass".to_string(),
            ..WebDavSyncSettings::default()
        });

        let mut incoming = AppSettings::default();
        incoming.webdav_sync = Some(WebDavSyncSettings {
            base_url: "https://dav.new.example.com".to_string(),
            username: "new".to_string(),
            password: "new-pass".to_string(),
            ..WebDavSyncSettings::default()
        });

        let merged = merge_settings_for_save(incoming, &existing);

        assert_eq!(
            merged.webdav_sync.as_ref().map(|v| v.base_url.as_str()),
            Some("https://dav.new.example.com")
        );
    }

    /// Regression test: frontend always receives empty password from
    /// get_settings_for_frontend(). If a component accidentally spreads
    /// the full settings object into save_settings, the empty password
    /// must NOT overwrite the existing one.
    #[test]
    fn save_settings_should_preserve_password_when_incoming_has_empty_password() {
        let mut existing = AppSettings::default();
        existing.webdav_sync = Some(WebDavSyncSettings {
            base_url: "https://dav.example.com".to_string(),
            username: "alice".to_string(),
            password: "secret".to_string(),
            ..WebDavSyncSettings::default()
        });

        // Simulate frontend sending settings with cleared password
        let mut incoming = AppSettings::default();
        incoming.webdav_sync = Some(WebDavSyncSettings {
            base_url: "https://dav.example.com".to_string(),
            username: "alice".to_string(),
            password: "".to_string(),
            ..WebDavSyncSettings::default()
        });

        let merged = merge_settings_for_save(incoming, &existing);

        assert_eq!(
            merged.webdav_sync.as_ref().map(|v| v.password.as_str()),
            Some("secret"),
            "empty password from frontend must not overwrite existing password"
        );
    }

    /// When both incoming and existing have no password, merge should
    /// work without panicking and keep the empty state.
    #[test]
    fn save_settings_should_handle_both_empty_passwords() {
        let mut existing = AppSettings::default();
        existing.webdav_sync = Some(WebDavSyncSettings {
            base_url: "https://dav.example.com".to_string(),
            username: "alice".to_string(),
            password: "".to_string(),
            ..WebDavSyncSettings::default()
        });

        let mut incoming = AppSettings::default();
        incoming.webdav_sync = Some(WebDavSyncSettings {
            base_url: "https://dav.example.com".to_string(),
            username: "alice".to_string(),
            password: "".to_string(),
            ..WebDavSyncSettings::default()
        });

        let merged = merge_settings_for_save(incoming, &existing);

        assert_eq!(
            merged.webdav_sync.as_ref().map(|v| v.password.as_str()),
            Some("")
        );
    }

    #[test]
    fn save_settings_should_preserve_existing_s3_when_payload_omits_it() {
        let mut existing = AppSettings::default();
        existing.s3_sync = Some(S3SyncSettings {
            region: "us-east-1".to_string(),
            bucket: "ccs-backup".to_string(),
            access_key_id: "AKID".to_string(),
            secret_access_key: "SECRET".to_string(),
            ..S3SyncSettings::default()
        });

        let incoming = AppSettings::default();
        let merged = merge_settings_for_save(incoming, &existing);

        assert!(merged.s3_sync.is_some());
        assert_eq!(
            merged.s3_sync.as_ref().map(|v| v.bucket.as_str()),
            Some("ccs-backup")
        );
        assert_eq!(
            merged
                .s3_sync
                .as_ref()
                .map(|v| v.secret_access_key.as_str()),
            Some("SECRET")
        );
    }

    #[test]
    fn save_settings_should_preserve_s3_secret_when_incoming_has_empty_secret() {
        let mut existing = AppSettings::default();
        existing.s3_sync = Some(S3SyncSettings {
            region: "us-east-1".to_string(),
            bucket: "ccs-backup".to_string(),
            access_key_id: "AKID".to_string(),
            secret_access_key: "SECRET".to_string(),
            ..S3SyncSettings::default()
        });

        let mut incoming = AppSettings::default();
        incoming.s3_sync = Some(S3SyncSettings {
            region: "us-east-1".to_string(),
            bucket: "ccs-backup".to_string(),
            access_key_id: "AKID".to_string(),
            secret_access_key: String::new(),
            ..S3SyncSettings::default()
        });

        let merged = merge_settings_for_save(incoming, &existing);

        assert_eq!(
            merged
                .s3_sync
                .as_ref()
                .map(|v| v.secret_access_key.as_str()),
            Some("SECRET"),
            "empty S3 secret from frontend must not overwrite existing secret"
        );
    }
}

/// 获取开机自启状态
#[tauri::command]
pub async fn get_auto_launch_status() -> Result<bool, String> {
    crate::auto_launch::is_auto_launch_enabled().map_err(|e| format!("获取开机自启状态失败: {e}"))
}

/// 获取整流器配置
#[tauri::command]
pub async fn get_rectifier_config(
    state: tauri::State<'_, crate::AppState>,
) -> Result<crate::proxy::types::RectifierConfig, String> {
    state.db.get_rectifier_config().map_err(|e| e.to_string())
}

/// 设置整流器配置
#[tauri::command]
pub async fn set_rectifier_config(
    state: tauri::State<'_, crate::AppState>,
    config: crate::proxy::types::RectifierConfig,
) -> Result<bool, String> {
    state
        .db
        .set_rectifier_config(&config)
        .map_err(|e| e.to_string())?;
    Ok(true)
}

/// 获取优化器配置
#[tauri::command]
pub async fn get_optimizer_config(
    state: tauri::State<'_, crate::AppState>,
) -> Result<crate::proxy::types::OptimizerConfig, String> {
    state.db.get_optimizer_config().map_err(|e| e.to_string())
}

/// 设置优化器配置
#[tauri::command]
pub async fn set_optimizer_config(
    state: tauri::State<'_, crate::AppState>,
    config: crate::proxy::types::OptimizerConfig,
) -> Result<bool, String> {
    // Validate cache_ttl: only allow known values
    match config.cache_ttl.as_str() {
        "5m" | "1h" => {}
        other => {
            return Err(format!(
                "Invalid cache_ttl value: '{other}'. Allowed values: '5m', '1h'"
            ))
        }
    }

    if config.token_saver_min_chars < 160 {
        return Err("Invalid token_saver_min_chars value: must be at least 160".to_string());
    }

    if config.token_saver_keep_chars < 80 {
        return Err("Invalid token_saver_keep_chars value: must be at least 80".to_string());
    }

    if config.token_saver_keep_chars >= config.token_saver_min_chars {
        return Err(
            "Invalid token_saver_keep_chars value: must be smaller than token_saver_min_chars"
                .to_string(),
        );
    }

    state
        .db
        .set_optimizer_config(&config)
        .map_err(|e| e.to_string())?;
    Ok(true)
}

/// 获取 Copilot 优化器配置
#[tauri::command]
pub async fn get_copilot_optimizer_config(
    state: tauri::State<'_, crate::AppState>,
) -> Result<crate::proxy::types::CopilotOptimizerConfig, String> {
    state
        .db
        .get_copilot_optimizer_config()
        .map_err(|e| e.to_string())
}

/// 设置 Copilot 优化器配置
#[tauri::command]
pub async fn set_copilot_optimizer_config(
    state: tauri::State<'_, crate::AppState>,
    config: crate::proxy::types::CopilotOptimizerConfig,
) -> Result<bool, String> {
    state
        .db
        .set_copilot_optimizer_config(&config)
        .map_err(|e| e.to_string())?;
    Ok(true)
}

/// 获取日志配置
#[tauri::command]
pub async fn get_log_config(
    state: tauri::State<'_, crate::AppState>,
) -> Result<crate::proxy::types::LogConfig, String> {
    state.db.get_log_config().map_err(|e| e.to_string())
}

/// 设置日志配置
#[tauri::command]
pub async fn set_log_config(
    state: tauri::State<'_, crate::AppState>,
    config: crate::proxy::types::LogConfig,
) -> Result<bool, String> {
    state
        .db
        .set_log_config(&config)
        .map_err(|e| e.to_string())?;
    log::set_max_level(config.to_level_filter());
    log::info!(
        "日志配置已更新: enabled={}, level={}",
        config.enabled,
        config.level
    );
    Ok(true)
}
