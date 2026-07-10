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

`fm.lua`が保持する`state`テーブル（モジュールローカル変数名は`app_state`）。
`on_init`/`on_key`はRust側から固定シグネチャで呼ばれるためこの変数を直接参照するが、
それ以外の関数（`current_pane`・`enter_directory`・`go_to_parent`・`draw`・
`Invoker.run`経由で呼ばれる`Commands`内の各コマンド）はクロージャで暗黙に
捕捉せず、必ず引数`state`として明示的に受け取る。「どの関数がどこで状態を
読み書きするか」を関数シグネチャから追えるようにするための方針
（C言語のstatic変数のように、ファイル内のどこからでも暗黙に読み書きできる
状態を避ける）。

```lua
local app_state = {
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

`state`には「ファイルマネージャの永続的な状態」だけを置く。コマンド実行結果と
しての「データ準備に対する今回限りの指示」（再読み込みが必要か、フォールバック
メッセージがあるか等）は`state`に混ぜず、`Invoker.run`の戻り値
（instruction。「コマンド登録」「コールバック」を参照）として`on_key`/`draw`へ
明示的に受け渡す。これは意図的な設計判断で、`state`に一時的な指示を混ぜると、
コマンドが増えるほど「どのフィールドが永続的な状態で、どれが一時的な指示か」が
`state`を見ただけでは分からなくなっていくため。

`refresh_files(pane)`（`fm.lua`内部関数）が`pane.all_files`から`pane.files`を
再構築する（`show_hidden`・`search_query`の両方のフィルタを適用。`".."`はどちらの
対象にもならず常に含まれる）。`pane.cursor`が新しい`pane.files`の範囲外になった
場合は末尾に補正する。ディレクトリ読み込み時・`toggle_hidden`実行時・検索確定時に
呼ばれる。すでに`pane`（`state.panes[N]`）を受け取っているので`state`自体は不要。

`load_pane_files(pane, state, fallback_message)`（`fm.lua`内部関数）が
`load_dir(pane.cwd)`で`pane.all_files`をディスクから読み込み、
`refresh_files(pane)`で`pane.files`を再構築する。読み込みに失敗した場合は
`pane.cwd`を変更せずに維持し、`pane.all_files`を空にした上で`state.message`に
`"error: " .. err`をセットする。成功した場合は`state.message`を
`fallback_message`（省略時は空文字）にする。

ファイルシステムは他プロセスからも操作されうる外部の状態であり、この失敗は
「ディレクトリ移動時」に限らず一覧の再取得が発生するあらゆるタイミングで
起こりうる一般的な現象として扱う。専用のエラー画面や確認ダイアログは設けず、
通常の一覧画面のまま（一覧は空、フッターにメッセージ）で継続する。カレント
ディレクトリ自体が削除された場合も同様で、ユーザーが親ディレクトリへ移動する
操作（`backspace`）を繰り返せば、いずれ生きているディレクトリに到達して
自然に回復する。`on_init`・`reload`のどちらもこの関数を経由するため、
挙動は統一されている。

`reload(pane, state, instruction)`（`fm.lua`内部関数）が`load_pane_files(pane, state,
instruction.fallback_message)`を呼ぶ。続けて`instruction.cursor_name`が`nil`で
なければ、それに応じてカーソル位置を決め直す（`false`なら先頭、文字列ならその
名前の要素）。`prepare_data`から`instruction.reload`が`true`の場合にのみ呼ばれる
（詳細は「コールバック」の`prepare_data`を参照）。

`delete`・`enter_directory`（`go_to_parent`/`open_selected`によるディレクトリ移動を
含む）のいずれも、ディスクの読み込みそのものは行わず、戻り値のinstructionで
`reload = true`（と、`enter_directory`の場合は`cursor_name`、`delete`の場合は
`fallback_message`）を伝えるだけにとどめ、実際の再読み込み・カーソル配置・
メッセージ確定は次の`draw()`まで遅延させる（詳細は「コマンド登録」を参照）。
`delete`が常に`reload = true`を返すのは、`rm`の成否によらず一覧を現状に合わせて
検証し直すため（確認ダイアログで"y"を押す前にディレクトリ自体が外部から
削除されているケースでも、古い一覧が残り続けず、実際のエラーが表示される）。

これにより、`newdir`が読み込めない場合のエラー検知も次の`draw()`まで遅延する点に注意
（`pane.cwd`自体は`enter_directory`の時点で即座に書き換わるが、`load_pane_files`が
失敗時に`pane.cwd`を変更しない設計のため、次の再読み込み以降は移動先のcwdで
エラー表示が続く。誤った移動先に留まりたくない場合は、ユーザー自身が
`backspace`でさらに移動して回復する）。

`current_pane(state)`（`fm.lua`内部関数）が`state.panes[state.active_pane]`を返す。
ナビゲーション層・コマンド定義層は、呼び出し時に`state`を渡してこれを経由して
状態を読み書きする。

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
- キー対応: `j`/`down` → `"cursor_down"`, `k`/`up` → `"cursor_up"`, `enter` → `"open_selected"`, `backspace` → `"go_to_parent"`, `.` → `"toggle_hidden"`, `d` → `"confirm_delete"`, `v` → `"toggle_layout"`, `/` → `"confirm_find"`, `q`/`escape` → `"quit"`

`"quit"`だけは`Invoker`を経由せず、`fm.lua`の`on_key`が直接検知する特別な
コマンド名で、`false`を返してメインループを終了させる。それ以外のコマンド名
（`"confirm_find"`を含む）はすべて`Invoker.run`経由で実行される（詳細は
「検索（行入力モード）」「コマンド登録」を参照）。

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

### `ConfirmFindScreen`（`lua/confirm_find_screen.lua`）

`Screen`を継承する、検索入力中のスクリーン。`ConfirmDeleteScreen`と同じく
ブロッキングループではなくスクリーン切り替えで実現しているが、実際の入力編集
はRust側の行入力（`terminal.request_line_input`/`read_line`）に委ねる点が異なる
（詳細は「検索（行入力モード）」を参照）。

#### `ConfirmFindScreen.new(previous_screen)` → instance

- 引数: `previous_screen`（呼び出し元のスクリーンのインスタンス。`ListScreen`
  または`GridScreen`）
- `previous_screen`は、下敷きの描画（`view`）と、検索確定/キャンセル後の
  復帰先の両方に使われる（`ConfirmDeleteScreen`の`previous_screen`と同じ役割）

#### `ConfirmFindScreen:view(data)`

- 動作: `previous_screen:view(data)`をそのまま呼ぶだけ。検索プロンプト
  （`"/"`と入力中の文字列）自体は、`on_key`が終了してRust側の`read_line`が
  実行される際に、同じ行へ上書きで描画される（`docs/API.md`の
  「行入力モードのリクエスト」を参照）ため、Lua側で何かを重ねて描く必要はない

#### `ConfirmFindScreen:command_mapper(key)` → command_name, args

- 引数: `key`（キー名ではなく、Rust側の`read_line`が確定/キャンセルした結果
  そのもの。詳細は「検索（行入力モード）」を参照）
- キー対応: `escape` → `"cancel"`（`args = { previous_screen = previous_screen }`）,
  それ以外（確定した検索文字列。空文字を含む） → `"search"`
  （`args = { query = key, previous_screen = previous_screen }`）

## コマンド登録（`lua/commands.lua`）

コマンドの実装本体は`lua/commands.lua`の`Commands`モジュールに分離されている。
ファイルを開く処理（`open_file`/`open_with_command`とその拡張子判定）・
パス操作のヘルパー（`join_path`/`parent_dir`/`last_segment`）・拡張子ごとの
コマンド定義（`config.load().associations`）は、いずれも`on_init`/`on_key`から
直接使われることがなく、`Invoker`経由のコマンド実行でしか使われないため、
`commands.lua`側に閉じている（`fm.lua`には残していない）。

`fm.lua`はスクリーンの読み書きなど、`on_init`とも共有する最小限の依存だけを
まとめた`ctx`テーブルを組み立て、`Commands.register(ctx)`を1回呼ぶことで、
`lua/invoker.lua`が提供する`Invoker.commands`（コマンド名→実行関数のテーブル）
にすべて登録される。

`commands.lua`は`fm.lua`のローカル変数に直接アクセスできない（別ファイルのため）
ので、必要な依存はすべて`ctx`引数で受け取る。`ctx`は`state`を保持しない。
`state`はクロージャで捕捉せず、`Invoker.run(command_name, args, state)`経由で
呼び出しのたびに引数として渡される（`ctx.current_pane`も同様に、`state`を
引数として明示的に受け取る関数になっている）。`ctx`の内容は以下の通り。

| キー | 内容 |
|---|---|
| `current_pane` | `(state)`を受け取り、操作対象のペインを返す関数 |
| `get_current_screen` / `set_current_screen` | アクティブなスクリーンの参照・切り替え関数 |
| `list_screen` / `grid_screen` | `ListScreen`/`GridScreen`のインスタンス |
| `ConfirmDeleteScreen` | `ConfirmDeleteScreen`モジュール |
| `ConfirmFindScreen` | `ConfirmFindScreen`モジュール |

`refresh_files`（`pane.all_files`から`pane.files`を再構築する関数）は`ctx`に
含まれない。ファイル一覧の内容が変わりうる操作（`toggle_hidden`/`search`）は、
`fm.lua`側の`refresh_files`を直接呼ぶのではなく、`delete`/`enter_directory`と
同様に`{ reload = true }`を返してディスクからの再読み込みを要求する
（他プロセスによる変更を取りこぼさないため。詳細は「状態」の`load_pane_files`・
`reload`を参照）。純粋なカーソル移動（`cursor_down`/`cursor_up`）は再読み込みを
要求しない。

`enter_directory`/`go_to_parent`は`commands.lua`内で`Commands.register(ctx)`の
ローカル関数として定義されているが、ディスクの読み込みは行わない。
`enter_directory(state, newdir, cursor_name)`は`ctx.current_pane(state)`で
取得したペインの`cwd`・`search_query`を書き換えるだけにとどめ、
`{ reload = true, cursor_name = cursor_name or false }`という
instructionテーブルを返す。`pane.all_files`の再読み込みとカーソルの実配置は
`fm.lua`の`reload`（次の`draw()`のデータ準備）に委ねる。`cursor_name`が`nil`の
場合は`instruction.cursor_name`に`false`を入れる（`nil`のままだと「カーソルには
触れない」という別の意味になってしまうため。詳細は「状態」の`reload`を参照）。

登録されるコマンドはすべて`function(args, state)`のシグネチャを持ち
（`Invoker.run`が呼び出し時に渡す）、戻り値としてinstructionテーブル
（データ準備への指示。`nil`の場合は「指示なし」）を返せる。以下は各コマンドの動作。

| コマンド名 | 動作 |
|---|---|
| `cursor_down` | `cursor`を1つ進める（末尾では何もしない） |
| `cursor_up` | `cursor`を1つ戻す（先頭では何もしない） |
| `go_to_parent` | 親ディレクトリへ移動する。戻る前にいたディレクトリの位置にカーソルを合わせる |
| `open_selected` | カーソル位置がディレクトリなら、そこに移動する（`..`の場合は`go_to_parent`相当）。ファイルなら、拡張子に対応するコマンド（`associations`）が定義されていればそれを、なければ`open_file`でファイルを開く |
| `toggle_hidden` | `show_hidden`を反転し、`{ reload = true }`を返す |
| `confirm_delete` | カーソル位置の要素（`".."`は対象外）について、現在のスクリーンを`previous_screen`として渡し`ConfirmDeleteScreen`へ切り替える |
| `delete` | `args.target`を`fs.run("rm ...")`（ディレクトリは`rm -r`）で削除する。成否によらず常に`{ reload = true }`を返す。失敗時はそこに`fallback_message`として削除失敗のメッセージを加える（再読み込みが成功すればこれが表示され、再読み込み自体が失敗すればそちらのエラーが優先される）。いずれの場合も`args.previous_screen`へ戻す |
| `cancel` | 何もせず`args.previous_screen`へ戻す |
| `toggle_layout` | `ListScreen`と`GridScreen`を切り替える |
| `confirm_find` | 現在のスクリーンを`previous_screen`として渡し`ConfirmFindScreen`へ切り替え、`terminal.request_line_input(...)`を呼んでRust側に行入力を要求する（詳細は「検索（行入力モード）」を参照） |
| `search` | `args.query`を`pane.search_query`にセットし、`args.previous_screen`へ戻した上で`{ reload = true }`を返す |

### `open_file(cwd, f)` (`commands.lua`内部関数)

カーソル位置のファイルを`fs.run`経由で外部コマンドで開く。拡張子に対応する
コマンドが`associations`にない場合のデフォルト動作。

- 引数: `cwd`（ファイルのあるディレクトリ）, `f`（`files`の要素。`name`と`size`を使う）
- 戻り値: なし
- 判定: `size == 0`、または`grep -Iq ''`の終了コードが`0`ならテキストファイルとみなし`less`で開く。それ以外は`xxd | less`でダンプを表示する
- ファイル名はシェルクォートしてから`fs.run`に渡す

### `associations`（拡張子ごとのコマンド定義。`commands.lua`内部変数）

拡張子をキーとし、値をコマンドテンプレート文字列とする連想配列。`Commands.register(ctx)`が呼ばれるたびに`config.load().associations`（`lua/config.lua`）から取得する。設定ファイルが存在しない、または不正なTOMLの場合は`config.lua`に内蔵された既定値にフォールバックする。

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

### `draw(state, instruction)`

- 引数: `state`（`app_state`）, `instruction`（省略可。直前に実行したコマンドの
  戻り値。「コマンド登録」を参照）
- 戻り値: なし
- 動作: `screen.get_size()`で`state.display`を更新し、`prepare_data(state,
  instruction)`でデータ準備（`docs/fm-interface-design.md`の「データ準備」を参照）
  を行った上で、`screen.clear()`した上で`get_current_screen():view(state)`を呼ぶ
- 呼び出し元: `on_init`（`instruction`省略）, `on_key`（`Invoker.run`の戻り値を渡す）

### `prepare_data(state, instruction)`

- 引数: `state`（`app_state`）, `instruction`（`nil`の場合は何もしない）
- 戻り値: なし
- 動作: `view`呼び出し前に必要な、表示用データの整形をまとめる関数。
  `instruction.reload`が`true`なら`reload(current_pane(state), state,
  instruction)`を呼ぶ。`instruction`は`state`とは別の、コマンド実行結果としての
  一時的な指示を伝えるための経路（詳細は「状態」の`state`と`instruction`の
  役割分担についての説明を参照）。今後コマンドが増えるにつれ、指示の種類が
  増えた場合はここに追加していく
- 呼び出し元: `draw`

### `on_init()`

- 引数: なし
- 戻り値: なし
- 動作: `load_pane_files(current_pane(app_state), app_state)`でカレントディレクトリの
  一覧を読み込んだ上で（失敗時の挙動は「状態」の`load_pane_files`を参照）、
  `draw(app_state)`を呼ぶ（`instruction`は渡さない＝`nil`）。`instruction.reload`に
  応じた`reload`経由の再読み込みと違い、常に読み込みを行う
- 呼び出し元: Rust側（起動時に1回）

### `on_key(key)`

1. `get_current_screen():command_mapper(key)`で`command_name`を決定する
2. `command_name == "quit"`なら`false`を返して終了（`Invoker`を経由しない）
3. `command_name`があれば`Invoker.run(command_name, args, app_state)`を呼び、
   その戻り値を`instruction`として保持する
4. `draw(app_state, instruction)`を呼ぶ
5. `true`を返す

`"quit"`以外のあらゆるキー入力（検索の入力待ちを含む）が、この単一の
`command_mapper` → `Invoker.run` → `draw`という経路を通る。「今どういう
入力待ちの状態か」はモジュールレベルの変数（旧`awaiting_search`のような
フラグ）ではなく、`get_current_screen()`が返す**スクリーンインスタンスそのもの**
で表現される（`fm-interface-design.md`の「モードは状態ではなく、メインループ
から呼ばれる処理である」という設計方針の通り）。検索の入力待ち中は
`ConfirmFindScreen`がアクティブなスクリーンになっており、次の`key`はその
`command_mapper`に渡される（詳細は「検索（行入力モード）」を参照）。

## 検索（行入力モード）

検索は、削除確認・表示切替と同じくスクリーン切り替えで実現しているが、
実際の文字入力・編集そのものはRust側の行編集（`terminal.request_line_input`/
`read_line`。詳細は`docs/API.md`）に委ねる点が異なる。`fm-interface-design.md`の
「`on_key`の戻り値による入力モード指定」で設計した通り、`on_key`の戻り値自体は
`true`/`false`のまま変えず、Rust側への行入力リクエストは別チャンネル
（`terminal.request_line_input`の呼び出し）で行う。

**流れ**

1. `/`押下: `ListScreen:command_mapper`が`"confirm_find"`を返す
2. `Invoker.run`が`confirm_find`コマンドを実行する: 現在のスクリーンを
   `previous_screen`として`ConfirmFindScreen.new(previous_screen)`に切り替え、
   `terminal.request_line_input(0, state.display.height - 1, state.display.width,
   "/")`を呼ぶ（Rust側に次の行入力リクエストを記録させるだけで、まだブロッキング
   はしない）
3. `draw(app_state, nil)`が呼ばれる。`get_current_screen()`は既に
   `ConfirmFindScreen`なので、その`view`（＝`previous_screen:view`への委譲）が
   描画される。`on_key`はここで終了する
4. Rust側のメインループが、次の反復で`read_key()`の代わりに`read_line(...)`を呼び、
   Enter/Escapeまでブロッキングして行編集を行う（この間の画面上の入力プロンプト
   表示自体はRust側が担当し、Luaの`view`とは独立している）
5. 確定時: 確定した検索文字列そのものが、キャンセル時: `"escape"`が、`key`として
   `on_key`に渡される。`get_current_screen()`は`ConfirmFindScreen`のままなので、
   通常の`on_key`の流れでその`command_mapper(key)`が呼ばれる
6. `key == "escape"`なら`"cancel"`（`previous_screen`へ戻すだけ）、それ以外なら
   `"search"`（`args = { query = key, previous_screen = previous_screen }`。
   空文字で確定した場合は絞り込みが解除される）に変換される
7. `Invoker.run`が`search`コマンドを実行する: `pane.search_query`をセットし、
   スクリーンを`previous_screen`（一覧画面）に戻し、`{ reload = true }`を返す
8. `draw`のデータ準備が再読み込みを行い、絞り込み結果を反映した一覧画面が
   描画される
