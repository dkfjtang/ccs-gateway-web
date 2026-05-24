use std::collections::BTreeSet;
use std::fs;
use std::path::PathBuf;

use cc_switch_core::WEB_COMPAT_TAURI_COMMANDS;
use cc_switch_server::api::{PUBLIC_METHODS, RPC_BUSINESS_METHODS, WS_PROTOCOL_METHODS};

fn sorted_set<'a>(items: &'a [&'a str]) -> BTreeSet<&'a str> {
    items.iter().copied().collect()
}

fn dispatch_match_methods() -> BTreeSet<String> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let dispatch_path = manifest_dir.join("src/api/dispatch.rs");
    let source = fs::read_to_string(&dispatch_path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", dispatch_path.display()));

    let mut methods = BTreeSet::new();
    let bytes = source.as_bytes();
    let mut i = 0;

    while i < bytes.len() {
        if bytes[i] != b'"' {
            i += 1;
            continue;
        }

        let start = i + 1;
        let mut end = start;
        while end < bytes.len() && bytes[end] != b'"' {
            end += 1;
        }
        if end >= bytes.len() {
            break;
        }

        let mut cursor = end + 1;
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }

        if cursor + 1 < bytes.len() && bytes[cursor] == b'=' && bytes[cursor + 1] == b'>' {
            methods.insert(source[start..end].to_string());
        }

        i = end + 1;
    }

    methods
}

const FRONTEND_DESKTOP_ONLY_METHODS: &[&str] = &[];

fn collect_source_files(dir: &std::path::Path, out: &mut Vec<PathBuf>) {
    let entries =
        fs::read_dir(dir).unwrap_or_else(|err| panic!("failed to read {}: {err}", dir.display()));
    for entry in entries {
        let entry = entry.unwrap_or_else(|err| panic!("failed to read dir entry: {err}"));
        let path = entry.path();
        if path.is_dir() {
            collect_source_files(&path, out);
            continue;
        }
        let Some(ext) = path.extension().and_then(|ext| ext.to_str()) else {
            continue;
        };
        if matches!(ext, "ts" | "tsx") {
            out.push(path);
        }
    }
}

fn frontend_invoke_methods() -> BTreeSet<String> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let src_root = manifest_dir.join("../../src");
    let mut files = Vec::new();
    collect_source_files(&src_root, &mut files);

    let mut methods = BTreeSet::new();
    for path in files {
        let source = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()));
        let bytes = source.as_bytes();
        let mut i = 0;

        while i + 6 <= bytes.len() {
            if &bytes[i..i + 6] != b"invoke" {
                i += 1;
                continue;
            }

            let mut cursor = i + 6;
            while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
                cursor += 1;
            }

            if cursor < bytes.len() && bytes[cursor] == b'<' {
                let mut depth = 1usize;
                cursor += 1;
                while cursor < bytes.len() && depth > 0 {
                    match bytes[cursor] {
                        b'<' => depth += 1,
                        b'>' => depth -= 1,
                        _ => {}
                    }
                    cursor += 1;
                }
            }

            while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
                cursor += 1;
            }
            if cursor >= bytes.len() || bytes[cursor] != b'(' {
                i += 1;
                continue;
            }
            cursor += 1;

            while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
                cursor += 1;
            }
            if cursor >= bytes.len() || !matches!(bytes[cursor], b'"' | b'\'') {
                i += 1;
                continue;
            }

            let quote = bytes[cursor];
            let start = cursor + 1;
            let mut end = start;
            while end < bytes.len() && bytes[end] != quote {
                end += 1;
            }
            if end < bytes.len() {
                methods.insert(source[start..end].to_string());
            }
            i = end.saturating_add(1);
        }
    }

    methods
}

#[test]
fn tauri_and_rpc_business_methods_stay_in_sync() {
    let tauri_methods = sorted_set(WEB_COMPAT_TAURI_COMMANDS);
    let rpc_methods = sorted_set(RPC_BUSINESS_METHODS);

    let missing_in_rpc: Vec<_> = tauri_methods.difference(&rpc_methods).copied().collect();
    assert!(
        missing_in_rpc.is_empty(),
        "web-compatible Tauri commands missing in RPC dispatch: {:?}",
        missing_in_rpc
    );

    let unexpected_rpc: Vec<_> = rpc_methods.difference(&tauri_methods).copied().collect();
    assert!(
        unexpected_rpc.is_empty(),
        "RPC business methods missing in Tauri compatibility list: {:?}",
        unexpected_rpc
    );
}

#[test]
fn protocol_method_whitelists_only_reference_live_entries() {
    let rpc_methods = sorted_set(RPC_BUSINESS_METHODS);
    let tauri_methods = sorted_set(WEB_COMPAT_TAURI_COMMANDS);
    let invoke_public = sorted_set(PUBLIC_METHODS);
    let ws_protocol = sorted_set(WS_PROTOCOL_METHODS);

    for method in PUBLIC_METHODS {
        assert!(
            !rpc_methods.contains(method),
            "public auth method {method} should stay out of RPC business methods"
        );
        assert!(
            !tauri_methods.contains(method),
            "public auth method {method} should stay out of Tauri compatibility methods"
        );
        assert!(
            invoke_public.contains(method),
            "public auth method whitelist contains stale entry {method}"
        );
    }

    for method in WS_PROTOCOL_METHODS {
        assert!(
            !rpc_methods.contains(method),
            "WS protocol method {method} should stay out of RPC business methods"
        );
        assert!(
            !tauri_methods.contains(method),
            "WS protocol method {method} should stay out of Tauri compatibility methods"
        );
        assert!(
            ws_protocol.contains(method),
            "WS protocol whitelist contains stale entry {method}"
        );
    }
}

#[test]
fn rpc_business_methods_have_real_dispatch_arms() {
    let dispatch_methods = dispatch_match_methods();
    let missing_dispatch: Vec<_> = RPC_BUSINESS_METHODS
        .iter()
        .copied()
        .filter(|method| !dispatch_methods.contains(*method))
        .collect();

    assert!(
        missing_dispatch.is_empty(),
        "RPC business methods missing match arms in dispatch.rs: {:?}",
        missing_dispatch
    );
}

#[test]
fn frontend_invokes_are_backed_by_rpc_or_explicitly_desktop_only() {
    let frontend_methods = frontend_invoke_methods();
    let rpc_methods = sorted_set(RPC_BUSINESS_METHODS);
    let desktop_only = sorted_set(FRONTEND_DESKTOP_ONLY_METHODS);

    let missing: Vec<_> = frontend_methods
        .iter()
        .filter(|method| {
            !rpc_methods.contains(method.as_str()) && !desktop_only.contains(method.as_str())
        })
        .cloned()
        .collect();
    assert!(
        missing.is_empty(),
        "frontend invoke methods missing in RPC dispatch: {:?}",
        missing
    );

    let stale_allowlist: Vec<_> = FRONTEND_DESKTOP_ONLY_METHODS
        .iter()
        .copied()
        .filter(|method| rpc_methods.contains(method))
        .collect();
    assert!(
        stale_allowlist.is_empty(),
        "frontend desktop-only allowlist contains RPC-backed methods: {:?}",
        stale_allowlist
    );
}
