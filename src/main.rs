use std::{
    fs,
    io,
    path::{Path, PathBuf},
};

use crossterm::{
    event::{self, Event, KeyCode, KeyEvent},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};

use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Span, Line},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    Terminal,
};

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
    fn render(f: &mut ratatui::Frame, area: ratatui::layout::Rect, entry: Option<&FileEntry>) {
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
            Line::from(Span::styled(
                name,
                Style::default().add_modifier(Modifier::BOLD),
            )),
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
        area: ratatui::layout::Rect,
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
    fn read_dir(path: &Path) -> Vec<FileEntry> {
        let mut result = Vec::new();
        if let Ok(read) = fs::read_dir(path) {
            for e in read.flatten() {
                let name = e.file_name().to_string_lossy().to_string();
                let is_dir = e.path().is_dir();
                result.push(FileEntry { name, is_dir });
            }
        }
        result
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
// DirectoryController（Path + FS + DirManager を束ねる頭脳）
//////////////////////////////////////////////////////
struct DirectoryController {
    path_mgr: PathManager,
    dir_mgr: DirStateManager,
    fs: FileSystemService,
}

impl DirectoryController {
    fn new(path: PathBuf) -> Self {
        let mut s = Self {
            path_mgr: PathManager::new(path),
            dir_mgr: DirStateManager::new(),
            fs: FileSystemService,
        };
        s.reload();
        s
    }

    fn reload(&mut self) {
        let entries = FileSystemService::read_dir(self.path_mgr.current());
        self.dir_mgr.set_entries(entries);
    }

    fn enter_dir(&mut self, name: &str) {
        self.path_mgr.enter_child(name);
        self.reload();
    }

    fn go_parent(&mut self) {
        if self.path_mgr.go_parent() {
            self.reload();
        }
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

    fn page_size(height: u16) -> usize {
        height.saturating_sub(3) as usize // FileInfo + StatusLine 分引く
    }

    fn adjust(&mut self, page: usize, total: usize) {
        if self.cursor < self.scroll {
            self.scroll = self.cursor;
        }
        let bottom = self.scroll + page - 1;
        if self.cursor > bottom {
            self.scroll = self.cursor - (page - 1);
        }
        if self.cursor >= total && total > 0 {
            self.cursor = total - 1;
        }
    }

    fn relative(&self) -> Option<usize> {
        self.cursor.checked_sub(self.scroll)
    }
}

//////////////////////////////////////////////////////
// EntryFormatter（ファイル一覧の1行変換）
//////////////////////////////////////////////////////
struct EntryFormatter;
impl EntryFormatter {
    fn format_entry(e: &FileEntry) -> ListItem<'static> {
        let formatted_file_info = if e.is_dir { format!("{}/", e.name) } else { e.name.clone() };
        ListItem::new(Span::raw(formatted_file_info))
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
        ui: &UIState,
        page: usize,
    ) {
        let size = f.size();

        // 縦方向に 3 分割
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),     // FileInfoView
                Constraint::Min(5),        // FileListView
                Constraint::Length(1),     // StatusLine
            ])
            .split(size);

        // ---- FileInfoView ----
        let current = ctl.entry_at(ui.cursor);
        FileInfoView::render(f, chunks[0], current);

        // ---- FileListView ----
        let entries = ctl.range(ui.scroll, page);
        let items: Vec<ListItem> = entries.iter().map(EntryFormatter::format_entry).collect();

        let mut state = ListState::default();
        if let Some(rel) = ui.relative() {
            state.select(Some(rel.min(items.len().saturating_sub(1))));
        }

        let list = List::new(items)
            .highlight_symbol("> ")
            .highlight_style(
                Style::default()
                    .bg(Color::White)
                    .fg(Color::Black)
                    .add_modifier(Modifier::BOLD),
            )
            .block(Block::default().title("Files").borders(Borders::ALL));

        f.render_stateful_widget(list, chunks[1], &mut state);

        // ---- StatusLine ----
        StatusLineView::render(f, chunks[2], ctl);
    }
}

//////////////////////////////////////////////////////
// 入力 → コマンド変換
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
            KeyCode::Up => Command::Up,
            KeyCode::Down => Command::Down,
            KeyCode::Enter => Command::Enter,
            KeyCode::Backspace => Command::Back,
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
        page: usize,
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
                        ctl.enter_dir(&name);
                        ui.cursor = 0;
                        ui.scroll = 0;
                    }
                }
            }
            Command::Back => {
                ctl.go_parent();
                ui.cursor = 0;
                ui.scroll = 0;
            }
            Command::Quit => return false,
            Command::None => {}
        }

        ui.adjust(page, ctl.len());
        true
    }
}

//////////////////////////////////////////////////////
// MAIN
//////////////////////////////////////////////////////
fn main() -> Result<(), Box<dyn std::error::Error>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut ctl = DirectoryController::new(PathBuf::from("."));
    let mut ui = UIState::new();

    loop {
        terminal.draw(|f| {
            let size = f.size();
            let page = UIState::page_size(size.height).max(1);
            Renderer::render(f, &ctl, &ui, page);
        })?;

        if let Event::Key(key) = event::read()? {
            let cmd = InputHandler::map(key);
            let page = UIState::page_size(terminal.size()?.height).max(1);
            if !CommandExecutor::exec(cmd, &mut ctl, &mut ui, page) {
                break;
            }
        }
    }

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    Ok(())
}