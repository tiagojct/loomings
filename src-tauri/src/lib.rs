use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use notify::RecursiveMode;
use notify_debouncer_mini::{new_debouncer, DebounceEventResult, Debouncer};
use tauri::menu::{AboutMetadataBuilder, MenuBuilder, MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder};
use tauri::path::BaseDirectory;
use tauri::{AppHandle, Emitter, Manager, State, WindowEvent};
use tauri_plugin_dialog::DialogExt;

type FileWatcher = Debouncer<notify::RecommendedWatcher>;

#[derive(Default)]
struct AppState {
    watcher: Mutex<Option<FileWatcher>>,
    watched_path: Mutex<Option<PathBuf>>,
    last_close_request: Mutex<Option<Instant>>,
}

#[derive(Serialize, Deserialize, Clone)]
struct FileOpenedPayload {
    path: String,
    content: String,
}

#[derive(Serialize, Deserialize)]
struct ScratchBuffer {
    content: String,
    current_file: Option<String>,
}

fn app_data_dir(app: &AppHandle) -> PathBuf {
    let dir = app
        .path()
        .app_data_dir()
        .expect("failed to resolve app_data_dir");
    if !dir.exists() {
        let _ = fs::create_dir_all(&dir);
    }
    dir
}

fn recent_path(app: &AppHandle) -> PathBuf {
    app_data_dir(app).join("recent.json")
}

fn scratch_path(app: &AppHandle) -> PathBuf {
    app_data_dir(app).join("scratch.json")
}

#[tauri::command]
fn save_file(path: String, content: String) -> Result<String, String> {
    fs::write(&path, content).map_err(|e| e.to_string())?;
    Ok(path)
}

#[tauri::command]
async fn save_file_as(app: AppHandle, content: String) -> Result<Option<String>, String> {
    let (tx, rx) = tokio::sync::oneshot::channel();
    app.dialog()
        .file()
        .add_filter("Markdown", &["md", "markdown", "txt"])
        .set_file_name("untitled.md")
        .set_title("Save Markdown File")
        .save_file(move |path| {
            let _ = tx.send(path);
        });
    let result = rx.await.map_err(|e| e.to_string())?;
    match result {
        Some(p) => {
            let path_str = p
                .into_path()
                .map_err(|e| e.to_string())?
                .to_string_lossy()
                .to_string();
            fs::write(&path_str, content).map_err(|e| e.to_string())?;
            Ok(Some(path_str))
        }
        None => Ok(None),
    }
}

#[tauri::command]
fn get_recent_files(app: AppHandle) -> Vec<String> {
    fs::read_to_string(recent_path(&app))
        .ok()
        .and_then(|s| serde_json::from_str::<Vec<String>>(&s).ok())
        .unwrap_or_default()
}

#[tauri::command]
fn add_recent_file(app: AppHandle, file_path: String) -> Result<(), String> {
    let mut rec = get_recent_files(app.clone());
    rec.retain(|f| f != &file_path);
    rec.insert(0, file_path);
    rec.truncate(10);
    let json = serde_json::to_string(&rec).map_err(|e| e.to_string())?;
    fs::write(recent_path(&app), json).map_err(|e| e.to_string())?;
    build_menu(&app).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
fn set_title(app: AppHandle, title: Option<String>) -> Result<(), String> {
    let window = app.get_webview_window("main").ok_or("main window missing")?;
    let final_title = match title.as_deref() {
        Some(t) if !t.is_empty() => format!("Loomings — {}", t),
        _ => "Loomings".to_string(),
    };
    window.set_title(&final_title).map_err(|e| e.to_string())
}

#[tauri::command]
fn save_scratch(app: AppHandle, content: String, current_file: Option<String>) -> Result<(), String> {
    let buf = ScratchBuffer { content, current_file };
    let json = serde_json::to_string(&buf).map_err(|e| e.to_string())?;
    fs::write(scratch_path(&app), json).map_err(|e| e.to_string())
}

#[tauri::command]
fn read_scratch(app: AppHandle) -> Option<ScratchBuffer> {
    fs::read_to_string(scratch_path(&app))
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
}

#[tauri::command]
fn clear_scratch(app: AppHandle) -> Result<(), String> {
    let p = scratch_path(&app);
    if p.exists() {
        fs::remove_file(p).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn confirm_quit(app: AppHandle) {
    app.exit(0);
}

#[tauri::command]
fn cancel_quit_request(state: State<AppState>) {
    *state.last_close_request.lock().unwrap() = None;
}

#[tauri::command]
fn watch_file(app: AppHandle, state: State<AppState>, path: String) -> Result<(), String> {
    let target = PathBuf::from(&path);
    let watched = fs::canonicalize(&target).unwrap_or(target);
    let parent = watched
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));

    {
        let mut current = state.watched_path.lock().unwrap();
        if current.as_ref() == Some(&watched) {
            return Ok(());
        }
        *current = Some(watched.clone());
    }

    let app_handle = app.clone();
    let watched_for_events = watched.clone();
    let watched_path_payload = path.clone();
    let mut debouncer = new_debouncer(
        Duration::from_millis(400),
        move |result: DebounceEventResult| {
            if let Ok(events) = result {
                for evt in events {
                    let evt_path = fs::canonicalize(&evt.path).unwrap_or_else(|_| evt.path.clone());
                    if evt_path == watched_for_events {
                        if let Ok(content) = fs::read_to_string(&watched_for_events) {
                            let _ = app_handle.emit(
                                "file-changed-on-disk",
                                FileOpenedPayload {
                                    path: watched_path_payload.clone(),
                                    content,
                                },
                            );
                        }
                    }
                }
            }
        },
    )
    .map_err(|e| e.to_string())?;

    debouncer
        .watcher()
        .watch(&parent, RecursiveMode::NonRecursive)
        .map_err(|e| e.to_string())?;

    *state.watcher.lock().unwrap() = Some(debouncer);
    Ok(())
}

#[derive(Serialize, Clone)]
struct UpdateInfo {
    version: String,
    url: String,
    body: String,
}

fn parse_semver(s: &str) -> Option<(u32, u32, u32)> {
    let s = s.trim_start_matches('v');
    let mut parts = s.split('.');
    let major: u32 = parts.next()?.parse().ok()?;
    let minor: u32 = parts.next()?.parse().ok()?;
    let patch_raw = parts.next()?;
    let patch: u32 = patch_raw.split(|c: char| !c.is_ascii_digit()).next()?.parse().ok()?;
    Some((major, minor, patch))
}

#[tauri::command]
fn check_for_update() -> Option<UpdateInfo> {
    let current = parse_semver(env!("CARGO_PKG_VERSION"))?;
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(5))
        .user_agent("loomings-update-check")
        .build();
    let resp = agent
        .get("https://api.github.com/repos/tiagojct/loomings/releases/latest")
        .call()
        .ok()?;
    let json: serde_json::Value = resp.into_json().ok()?;
    let tag = json.get("tag_name")?.as_str()?.to_string();
    let url = json
        .get("html_url")
        .and_then(|v| v.as_str())
        .unwrap_or("https://github.com/tiagojct/loomings/releases/latest")
        .to_string();
    let body = json
        .get("body")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let remote = parse_semver(&tag)?;
    if remote > current {
        Some(UpdateInfo {
            version: tag.trim_start_matches('v').to_string(),
            url,
            body,
        })
    } else {
        None
    }
}

#[tauri::command]
fn open_example(app: AppHandle) -> Result<(), String> {
    let path = app
        .path()
        .resolve("examples/loomings.md", BaseDirectory::Resource)
        .map_err(|e| e.to_string())?;
    let content = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    app.emit(
        "file-opened",
        FileOpenedPayload {
            path: path.to_string_lossy().to_string(),
            content,
        },
    )
    .map_err(|e| e.to_string())
}

#[tauri::command]
fn unwatch_file(state: State<AppState>) -> Result<(), String> {
    *state.watcher.lock().unwrap() = None;
    *state.watched_path.lock().unwrap() = None;
    Ok(())
}

#[tauri::command]
async fn open_file_dialog(app: AppHandle) -> Result<Option<FileOpenedPayload>, String> {
    let (tx, rx) = tokio::sync::oneshot::channel();
    app.dialog()
        .file()
        .add_filter("Markdown", &["md", "markdown", "txt"])
        .add_filter("All Files", &["*"])
        .set_title("Open Markdown File")
        .pick_file(move |path| {
            let _ = tx.send(path);
        });
    let result = rx.await.map_err(|e| e.to_string())?;
    match result {
        Some(p) => {
            let path_str = p
                .into_path()
                .map_err(|e| e.to_string())?
                .to_string_lossy()
                .to_string();
            let content = fs::read_to_string(&path_str).map_err(|e| e.to_string())?;
            Ok(Some(FileOpenedPayload {
                path: path_str,
                content,
            }))
        }
        None => Ok(None),
    }
}

fn open_recent_file(app: &AppHandle, path: String) {
    match fs::read_to_string(&path) {
        Ok(content) => {
            let _ = app.emit("file-opened", FileOpenedPayload { path, content });
        }
        Err(_) => {
            let mut rec = get_recent_files(app.clone());
            rec.retain(|f| f != &path);
            if let Ok(json) = serde_json::to_string(&rec) {
                let _ = fs::write(recent_path(app), json);
                let _ = build_menu(app);
            }
        }
    }
}

fn build_menu(app: &AppHandle) -> tauri::Result<()> {
    let new_item = MenuItemBuilder::new("New")
        .id("file-new")
        .accelerator("CmdOrCtrl+N")
        .build(app)?;
    let open_item = MenuItemBuilder::new("Open...")
        .id("file-open")
        .accelerator("CmdOrCtrl+O")
        .build(app)?;

    let recent_submenu = build_recent_submenu(app)?;

    let save_item = MenuItemBuilder::new("Save")
        .id("file-save")
        .accelerator("CmdOrCtrl+S")
        .build(app)?;
    let save_as_item = MenuItemBuilder::new("Save As...")
        .id("file-save-as")
        .accelerator("CmdOrCtrl+Shift+S")
        .build(app)?;
    let close_item = MenuItemBuilder::new("Close Window")
        .id("file-close")
        .accelerator("CmdOrCtrl+W")
        .build(app)?;

    let sep1 = PredefinedMenuItem::separator(app)?;
    let sep2 = PredefinedMenuItem::separator(app)?;
    let sep3 = PredefinedMenuItem::separator(app)?;
    let sep4 = PredefinedMenuItem::separator(app)?;
    let sep5 = PredefinedMenuItem::separator(app)?;
    let sep6 = PredefinedMenuItem::separator(app)?;
    let sep7 = PredefinedMenuItem::separator(app)?;
    let sep8 = PredefinedMenuItem::separator(app)?;

    #[allow(unused_mut)]
    let mut file_items: Vec<&dyn tauri::menu::IsMenuItem<tauri::Wry>> = vec![
        &new_item,
        &open_item,
        &recent_submenu,
        &sep1,
        &save_item,
        &save_as_item,
        &sep2,
        &close_item,
    ];

    #[cfg(not(target_os = "macos"))]
    let win_quit_item = MenuItemBuilder::new("Quit Loomings")
        .id("app-quit-menu")
        .accelerator("CmdOrCtrl+Q")
        .build(app)?;
    #[cfg(not(target_os = "macos"))]
    file_items.push(&win_quit_item);

    let file_menu = SubmenuBuilder::new(app, "File")
        .items(&file_items)
        .build()?;

    let edit_menu = SubmenuBuilder::new(app, "Edit")
        .undo()
        .redo()
        .separator()
        .cut()
        .copy()
        .paste()
        .select_all()
        .build()?;

    let toggle_focus = MenuItemBuilder::new("Toggle Focus Mode")
        .id("toggle-focus")
        .accelerator("CmdOrCtrl+Shift+D")
        .build(app)?;
    let toggle_preview = MenuItemBuilder::new("Toggle Preview")
        .id("toggle-preview")
        .accelerator("CmdOrCtrl+Shift+P")
        .build(app)?;
    let toggle_stats = MenuItemBuilder::new("Toggle Stats")
        .id("toggle-stats")
        .accelerator("CmdOrCtrl+Shift+L")
        .build(app)?;
    let toggle_width = MenuItemBuilder::new("Cycle Column Width")
        .id("toggle-width")
        .accelerator("CmdOrCtrl+Shift+W")
        .build(app)?;
    let font_inc = MenuItemBuilder::new("Increase Font Size")
        .id("font-inc")
        .accelerator("CmdOrCtrl+=")
        .build(app)?;
    let font_dec = MenuItemBuilder::new("Decrease Font Size")
        .id("font-dec")
        .accelerator("CmdOrCtrl+-")
        .build(app)?;
    let toggle_theme = MenuItemBuilder::new("Cycle Theme")
        .id("toggle-theme")
        .accelerator("CmdOrCtrl+Shift+T")
        .build(app)?;
    let cycle_goal = MenuItemBuilder::new("Cycle Word Goal")
        .id("cycle-goal")
        .accelerator("CmdOrCtrl+Shift+G")
        .build(app)?;
    let toggle_typo = MenuItemBuilder::new("Smart Typography")
        .id("toggle-typo")
        .build(app)?;
    let open_palette = MenuItemBuilder::new("Jump to Heading...")
        .id("open-palette")
        .accelerator("CmdOrCtrl+P")
        .build(app)?;
    let toggle_fs = MenuItemBuilder::new("Toggle Fullscreen")
        .id("toggle-fullscreen")
        .accelerator("F11")
        .build(app)?;
    let devtools = MenuItemBuilder::new("Toggle Developer Tools")
        .id("toggle-devtools")
        .accelerator("CmdOrCtrl+Alt+I")
        .build(app)?;

    let view_menu = SubmenuBuilder::new(app, "View")
        .items(&[
            &toggle_focus,
            &toggle_preview,
            &sep3,
            &toggle_stats,
            &toggle_width,
            &toggle_theme,
            &cycle_goal,
            &toggle_typo,
            &open_palette,
            &sep4,
            &font_inc,
            &font_dec,
            &sep5,
            &toggle_fs,
            &sep6,
            &devtools,
        ])
        .build()?;

    let help_about = MenuItemBuilder::new("About Loomings")
        .id("help-about")
        .build(app)?;
    let help_example = MenuItemBuilder::new("Open Example")
        .id("help-example")
        .build(app)?;
    let help_check_update = MenuItemBuilder::new("Check for Updates…")
        .id("help-check-update")
        .build(app)?;
    let help_website = MenuItemBuilder::new("Visit Website")
        .id("help-website")
        .build(app)?;
    let help_github = MenuItemBuilder::new("GitHub Repository")
        .id("help-github")
        .build(app)?;
    let help_sep1 = PredefinedMenuItem::separator(app)?;
    let help_sep2 = PredefinedMenuItem::separator(app)?;
    let help_sep3 = PredefinedMenuItem::separator(app)?;
    let help_menu = SubmenuBuilder::new(app, "Help")
        .items(&[
            &help_about,
            &help_sep1,
            &help_example,
            &help_sep2,
            &help_check_update,
            &help_sep3,
            &help_website,
            &help_github,
        ])
        .build()?;

    let mut menu_builder = MenuBuilder::new(app);

    #[cfg(target_os = "macos")]
    {
        let app_name = "Loomings";
        let about_meta = AboutMetadataBuilder::new()
            .name(Some(app_name.to_string()))
            .version(Some(env!("CARGO_PKG_VERSION").to_string()))
            .authors(Some(vec!["Tiago Jacinto".to_string()]))
            .license(Some("MIT".to_string()))
            .website(Some("https://tiagojct.eu/loomings".to_string()))
            .website_label(Some("tiagojct.eu/loomings".to_string()))
            .copyright(Some("© 2026 Tiago Jacinto".to_string()))
            .comments(Some("A markdown writing app. Built with Tauri 2 + CodeMirror 6.".to_string()))
            .build();
        let about = PredefinedMenuItem::about(app, Some(app_name), Some(about_meta))?;
        let services = PredefinedMenuItem::services(app, None)?;
        let hide = PredefinedMenuItem::hide(app, None)?;
        let hide_others = PredefinedMenuItem::hide_others(app, None)?;
        let show_all = PredefinedMenuItem::show_all(app, None)?;
        let app_quit_item = MenuItemBuilder::new("Quit Loomings")
            .id("app-quit-menu")
            .accelerator("CmdOrCtrl+Q")
            .build(app)?;
        let app_menu = SubmenuBuilder::new(app, app_name)
            .items(&[
                &about,
                &sep7,
                &services,
                &sep8,
                &hide,
                &hide_others,
                &show_all,
            ])
            .item(&PredefinedMenuItem::separator(app)?)
            .item(&app_quit_item)
            .build()?;
        menu_builder = menu_builder.item(&app_menu);
    }

    let menu = menu_builder
        .items(&[&file_menu, &edit_menu, &view_menu, &help_menu])
        .build()?;
    app.set_menu(menu)?;
    Ok(())
}

fn build_recent_submenu(app: &AppHandle) -> tauri::Result<tauri::menu::Submenu<tauri::Wry>> {
    let mut builder = SubmenuBuilder::new(app, "Open Recent").id("file-open-recent");
    let recents = get_recent_files(app.clone());
    if recents.is_empty() {
        let empty = MenuItemBuilder::new("(no recent files)")
            .id("recent-empty")
            .enabled(false)
            .build(app)?;
        builder = builder.item(&empty);
    } else {
        for (i, p) in recents.iter().enumerate() {
            let label = std::path::Path::new(p)
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| p.clone());
            let item = MenuItemBuilder::new(label)
                .id(format!("recent-{}", i))
                .build(app)?;
            builder = builder.item(&item);
        }
        let sep = PredefinedMenuItem::separator(app)?;
        let clear = MenuItemBuilder::new("Clear Recent")
            .id("recent-clear")
            .build(app)?;
        builder = builder.item(&sep).item(&clear);
    }
    builder.build()
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            save_file,
            save_file_as,
            get_recent_files,
            add_recent_file,
            set_title,
            save_scratch,
            read_scratch,
            clear_scratch,
            confirm_quit,
            cancel_quit_request,
            open_file_dialog,
            watch_file,
            unwatch_file,
            check_for_update,
            open_example
        ])
        .setup(|app| {
            build_menu(&app.handle())?;
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
            }
            Ok(())
        })
        .on_menu_event(|app, event| {
            let id = event.id().as_ref();
            let window = match app.get_webview_window("main") {
                Some(w) => w,
                None => return,
            };
            match id {
                "file-new"       => { let _ = app.emit("file-new", ()); }
                "file-open"      => {
                    let app_handle = app.clone();
                    tauri::async_runtime::spawn(async move {
                        if let Ok(Some(payload)) = open_file_dialog(app_handle.clone()).await {
                            let _ = app_handle.emit("file-opened", payload);
                        }
                    });
                }
                "file-save"      => { let _ = app.emit("request-save", ()); }
                "file-save-as"   => { let _ = app.emit("request-save-as", ()); }
                "file-close"     => { let _ = app.emit("request-close", ()); }
                "app-quit-menu"  => { let _ = app.emit("request-close", ()); }
                "toggle-focus"   => { let _ = app.emit("toggle-focus", ()); }
                "toggle-preview" => { let _ = app.emit("toggle-preview", ()); }
                "toggle-stats"   => { let _ = app.emit("toggle-stats", ()); }
                "toggle-width"   => { let _ = app.emit("toggle-width", ()); }
                "toggle-theme"   => { let _ = app.emit("toggle-theme", ()); }
                "cycle-goal"     => { let _ = app.emit("cycle-goal", ()); }
                "toggle-typo"    => { let _ = app.emit("toggle-typo", ()); }
                "open-palette"   => { let _ = app.emit("open-palette", ()); }
                "help-about"     => { let _ = app.emit("open-about", ()); }
                "help-example"   => {
                    let app_handle = app.clone();
                    tauri::async_runtime::spawn(async move {
                        let _ = open_example(app_handle);
                    });
                }
                "help-check-update" => { let _ = app.emit("manual-update-check", ()); }
                "help-website"   => { let _ = app.emit("open-url", "https://tiagojct.eu/loomings"); }
                "help-github"    => { let _ = app.emit("open-url", "https://github.com/tiagojct/loomings"); }
                "font-inc"       => { let _ = app.emit("font-size", 1i32); }
                "font-dec"       => { let _ = app.emit("font-size", -1i32); }
                "toggle-fullscreen" => {
                    if let Ok(is_fs) = window.is_fullscreen() {
                        let _ = window.set_fullscreen(!is_fs);
                    }
                }
                "toggle-devtools" => {
                    #[cfg(debug_assertions)]
                    {
                        if window.is_devtools_open() {
                            window.close_devtools();
                        } else {
                            window.open_devtools();
                        }
                    }
                }
                "recent-clear" => {
                    let _ = fs::write(recent_path(app), "[]");
                    let _ = build_menu(app);
                }
                s if s.starts_with("recent-") => {
                    if let Ok(idx) = s.trim_start_matches("recent-").parse::<usize>() {
                        let recents = get_recent_files(app.clone());
                        if let Some(path) = recents.get(idx) {
                            open_recent_file(app, path.clone());
                        }
                    }
                }
                _ => {}
            }
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                let state = window.state::<AppState>();
                let now = Instant::now();
                {
                    let mut last = state.last_close_request.lock().unwrap();
                    if let Some(prev) = *last {
                        if now.duration_since(prev) <= Duration::from_secs(2) {
                            *last = None;
                            return;
                        }
                    }
                    *last = Some(now);
                }

                api.prevent_close();
                let _ = window.app_handle().emit("request-close", ());
            }
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            if let tauri::RunEvent::ExitRequested { .. } | tauri::RunEvent::Exit = event {
                let p = scratch_path(app_handle);
                if p.exists() {
                    let _ = fs::remove_file(p);
                }
            }
        });
}
