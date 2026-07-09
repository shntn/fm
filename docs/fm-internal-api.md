# fm.lua 内部API

`lua/fm.lua` は「状態」「ディレクトリナビゲーション」「コマンド登録」「コールバック」の
4つの塊に分かれている。画面描画そのものは`lua/list_screen.lua`（`ListScreen`）に、
コマンドの実行入口は`lua/invoker.lua`（`Invoker`）に、コマンドの実装本体は
`lua/commands.lua`（`Commands`）に分離されている。
このドキュメントは、これらの境界を跨ぐ最小限の契約を定義する。
各塊の内部だけで完結する関数（`find_index_by_name`, `join_path` など）は対象外。

設計の背景・検討過程は`docs/fm-screen-architecture.md`・
`docs/fm-mode-interface-design.md`・`docs/fm-interface-design.md`を参照。

## 状態

`fm.lua`が保持する`state`テーブル。ナビゲーション層・コマンド定義層が書き込み、
`ListScreen:view`が読み取る。

```lua
local state = {
    display = { width = 0, height = 0 },
    panes = {
        { cwd = "...", cursor = 1, show_hidden = true, search_query = "", all_files = {}, files = {} },
    },
    active_pane = 1,
    message = "",
}
```

| フィールド | 型 | 内容 |
|---|---|---|
| `state.display` | table | `screen.get_size()`の結果。`draw()`が毎回更新する |
| `state.panes` | table | ペインごとの状態の配列。現状は単一ペインのみ対応のため要素は常に1つ |
| `state.panes[N].cwd` | string | そのペインのカレントディレクトリの絶対パス |
| `state.panes[N].cursor` | number | カーソル位置（`files`の1始まりインデックス） |
| `state.panes[N].show_hidden` | boolean | 隠しファイル（`.`始まりの名前。`..`自体は対象外）を表示するか。既定は`true` |
| `state.panes[N].search_query` | string | 検索文字列。空文字なら絞り込みなし。ディレクトリ移動時に空文字へリセットされる |
| `state.panes[N].all_files` | table | `fs.list`の戻り値の先頭に`..`エントリを加えた、フィルタ適用前の生の一覧 |
| `state.panes[N].files` | table | `all_files`に`show_hidden`・`search_query`のフィルタを適用した一覧。`ListScreen:view`とカーソル移動系コマンドはこちらを見る |
| `state.active_pane` | number | 操作対象のペイン（`state.panes`のインデックス） |
| `state.message` | string | エラー・通知メッセージ。空文字でなければ`ListScreen:view`がフッター行に通常のヘルプの代わりに表示する |

`refresh_files(pane)`（`fm.lua`内部関数）が`pane.all_files`から`pane.files`を
再構築する（`show_hidden`・`search_query`の両方のフィルタを適用。`".."`はどちらの
対象にもならず常に含まれる）。`pane.cursor`が新しい`pane.files`の範囲外になった
場合は末尾に補正する。ディレクトリ読み込み時・`toggle_hidden`実行時・検索確定時に
呼ばれる。

`current_pane()`（`fm.lua`内部関数）が`state.panes[state.active_pane]`を返す。
ナビゲーション層・コマンド定義層はこれを経由して状態を読み書きする。

## 画面描画・スクリーン管理

`fm.lua`は「今アクティブなスクリーンはどれか」をモジュールレベルのローカル変数
（`current_screen`）で保持する。`get_current_screen()`/`set_current_screen(screen_instance)`
（`fm.lua`内部関数）を経由してのみ読み書きする。

- `draw()`・`on_key`は、固定の`ListScreen`インスタンスではなく`get_current_screen()`が
  返すインスタンスの`view`/`command_mapper`を呼ぶ
- スクリーンを切り替えるコマンド（`confirm_delete`/`delete`/`cancel`/`toggle_layout`）は、
  `Invoker.commands`内から`set_current_screen`を呼ぶ
- 切り替えは呼ばれた直後の`draw()`から有効になる（次の`on_key`呼び出しを待つ必要はない）

### `ListScreen`（`lua/list_screen.lua`）

`lua/screen.lua`の`Screen`を継承する、ファイル一覧表示のスクリーン。起動直後の
既定のアクティブスクリーンでもある。

### `ListScreen:view(data)`

- 引数: `data`（`state`テーブルそのもの）
- 戻り値: なし
- 動作: `data.active_pane`が指すペインのファイル一覧を描画する。カーソル行は
  反転表示のエスケープシーケンス（`\27[7m` / `\27[0m`）で行全体を囲む
- 呼び出し元: `fm.lua`の`draw()`

### `ListScreen:command_mapper(key)` → command_name, args

- 引数: `key`（キー名）
- 戻り値: `command_name`（実行すべきコマンド名の文字列。対応するキーがなければ`nil`）, `args`（今は常に`nil`）
- キー対応: `j`/`down` → `"cursor_down"`, `k`/`up` → `"cursor_up"`, `enter` → `"open_selected"`, `backspace` → `"go_to_parent"`, `.` → `"toggle_hidden"`, `d` → `"confirm_delete"`, `v` → `"toggle_layout"`, `/` → `"search"`, `q`/`escape` → `"quit"`

`"quit"`と`"search"`は`Invoker`を経由せず、`fm.lua`の`on_key`が直接検知する
特別なコマンド名。`"quit"`は`false`を返してメインループを終了させる。`"search"`は
行入力モードへの切り替えをリクエストする（詳細は「検索（行入力モード）」を参照）。

### `GridScreen`（`lua/grid_screen.lua`）

`ListScreen`を継承する、ファイル一覧を2段組で表示するスクリーン。
`command_mapper`は上書きせず`ListScreen`のものをそのまま使う（カーソル移動・
削除・隠しファイル切替などのキー操作は表示レイアウトに依存しないため）。
`view`のみ上書きし、名前だけを2列（`COLUMNS_WIDTH`幅ずつ）に並べて表示する。
パーミッション・サイズ・更新日時は表示しない。ページングは行わない
（`list_h × 2`件を超えるファイルは表示されない）。

### `ConfirmDeleteScreen`（`lua/confirm_delete_screen.lua`）

`Screen`を継承する、削除確認ダイアログのスクリーン。`fm-interface-design.md`の
「確認ダイアログの実現方法（ブロッキングループを使わない）」で設計した通り、
ブロッキングループではなくスクリーン切り替えで実現している。

#### `ConfirmDeleteScreen.new(target, previous_screen)` → instance

- 引数: `target`（削除対象のファイルエントリ。`files`の要素）, `previous_screen`
  （呼び出し元のスクリーンのインスタンス。`ListScreen`または`GridScreen`）
- `previous_screen`は、下敷きの描画（`view`）と、`y`/`n`後の復帰先の両方に使われる。
  これにより、`GridScreen`表示中に削除確認を開いても、キャンセル・削除後に
  `ListScreen`へ戻ってしまうことなく、元の表示のまま維持される

#### `ConfirmDeleteScreen:view(data)`

- 動作: `previous_screen:view(data)`で下敷きを描画した上で、フッター行に
  `"<target.name>" を削除しますか？ (y/n)`を画面幅いっぱいにパディングして
  重ねて表示する（下敷きのフッター文字列の残骸が残らないようにするため）

#### `ConfirmDeleteScreen:command_mapper(key)` → command_name, args

- キー対応: `y` → `"delete"`（`args = { target = target, previous_screen = previous_screen }`）,
  `n`/`escape` → `"cancel"`（`args = { previous_screen = previous_screen }`）

## コマンド登録（`lua/commands.lua`）

コマンドの実装本体は`lua/commands.lua`の`Commands`モジュールに分離されている。
`fm.lua`は状態・ナビゲーション関数・スクリーンインスタンスなどをまとめた`ctx`
テーブルを組み立て、`Commands.register(ctx)`を1回呼ぶことで、`lua/invoker.lua`が
提供する`Invoker.commands`（コマンド名→実行関数のテーブル）にすべて登録される。

`commands.lua`は`fm.lua`のローカル変数に直接アクセスできない（別ファイルのため）
ので、必要な依存はすべて`ctx`引数で受け取る。`ctx`の内容は以下の通り。

| キー | 内容 |
|---|---|
| `state` | 状態テーブル（`state.message`の書き換えに使う） |
| `current_pane` | 操作対象のペインを返す関数 |
| `refresh_files` | `pane.all_files`から`pane.files`を再構築する関数 |
| `enter_directory` | ディレクトリ移動関数 |
| `go_to_parent` | 親ディレクトリへ移動する関数 |
| `join_path` | パス結合関数 |
| `shell_quote` | シェルクォート関数 |
| `open_file` | デフォルトのファイルを開く関数 |
| `open_with_command` | 拡張子対応コマンドでファイルを開く関数 |
| `file_extension` | 拡張子取得関数 |
| `ASSOCIATIONS` | 拡張子ごとのコマンド定義 |
| `get_current_screen` / `set_current_screen` | アクティブなスクリーンの参照・切り替え関数 |
| `list_screen` / `grid_screen` | `ListScreen`/`GridScreen`のインスタンス |
| `ConfirmDeleteScreen` | `ConfirmDeleteScreen`モジュール |

登録されるコマンドは以下の通り。いずれも`state`（`ctx`経由）を直接書き換える。

| コマンド名 | 動作 |
|---|---|
| `cursor_down` | `cursor`を1つ進める（末尾では何もしない） |
| `cursor_up` | `cursor`を1つ戻す（先頭では何もしない） |
| `go_to_parent` | 親ディレクトリへ移動する。戻る前にいたディレクトリの位置にカーソルを合わせる |
| `open_selected` | カーソル位置がディレクトリなら、そこに移動する（`..`の場合は`go_to_parent`相当）。ファイルなら、拡張子に対応するコマンド（`ASSOCIATIONS`）が定義されていればそれを、なければ`open_file`でファイルを開く |
| `toggle_hidden` | `show_hidden`を反転し、`refresh_files`で`files`を再構築する |
| `confirm_delete` | カーソル位置の要素（`".."`は対象外）について、現在のスクリーンを`previous_screen`として渡し`ConfirmDeleteScreen`へ切り替える |
| `delete` | `args.target`を`fs.run("rm ...")`（ディレクトリは`rm -r`）で削除する。成功時は`state.message`を空にしてディレクトリを再読み込みし、失敗時はエラーメッセージを`state.message`にセットする。いずれの場合も`args.previous_screen`へ戻す |
| `cancel` | 何もせず`args.previous_screen`へ戻す |
| `toggle_layout` | `ListScreen`と`GridScreen`を切り替える |
| `search` | `args.query`を`pane.search_query`にセットし、`refresh_files`で`files`を再構築する |

### `open_file(cwd, f)` (内部関数)

カーソル位置のファイルを`fs.run`経由で外部コマンドで開く。拡張子に対応する
コマンドが`ASSOCIATIONS`にない場合のデフォルト動作。

- 引数: `cwd`（ファイルのあるディレクトリ）, `f`（`files`の要素。`name`と`size`を使う）
- 戻り値: なし
- 判定: `size == 0`、または`grep -Iq ''`の終了コードが`0`ならテキストファイルとみなし`less`で開く。それ以外は`xxd | less`でダンプを表示する
- ファイル名はシェルクォートしてから`fs.run`に渡す

### `ASSOCIATIONS`（拡張子ごとのコマンド定義）

拡張子をキーとし、値をコマンドテンプレート文字列とする連想配列。`config.load().associations`（`lua/config.lua`）から取得する。設定ファイルが存在しない、または不正なTOMLの場合は`config.lua`に内蔵された既定値にフォールバックする。

- キー: 拡張子（`file_extension`が返す値。先頭がドットの隠しファイルで他にドットがない場合は拡張子なし扱いになりマッチしない）
- 値: コマンドテンプレート文字列。以下のプレースホルダを含められる
  - `$C`: カーソル位置のファイル名（拡張子あり）
  - `$X`: カーソル位置のファイル名（拡張子なし）
  - `$P`: カレントディレクトリのフルパス
- 各プレースホルダの値はシェルクォートしてから展開される
- 対応するエントリがない場合は`open_file`にフォールバックする

## 設定ファイル（`lua/config.lua`）

`config.load()`は、設定ファイルの内容（TOML）を`toml.parse`でパースしたテーブルを返す。

- 設定ファイルのパス: `FM_CONFIG`環境変数が設定されていればそのパス、なければ`$HOME/.config/fm/config.toml`
- ファイルが存在しない、または`toml.parse`が失敗するようなTOMLとして不正な内容の場合は、`config.lua`に文字列として内蔵された既定値（実際の設定ファイルと同じTOML形式）にフォールバックする
- 現状は`[associations]`セクション（`ASSOCIATIONS`）のみを定義しているが、今後セクションを追加する場合もこの既定値文字列とパース経路をそのまま使う

## コールバック（グローバルな`on_init`/`on_key`）

Rust側（`lua_bridge.rs`）が呼び出す唯一の入口。`fm-interface-design.md`の
「メインループとの対応」で定義した構造をそのまま実装している。

### `draw()`

- 引数: なし
- 戻り値: なし
- 動作: `screen.get_size()`で`state.display`を更新し、`screen.clear()`した上で`get_current_screen():view(state)`を呼ぶ
- 呼び出し元: `on_init`, `on_key`

### `on_key(key)`

1. `awaiting_search`（行入力の結果待ちかどうかを示すモジュールレベルの変数）が`true`
   なら、`key`は通常のキー名ではなく確定した検索文字列そのものとして扱う（詳細は
   「検索（行入力モード）」を参照）。処理後は`draw()`を呼び`true`を返す
2. `get_current_screen():command_mapper(key)`で`command_name`を決定する
3. `command_name == "quit"`なら`false`を返して終了（`Invoker`を経由しない）
4. `command_name == "search"`なら`awaiting_search`を`true`にし、
   `terminal.request_line_input(...)`を呼んで`true`を返す（`Invoker`を経由しない）
5. `command_name`があれば`Invoker.run(command_name, args)`を呼ぶ
6. `draw()`を呼ぶ
7. `true`を返す

## 検索（行入力モード）

検索は、削除確認・表示切替とは異なり、Rust側の行編集（`terminal.request_line_input`/
`read_line`。詳細は`docs/API.md`）を経由する。`fm-interface-design.md`の
「`on_key`の戻り値による入力モード指定」で設計した通り、`on_key`の戻り値自体は
`true`/`false`のまま変えず、Rust側への行入力リクエストは別チャンネル
（`terminal.request_line_input`の呼び出し）で行う。

**流れ**

1. `/`押下: `ListScreen:command_mapper`が`"search"`を返す → `on_key`が
   `awaiting_search = true`にし、`terminal.request_line_input(0, state.display.height - 1,
   state.display.width, "/")`を呼ぶ → `true`を返す
2. Rust側のメインループが、次の反復で`read_key()`の代わりに`read_line(...)`を呼び、
   Enter/Escapeまでブロッキングして行編集を行う
3. 確定時: 確定した検索文字列そのものが、キャンセル時: `"escape"`が、`key`として
   `on_key`に渡される
4. `on_key`は`awaiting_search`が`true`であることを見て、`key`を検索文字列として扱う。
   `key == "escape"`でなければ`Invoker.run("search", { query = key })`を呼ぶ
   （空文字で確定した場合は絞り込みが解除される）
5. `awaiting_search`を`false`に戻し、`draw()`を呼ぶ

## 例外: on_init の直接呼び出し

`on_init`は、初回読み込みに失敗した場合のエラー表示のために、`draw()`を経由せず`screen.clear`/`screen.write`を直接呼び、`load_dir`（ナビゲーション層の内部関数）も直接呼び出している。これは上記のAPIではなく、起動失敗時のみの特別な経路。
