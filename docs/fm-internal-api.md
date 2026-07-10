# fm.lua 内部API

`lua/fm.lua` は「状態」「ディレクトリナビゲーション」「コマンド登録」「コールバック」の
4つの塊に分かれている。画面描画そのものは`lua/list_screen.lua`（`ListScreen`）に、
コマンドの実行入口は`lua/invoker.lua`（`Invoker`）に、コマンドの実装本体は
`lua/commands.lua`（`Commands`）に分離されている。
このドキュメントは、これらの境界を跨ぐ最小限の契約を定義する。
各塊の内部だけで完結する関数（`find_index_by_name`, `truncate_name` など）は対象外。

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
    screen = {
        default = list_screen,
        pushed = nil,
        current = list_screen,
    },
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
| `state.screen.default` | table | 標準画面（一覧などの、割り込みが何もない時に表示する画面）のインスタンス |
| `state.screen.pushed` | table/nil | `push_screen`で置かれた「次に見せたい割り込み画面」。`select_screen`が消費するまで保持する |
| `state.screen.current` | table | 今アクティブなスクリーンのインスタンス。`select_screen`でのみ更新する |
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

`fm.lua`は「今アクティブなスクリーンはどれか」を`state.screen`（`default`/`pushed`/
`current`の3フィールド。「状態」を参照）で保持する。読み書きは以下の関数
（`fm.lua`内部関数。いずれも`state`を明示的な第一引数として受け取り、クロージャで
暗黙に捕捉しない）を経由してのみ行う。

- `get_current_screen(state)` → `state.screen.current`を返す
- `push_screen(state, screen_instance)` → `state.screen.pushed`に置く（次に見せたい
  割り込み画面。確認ダイアログや検索入力画面など）
- `get_default_screen(state)` / `set_default_screen(state, screen_instance)` →
  標準画面（一覧などの、割り込みが何もない時に表示する画面）の参照・切り替え。
  `ListScreen`⇔`GridScreen`の切り替え（`toggle_layout`）に使う
- `select_screen(state)` → `state.screen.pushed`があればそれを`current`として採用し
  （1回で消費する）、なければ`default`を採用する

`draw()`は、固定の`ListScreen`インスタンスではなく`get_current_screen(state)`が
返すインスタンスの`view`を呼ぶ。`on_key`は、`get_current_screen(state)`が返す
インスタンスの`command_mapper`でコマンド名を決定し、`Invoker.run`の直後に
`select_screen(state)`を呼ぶ（詳細は「コールバック」の`on_key`を参照）。
`push_screen`/`set_default_screen`はスクリーン自体の切り替えを行わず、次の
`select_screen(state)`呼び出しで初めて`current`に反映される点に注意
（`select_screen`は`on_key`が`Invoker.run`の直後に呼ぶため、実質的には
コマンド実行直後の`draw()`から有効になる）。

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
`view`のみ上書きし、名前だけを2列（`COLUMN_WIDTH`幅ずつ）に並べて表示する。
パーミッション・サイズ・更新日時は表示しない。ページングは行わない
（`list_h × 2`件を超えるファイルは表示されない）。

### `ConfirmDeleteScreen`（`lua/confirm_delete_screen.lua`）

`Screen`を継承する、削除確認ダイアログのスクリーン。`fm-interface-design.md`の
「確認ダイアログの実現方法（ブロッキングループを使わない）」で設計した通り、
ブロッキングループではなくスクリーン切り替えで実現している。

#### `ConfirmDeleteScreen.new(target)` → instance

- 引数: `target`（削除対象のファイルエントリ。`files`の要素）
- `push_screen(state, ConfirmDeleteScreen.new(target))`で`state.screen.pushed`に
  置かれる。復帰先（`y`/`n`後にどの標準画面に戻るか）は、このインスタンス自体は
  何も持たず、`state.screen.default`を使う`select_screen`のフォールバック挙動に
  委ねられる。これにより、`GridScreen`が`default`のときに削除確認を開いても、
  キャンセル・削除後に`ListScreen`へ戻ってしまうことなく、元の表示のまま維持される

#### `ConfirmDeleteScreen:view(data)`

- 動作: フッター行に`"<target.name>" を削除しますか？ (y/n)`を画面幅いっぱいに
  パディングして表示するだけ。下敷き（一覧/2段組）の再描画は行わない
  （前フレームの描画がそのまま画面に残っているため、フッター行以外は書き換える
  必要がない）

#### `ConfirmDeleteScreen:command_mapper(key)` → command_name, args

- キー対応: `y` → `"delete"`（`args = { target = target }`）, `n`/`escape` →
  `"cancel"`（`args`なし）

### `ConfirmFindScreen`（`lua/confirm_find_screen.lua`）

`Screen`を継承する、検索入力中のスクリーン。`ConfirmDeleteScreen`と同じく
ブロッキングループではなくスクリーン切り替えで実現しているが、実際の入力編集
はRust側の行入力（`terminal.request_line_input`/`read_line`）に委ねる点が異なる
（詳細は「検索（行入力モード）」を参照）。

#### `ConfirmFindScreen.new()` → instance

- 引数: なし
- `push_screen(state, ConfirmFindScreen.new())`で`state.screen.pushed`に置かれる。
  復帰先は`ConfirmDeleteScreen`と同じく、このインスタンス自体は何も持たず、
  `select_screen`の`default`へのフォールバック挙動に委ねられる

#### `ConfirmFindScreen:view(data)`

- 動作: `Screen`の既定（何もしない）の`view`をそのまま継承しており、独自の描画は
  一切行わない。検索プロンプト（`"/"`と入力中の文字列）自体は、`on_key`が終了して
  Rust側の`read_line`が実行される際に、同じ行へ上書きで描画される（`docs/API.md`の
  「行入力モードのリクエスト」を参照）ため、Lua側で何かを描く必要がない

#### `ConfirmFindScreen:command_mapper(key)` → command_name, args

- 引数: `key`（キー名ではなく、Rust側の`read_line`が確定/キャンセルした結果
  そのもの。詳細は「検索（行入力モード）」を参照）
- キー対応: `escape` → `"cancel"`（`args`なし）, それ以外（確定した検索文字列。
  空文字を含む） → `"search"`（`args = { query = key }`）

## コマンド登録（`lua/commands.lua`）

コマンドの実装本体は`lua/commands.lua`の`Commands`モジュールに分離されている。
ファイルを開く処理（`open_file`/`open_with_command`）・拡張子ごとのコマンド定義
（`config.load().associations`）は、いずれも`on_init`/`on_key`から直接使われる
ことがなく、`Invoker`経由のコマンド実行でしか使われないため、`commands.lua`側に
閉じている（`fm.lua`には残していない）。

パス・ファイル名の文字列操作（`join`/`parent_dir`/`last_segment`/`extension`/
`strip_extension`）は、状態や外部コマンド実行に依存しない純粋な文字列処理で
あり、`commands.lua`（`open_selected`での拡張子判定・`delete`でのパス組み立て
など）と`lua/list_screen.lua`（ファイル名の切り詰め表示）の両方から使われるため、
`lua/path.lua`という独立したモジュールに切り出されている。

`fm.lua`はスクリーンの読み書きなど、`on_init`とも共有する最小限の依存だけを
まとめた`ctx`テーブルを組み立て、`Commands.register(ctx)`を1回呼ぶことで、
`lua/invoker.lua`が提供する`Invoker.commands`（コマンド名→実行関数のテーブル）
にすべて登録される。

`commands.lua`は`fm.lua`のローカル変数に直接アクセスできない（別ファイルのため）
ので、必要な依存はすべて`ctx`引数で受け取る。`ctx`は`state`を保持しない。
`state`はクロージャで捕捉せず、`Invoker.run(command_name, args, state)`経由で
呼び出しのたびに引数として渡される（`ctx.current_pane`・`ctx.push_screen`・
`ctx.get_default_screen`・`ctx.set_default_screen`も同様に、`state`を引数として
明示的に受け取る関数になっている）。`ctx`の内容は以下の通り。

| キー | 内容 |
|---|---|
| `current_pane` | `(state)`を受け取り、操作対象のペインを返す関数 |
| `push_screen` | `(state, screen_instance)`を受け取り、次に見せたい割り込み画面を置く関数 |
| `get_default_screen` / `set_default_screen` | `(state)`/`(state, screen_instance)`で標準画面の参照・切り替えを行う関数 |
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
| `confirm_delete` | カーソル位置の要素（`".."`は対象外）について、`ConfirmDeleteScreen`を`push_screen`で置く |
| `delete` | `args.target`を`fs.run("rm ...")`（ディレクトリは`rm -r`）で削除する。成否によらず常に`{ reload = true }`を返す。失敗時はそこに`fallback_message`として削除失敗のメッセージを加える（再読み込みが成功すればこれが表示され、再読み込み自体が失敗すればそちらのエラーが優先される）。何もpushしないため、`select_screen`のフォールバックにより標準画面(一覧/2段組)に戻る |
| `cancel` | 何もしない（何もpushしないため、`select_screen`のフォールバックにより標準画面(一覧/2段組)に戻る） |
| `toggle_layout` | `set_default_screen`で`ListScreen`と`GridScreen`を切り替える（`push_screen`は使わない） |
| `confirm_find` | `ConfirmFindScreen`を`push_screen`で置き、`terminal.request_line_input(...)`を呼んでRust側に行入力を要求する（詳細は「検索（行入力モード）」を参照） |
| `search` | `args.query`を`pane.search_query`にセットし、`{ reload = true }`を返す。何もpushしないため、`select_screen`のフォールバックにより標準画面(一覧/2段組)に戻る |

### `open_file(cwd, f)` (`commands.lua`内部関数)

カーソル位置のファイルを`fs.run`経由で外部コマンドで開く。拡張子に対応する
コマンドが`associations`にない場合のデフォルト動作。

- 引数: `cwd`（ファイルのあるディレクトリ）, `f`（`files`の要素。`name`と`size`を使う）
- 戻り値: なし
- 判定: `size == 0`、または`grep -Iq ''`の終了コードが`0`ならテキストファイルとみなし`less`で開く。それ以外は`xxd | less`でダンプを表示する
- ファイル名はシェルクォートしてから`fs.run`に渡す

### `associations`（拡張子ごとのコマンド定義。`commands.lua`内部変数）

拡張子をキーとし、値をコマンドテンプレート文字列とする連想配列。`Commands.register(ctx)`が呼ばれるたびに`config.load().associations`（`lua/config.lua`）から取得する。設定ファイルが存在しない、または不正なTOMLの場合は`config.lua`に内蔵された既定値にフォールバックする。

- キー: 拡張子（`path.extension`が返す値。先頭がドットの隠しファイルで他にドットがない場合は拡張子なし扱いになりマッチしない）
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
  を行った上で、`get_current_screen(state):view(state)`を呼ぶ。`screen.clear()`は
  `draw`自体は呼ばず、`ListScreen:view`/`GridScreen:view`側で行う（`ConfirmDeleteScreen`/
  `ConfirmFindScreen`はクリアしないことで、下敷きの一覧/2段組の描画をそのまま残す）
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

1. `get_current_screen(app_state):command_mapper(key)`で`command_name`を決定する
2. `command_name == "quit"`なら`false`を返して終了（`Invoker`を経由しない）
3. `command_name`があれば`Invoker.run(command_name, args, app_state)`を呼び、
   その戻り値を`instruction`として保持した上で、`select_screen(app_state)`を呼ぶ
   （`state.screen.pushed`があればそれを`current`として採用し、なければ
   `default`を採用する。詳細は「画面描画・スクリーン管理」を参照）
4. `draw(app_state, instruction)`を呼ぶ
5. `true`を返す

`"quit"`以外のあらゆるキー入力（検索の入力待ちを含む）が、この単一の
`command_mapper` → `Invoker.run` → `select_screen` → `draw`という経路を通る。
「今どういう入力待ちの状態か」はモジュールレベルの変数（旧`awaiting_search`の
ようなフラグ）ではなく、`state.screen.current`（`get_current_screen(state)`が
返す）が指す**スクリーンインスタンスそのもの**で表現される
（`fm-interface-design.md`の「モードは状態ではなく、メインループから呼ばれる
処理である」という設計方針の通り）。検索の入力待ち中は`ConfirmFindScreen`が
`state.screen.current`になっており、次の`key`はその`command_mapper`に渡される
（詳細は「検索（行入力モード）」を参照）。

## 検索（行入力モード）

検索は、削除確認・表示切替と同じくスクリーン切り替えで実現しているが、
実際の文字入力・編集そのものはRust側の行編集（`terminal.request_line_input`/
`read_line`。詳細は`docs/API.md`）に委ねる点が異なる。`fm-interface-design.md`の
「`on_key`の戻り値による入力モード指定」で設計した通り、`on_key`の戻り値自体は
`true`/`false`のまま変えず、Rust側への行入力リクエストは別チャンネル
（`terminal.request_line_input`の呼び出し）で行う。

**流れ**

1. `/`押下: `ListScreen:command_mapper`が`"confirm_find"`を返す
2. `Invoker.run`が`confirm_find`コマンドを実行する: `push_screen(state,
   ConfirmFindScreen.new())`で`state.screen.pushed`に置き、
   `terminal.request_line_input(0, state.display.height - 1, state.display.width,
   "/")`を呼ぶ（Rust側に次の行入力リクエストを記録させるだけで、まだブロッキング
   はしない）。続けて`on_key`が`select_screen(app_state)`を呼ぶため、
   `state.screen.current`は`ConfirmFindScreen`になる
3. `draw(app_state, nil)`が呼ばれる。`get_current_screen(state)`は既に
   `ConfirmFindScreen`なので、その`view`（何もしない）が呼ばれる。下敷きの
   一覧/2段組の描画はクリアされずそのまま残る。`on_key`はここで終了する
4. Rust側のメインループが、次の反復で`read_key()`の代わりに`read_line(...)`を呼び、
   Enter/Escapeまでブロッキングして行編集を行う（この間の画面上の入力プロンプト
   表示自体はRust側が担当し、Luaの`view`とは独立している）
5. 確定時: 確定した検索文字列そのものが、キャンセル時: `"escape"`が、`key`として
   `on_key`に渡される。`state.screen.current`は`ConfirmFindScreen`のままなので、
   通常の`on_key`の流れでその`command_mapper(key)`が呼ばれる
6. `key == "escape"`なら`"cancel"`（`args`なし）、それ以外なら`"search"`
   （`args = { query = key }`。空文字で確定した場合は絞り込みが解除される）に
   変換される
7. `Invoker.run`が`search`（または`cancel`）コマンドを実行する。`search`は
   `pane.search_query`をセットし`{ reload = true }`を返す。どちらのコマンドも
   何もpushしないため、続く`select_screen(app_state)`が`state.screen.pushed`を
   見つけられず`default`（一覧/2段組）にフォールバックする
8. `draw`のデータ準備が（`search`の場合）再読み込みを行い、絞り込み結果を
   反映した一覧画面が描画される
