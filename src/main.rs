use std::{
    fs,
    io::{self, Stdout},
    path::{Path, PathBuf},
};

use crossterm::{
    event::{self, Event, KeyCode, KeyEvent},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};

use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Span, Line},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    Terminal,
};

//////////////////////////////////////////////////////
// TerminalGuard (Stdout を保持し、ドロップ時に復旧)
//////////////////////////////////////////////////////
struct TerminalGuard {
    stdout: Stdout,
}

impl TerminalGuard {
    fn init() -> Result<Self, Box<dyn std::error::Error>> {
        let mut stdout = io::stdout();
        enable_raw_mode()?;
        execute!(stdout, EnterAlternateScreen)?;
        Ok(TerminalGuard { stdout })
    }

    fn terminal(&mut self) -> io::Result<Terminal<CrosstermBackend<&mut Stdout>>> {
        let backend = CrosstermBackend::new(&mut self.stdout);
        Terminal::new(backend)
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(self.stdout, LeaveAlternateScreen);
    }
}

//////////////////////////////////////////////////////
// FileEntry（純粋なデータ保持構造）
//////////////////////////////////////////////////////
#[derive(Clone)]
struct FileEntry {
    name: String,
    is_dir: bool,
}

//////////////////////////////////////////////////////
// FileInfoView（選択中ファイルを2行表示）
//////////////////////////////////////////////////////
struct FileInfoView;
impl FileInfoView {
    fn render(f: &mut ratatui::Frame, area: Rect, entry: Option<&FileEntry>) {
        let (name, meta) = match entry {
            Some(e) => {
                let name = if e.is_dir {
                    format!("{}/", e.name)
                } else {
                    e.name.clone()
                };

                let size_or_dir = if e.is_dir {
                    "<DIR>".to_string()
                } else {
                    "bytes not loaded".to_string() // 今はまだサイズ取得していない
                };

                let meta = format!("{}   (metadata TBD)", size_or_dir);
                (name, meta)
            }
            None => ("(no file)".to_string(), "".to_string()),
        };

        let text = vec![
            Line::from(
                Span::styled(
                    name,
                    Style::default().add_modifier(Modifier::BOLD)
                )
            ),
            Line::from(Span::raw(meta)),
        ];

        let para = Paragraph::new(text).block(
            Block::default().title(" File Info ").borders(Borders::ALL),
        );

        f.render_widget(para, area);
    }
}

//////////////////////////////////////////////////////
// StatusLineView（末尾パス + 件数）
//////////////////////////////////////////////////////
struct StatusLineView;

impl StatusLineView {
    fn short_path(path: &Path, levels: usize) -> String {
        let comps: Vec<_> = path.components().collect();
        let len = comps.len();
        let start = len.saturating_sub(levels);
        let slice = &comps[start..len];

        let mut s = String::new();
        if start > 0 {
            s.push_str(".../");
        }

        s.push_str(
            &slice
                .iter()
                .map(|c| c.as_os_str().to_string_lossy())
                .collect::<Vec<_>>()
                .join("/"),
        );
        s
    }

    fn render(
        f: &mut ratatui::Frame,
        area: Rect,
        ctl: &DirectoryController,
    ) {
        let short = Self::short_path(ctl.current_path(), 3);
        let msg = format!(" {}   {} entries", short, ctl.len());

        let para = Paragraph::new(Line::from(msg))
            .block(Block::default().borders(Borders::ALL));

        f.render_widget(para, area);
    }
}

//////////////////////////////////////////////////////
// DirState（データ保持専用）
//////////////////////////////////////////////////////
struct DirState {
    entries: Vec<FileEntry>,
}

impl DirState {
    fn new() -> Self {
        Self { entries: Vec::new() }
    }
}

//////////////////////////////////////////////////////
// PathManager（パス操作専用）
//////////////////////////////////////////////////////
struct PathManager {
    current: PathBuf,
}

impl PathManager {
    fn new(path: PathBuf) -> Self {
        Self { current: path }
    }

    fn current(&self) -> &Path {
        &self.current
    }

    fn enter_child(&mut self, name: &str) {
        self.current.push(name);
    }

    fn go_parent(&mut self) -> bool {
        if self.current.parent().is_some() {
            self.current.pop();
            return true;
        }
        false
    }
}

//////////////////////////////////////////////////////
// FileSystemService（OS からのファイル取得専用）
//////////////////////////////////////////////////////
struct FileSystemService;

impl FileSystemService {
    fn read_dir(path: &Path) -> io::Result<Vec<FileEntry>> {
        let mut result = Vec::new();
        for e in fs::read_dir(path)?.flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            let is_dir = e.path().is_dir();
            result.push(FileEntry { name, is_dir });
        }
        Ok(result)
    }
}

//////////////////////////////////////////////////////
// DirStateManager（entries の整列/抽出専用）
//////////////////////////////////////////////////////
struct DirStateManager {
    state: DirState,
}

impl DirStateManager {
    fn new() -> Self {
        Self { state: DirState::new() }
    }

    fn set_entries(&mut self, entries: Vec<FileEntry>) {
        self.state.entries = entries;
        self.sort_by_name();
    }

    fn sort_by_name(&mut self) {
        self.state
            .entries
            .sort_by_key(|e| e.name.to_lowercase());
    }

    fn len(&self) -> usize {
        self.state.entries.len()
    }

    fn entry_at(&self, idx: usize) -> Option<&FileEntry> {
        self.state.entries.get(idx)
    }

    fn range(&self, start: usize, count: usize) -> &[FileEntry] {
        let s = start.min(self.state.entries.len());
        let e = (s + count).min(self.state.entries.len());
        &self.state.entries[s..e]
    }
}

//////////////////////////////////////////////////////
// DirectoryController（Path + FS + DirManager を束ねる）
//////////////////////////////////////////////////////
struct DirectoryController {
    path_mgr: PathManager,
    dir_mgr: DirStateManager,
}
impl DirectoryController {
    fn new(path: PathBuf) -> io::Result<Self> {
        let mut s = Self {
            path_mgr: PathManager::new(path),
            dir_mgr: DirStateManager::new()
        };
        s.reload()?;
        Ok(s)
    }

    fn reload(&mut self) -> io::Result<()> {
        let entries = FileSystemService::read_dir(self.path_mgr.current())?;
        self.dir_mgr.set_entries(entries);
        Ok(())
    }

    fn enter_dir(&mut self, name: &str) -> io::Result<()> {
        self.path_mgr.enter_child(name);
        self.reload()
    }

    fn go_parent(&mut self) -> io::Result<()> {
        if self.path_mgr.go_parent() {
            self.reload()?;
        }
        Ok(())
    }

    fn current_path(&self) -> &Path {
        self.path_mgr.current()
    }

    fn len(&self) -> usize {
        self.dir_mgr.len()
    }

    fn entry_at(&self, idx: usize) -> Option<&FileEntry> {
        self.dir_mgr.entry_at(idx)
    }

    fn range(&self, start: usize, count: usize) -> &[FileEntry] {
        self.dir_mgr.range(start, count)
    }
}

//////////////////////////////////////////////////////
// UIState（カーソル・スクロール位置）
//////////////////////////////////////////////////////
struct UIState {
    cursor: usize,
    scroll: usize,
}

impl UIState {
    fn new() -> Self {
        Self { cursor: 0, scroll: 0 }
    }

    fn adjust(&mut self, page: usize, total: usize) {
        if total == 0 {
            self.cursor = 0;
            self.scroll = 0;
            return;
        }
        self.cursor = self.cursor.min(total.saturating_sub(1));

        let bottom = self.scroll + page;
        if self.cursor < self.scroll {
            self.scroll = self.cursor;
        } else if page > 0 && self.cursor >= bottom {
            self.scroll = self.cursor - page + 1;
        }
    }

    fn relative(&self) -> usize {
        self.cursor.saturating_sub(self.scroll)
    }
}

//////////////////////////////////////////////////////
// EntryFormatter（ファイル一覧の1行変換）
//////////////////////////////////////////////////////
struct EntryFormatter;
impl EntryFormatter {
    fn format_entry(e: &FileEntry) -> ListItem<'static> {
        let formatted_file_info = if e.is_dir { format!("{}/", e.name) } else { e.name.clone() };
        ListItem::new(formatted_file_info)
    }
}

//////////////////////////////////////////////////////
// Renderer（画面を縦分割し FileInfo → List → StatusLine）
//////////////////////////////////////////////////////
struct Renderer;

impl Renderer {
    fn render(
        f: &mut ratatui::Frame,
        ctl: &DirectoryController,
        ui: &UIState
    ) -> usize {

        // 縦方向に 3 分割
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),      // FileInfoView
                Constraint::Min(1),         // FileListView
                Constraint::Length(3),      // StatusLine
            ]).split(f.size());

        let list_area = chunks[1];

        let list_block = Block::default().title(" Files ").borders(Borders::ALL);
        let list_inner = list_block.inner(list_area);
        let page = list_inner.height as usize;

        // ---- FileInfoView ----
        let current = ctl.entry_at(ui.cursor);
        FileInfoView::render(f, chunks[0], current);

        // ---- FileListView ----
        let entries = ctl.range(ui.scroll, page);
        let items: Vec<ListItem> = entries
            .iter()
            .map(EntryFormatter::format_entry)
            .collect();
        let mut state = ListState::default();

        if !items.is_empty() {
            let rel = ui.relative();
            state.select(Some(rel.min(items.len() - 1)));
        }

        let list = List::new(items)
            .highlight_symbol("> ")
            .highlight_style(
                Style::default()
                    .bg(Color::White)
                    .fg(Color::Black)
                    .add_modifier(Modifier::BOLD),
            );

        // block は outer に描画
        f.render_widget(list_block, list_area);
        // list は inner に描画
        f.render_stateful_widget(list, list_inner, &mut state);

        // ---- StatusLine ----
        StatusLineView::render(f, chunks[2], ctl);

        page
    }
}

//////////////////////////////////////////////////////
// InputHandler (入力 → コマンド変換)
//////////////////////////////////////////////////////
enum Command {
    Up,
    Down,
    Enter,
    Back,
    Quit,
    None,
}

struct InputHandler;
impl InputHandler {
    fn map(ev: KeyEvent) -> Command {
        match ev.code {
            KeyCode::Up | KeyCode::Char('k') => Command::Up,
            KeyCode::Down | KeyCode::Char('j') => Command::Down,
            KeyCode::Enter | KeyCode::Right | KeyCode::Char('l') => Command::Enter,
            KeyCode::Backspace | KeyCode::Left | KeyCode::Char('h') => Command::Back,
            KeyCode::Char('q') => Command::Quit,
            _ => Command::None,
        }
    }
}

//////////////////////////////////////////////////////
// CommandExecutor（Command を ctl + ui に適用）
//////////////////////////////////////////////////////
struct CommandExecutor;
impl CommandExecutor {
    fn exec(
        cmd: Command,
        ctl: &mut DirectoryController,
        ui: &mut UIState,
        page: usize
    ) -> bool {
        match cmd {
            Command::Up => {
                if ui.cursor > 0 {
                    ui.cursor -= 1;
                }
            }
            Command::Down => {
                if ui.cursor + 1 < ctl.len() {
                    ui.cursor += 1;
                }
            }
            Command::Enter => {
                if let Some(e) = ctl.entry_at(ui.cursor) {
                    if e.is_dir {
                        let name = e.name.clone();
                        if ctl.enter_dir(&name).is_ok() {
                            ui.cursor = 0;
                            ui.scroll = 0;
                        }
                    }
                }
            }
            Command::Back => {
                if ctl.go_parent().is_ok() {
                    ui.cursor = 0;
                    ui.scroll = 0;
                }
            }
            Command::Quit => return false,
            _ => {}
        }

        ui.adjust(page, ctl.len());
        true
    }
}

//////////////////////////////////////////////////////
// Main
//////////////////////////////////////////////////////
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut guard = TerminalGuard::init()?;
    let mut terminal = guard.terminal()?;

    let mut ctl = DirectoryController::new(PathBuf::from("."))?;
    let mut ui = UIState::new();
    let mut last_page = 1;

    loop {
        terminal.draw(|f| {
            last_page = Renderer::render(f, &ctl, &ui);
        })?;

        if let Event::Key(key) = event::read()? {
            if !CommandExecutor::exec(InputHandler::map(key), &mut ctl, &mut ui, last_page) {
                break;
            }
        }
    }
    Ok(())
}