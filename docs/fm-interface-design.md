# fm インタフェース定義

このファイルは、fmのスクリーン・ビュー・コマンドマッパー・インボーカーの
インタフェースを定義していくためのドキュメント。まず用語を定義し、以降
このファイルに具体的なインタフェース（関数のシグネチャ、渡すデータの
構造など）を追記していく。

## この検討の方針

各処理を関数やLuaのテーブル（クラスに相当するイメージ）を使って定義
していく。引数やテーブルのデータ・グローバル変数は代表的な定義をするに
留め、現時点で完璧なものを目指さない。

目的は、ClaudeCodeに設計・実装を任せるときに、現状の設計意図が伝わる
形にすることであり、厳密な仕様書を作ることではない。これは
`fm-mode-interface-design.md`で確認した「厳密なインタフェース仕様を
決め切ることはできない、実際に作ってみないとわからない部分が残る」
という方針とも一致する。

## 背景

`fm-mode-interface-design.md`での4ケース（削除・検索・隠しファイル表示
切替・外部コマンド実行）の検討と、「モードは状態ではなく、メインループ
から呼ばれる処理である」という発見を経て、当初「モード」という1つの
言葉で呼んでいた概念が、性質の異なる2つの概念に分かれることが分かった。

- 画面バリエーション（1列表示・2列表示・PC情報ポップアップなど）を
  切り替える話 ─ 描画とキー入力がワンセットになった単位
- 削除・検索・隠しファイル表示切替・外部コマンド実行のような、1回で
  完結する処理を実行する話 ─ 統一された入り口を持つ実行の仕組み

この2つを明確に区別するため、以下の用語を定義する。

## 用語定義

| 用語 | 役割 |
|---|---|
| **スクリーン** | `draw`（ビュー）+ `on_key`（コマンドマッパー）のセット。画面バリエーション（1列表示・2列表示・PC情報ポップアップなど）の単位。グローバルな`draw`/`on_key`の内部から、アクティブなものが呼ばれる |
| **ビュー** | スクリーンが持つ、画面に何を表示するかの描画処理 |
| **コマンドマッパー** | スクリーンが持つ、キー入力から実行すべきコマンドを決定する処理 |
| **インボーカー** | コマンドマッパーが決定したコマンドを、実際に実行する統一入口 |

「インボーカー」という名称は、GoFのCommandパターンにおける`Invoker`
（コマンドオブジェクトを受け取り、それを実行する責任を持つもの）という
役割に由来する。

## メインループとの対応

Rust側から呼ばれるのは、今までと変わらず**グローバルな`on_init`/`on_key`
のみ**（`lua_bridge.rs`が呼び出すインタフェースは変わらない）。「スクリーン
ごとの`draw`/`on_key`」というのは、Rustが直接使い分けて呼ぶという意味では
なく、グローバルな`on_key`/`draw`の内部で「今どのスクリーンがアクティブ
か」を判断し、そのスクリーンの**コマンドマッパー**/**ビュー**に処理を
委譲する、という構造を指す。

> **後日の訂正**: 「Rust側から呼ばれるのは`on_init`/`on_key`のみで変わら
> ない」という前提は、本ファイル末尾「`on_key`の戻り値による入力モード
> 指定」で見直されている。`read_line`相当の行入力を実現するために、
> `on_key`の戻り値でRustに次の入力モードを伝える必要があり、Rustの
> メインループ自体に変更が必要になる。

`fm-mode-interface-design.md`の「重要な発見」で示したメインループの
概念図を、この用語で書き直すと以下のようになる。

**グローバルな`draw()`**

1. データ準備
2. 今の状態を見て、どのスクリーンがアクティブかを判断する
3. アクティブなスクリーンの**ビュー**を呼ぶ
4. return

**グローバルな`on_key()`**

1. 今の状態を見て、どのスクリーンがアクティブかを判断する
2. アクティブなスクリーンの**コマンドマッパー**を呼ぶ
3. コマンドマッパーが「実行すべきコマンド」を決定する（実行はしない、
   決定するだけ）
4. return
5. **インボーカー**を呼ぶ（コマンド名とデータを渡す）
6. インボーカーがコマンドを実行する（内部処理でも外部コマンドでも、
   この中で完結。確認や追加入力が必要な場合は、ブロッキングして待つ
   のではなく、**別のスクリーンに切り替える**ことで次のキー入力を待つ
   （詳細は「確認ダイアログの実現方法」を参照）。ただし`read_line`の
   ような、Rust側が短い入力ループ自体を完結させて返してくる形の呼び出し
   はこの限りではない
7. return
8. グローバルな`draw()`を呼ぶ（再描画）
9. return

## 各ケースとの対応（`fm-mode-interface-design.md`との対応表）

`fm-mode-interface-design.md`で「コマンド実行モードへ遷移する」
「コマンド実行処理を呼ぶ」としていた記述は、この用語では次のように
対応する。

| `fm-mode-interface-design.md`での表現 | この用語での表現 |
|---|---|
| 通常モード | 通常のスクリーン（ファイル一覧の**ビュー**＋**コマンドマッパー**） |
| コマンド実行モードへ遷移 | **インボーカー**を呼ぶ |
| コマンド実行モードが保持する状態 | （不要。呼び出しのローカルな引数・戻り値、またはグローバル状態の直接変更で完結する） |
| 「削除コマンドの処理」「検索コマンドの処理」など | インボーカーが、コマンド名に応じて内部で分岐する処理 |

## 残る検討事項

- **アクティブなスクリーン切り替えの前後処理**: `set_current_screen`が
  呼ばれる前後で、切り替え元・切り替え先のスクリーンに何らかの後始末
  や初期化処理が必要になるか（例: 切り替え時にカーソル位置を引き継ぐ、
  など）は未検討
- **`Invoker.run`のエラー処理**: 未知のコマンド名が渡された場合や、
  各コマンドの実行関数が失敗した場合の扱いは代表例レベルに留まっている
  （`fm-screen-architecture.md`の「エラー・異常系の扱い」の方針と
  合わせて、実装時に詰める）
- **`prepare_data()`の中身**: ソート・フィルタ処理の具体的な実装は
  今回のインタフェース定義の対象外（`fm-screen-architecture.md`の
  未決事項を参照）。ただし、ファイル数が多い場合にソート処理でコピーの
  コストが発生するのではという懸念については、Luaの標準関数
  `table.sort`が既存のテーブルの中身を並び替えるだけ（in-place）で
  新しいテーブルを作らないため、コピーコストは発生しないことを確認
  済み。

  ```lua
  -- table.sort はコピーせず、既存のテーブルを直接並び替える
  table.sort(state.files, function(a, b)
      return a.name < b.name
  end)
  -- ソート後、state.files をそのままビューに渡してよい
  ```

  第2引数の比較関数を差し替えるだけでソートキー（名前順・サイズ順・
  更新日時順など）を切り替えられる。ただし、この方法では取得直後の
  順序を後から復元することはできない（必要になった場合は`fs.list()`を
  再度呼び直す）。

---

## データ構造の基本形

ファイルマネージャが持つ全データは、`state`という1つのテーブルに
まとめる。`fm-screen-architecture.md`で決めた3カテゴリ（ファイル
システム・コンピュータの情報／表示に関する情報／ファイルマネージャ
としての情報）を反映した構造とする。

サイズや日時などの数値データは、そのまま数値として持つ（文字列化は
しない）。表示用の文字列への変換は`state`の責務ではなく、**ビュー側が
ヘルパー関数を使って行う**。これは、レイアウトエンジン・テンプレート
エンジンに渡す前に呼び出し側が文字列化する、という既存の設計方針
（`fm-spec-v0.1.md`、レイアウトエンジンAPI）とも一貫している。

```lua
local state = {
    -- 1. ファイルシステム・コンピュータの情報
    system = {
        storage = "120GB free",
    },

    -- 2. 表示に関する情報
    display = {
        width = 80,
        height = 25,
        color = true,
    },

    -- 3. ファイルマネージャとしての情報
    panes = {
        {
            cwd = "/home/user",
            cursor = 1,
            show_hidden = false,
            sort_key = "name",
            files = {
                -- fs.list()の結果がそのまま入る（サイズ・日時は数値/生データのまま）
            },
        },
    },
    active_pane = 1,
    message = "",
}
```

（代表例のみ。マーク機能や複数ペインの詳細な項目は、必要になった時点で
`panes`要素に追加していく想定。）

---

## インタフェース定義

### スクリーン（基底テーブル）

スクリーンは1つのテーブル（クラスに相当）として定義し、具体的な各
スクリーン（ファイル一覧の1列表示・2列表示、PC情報ポップアップなど）は
これを継承する形で実装する。継承にはLuaの`__index`メタテーブルを使った
典型的なパターンを用いる。

基底のスクリーンは、`view`（ビュー）と`command_mapper`（コマンドマッパー）
という2つのメソッドを持つ。デフォルトでは何もしない実装とし、各具体的な
スクリーンがこれを上書きする。

```lua
-- 基底となるスクリーンの型（クラスに相当）
local Screen = {}
Screen.__index = Screen

function Screen.new()
    local self = setmetatable({}, Screen)
    return self
end

-- デフォルトのビュー（何も描画しない）
function Screen:view(data)
end

-- デフォルトのコマンドマッパー（何も反応しない）
function Screen:command_mapper(key)
    return nil  -- 実行すべきコマンドなし
end

return Screen
```

具体的なスクリーンは、これを継承して`view`と`command_mapper`を上書きする。
例（ファイル一覧の1列表示）：

```lua
local Screen = require("screen")

local ListView = setmetatable({}, { __index = Screen })
ListView.__index = ListView

function ListView.new()
    local self = Screen.new()
    return setmetatable(self, ListView)
end

function ListView:view(data)
    -- ファイル一覧を1列で描画
end

function ListView:command_mapper(key)
    if key == "j" then return "cursor_down" end
    if key == "k" then return "cursor_up" end
    -- ...（代表例のみ。網羅はしない）
end

return ListView
```

グローバルな`draw`/`on_key`（Rustから呼ばれる唯一の入口）は、「今
アクティブなスクリーンはどれか」を判断し、そのインスタンスの`view`/
`command_mapper`を呼ぶ。

> **検討メモ**: `Screen`をメタテーブルによる継承（クラス）にする必要が
> あるかどうかは一度議論になった。今のコードベース（`layout.lua`/
> `template.lua`/`config.lua`/`view.lua`）はすべて素朴なテーブルを返す
> だけで、メタテーブル・継承は使っていない。ただし、`Screen`と
> `Invoker`は「試作・変更のしやすさ」というコンセプトのコアであり、
> インタフェースを共通化したいという意図でこの形にしている。継承の
> 段数（今は1段のみ）が問題なのではなく、「切り替え前後の初期化・
> 後始末処理」のような将来のメソッド追加時に、`Screen`側にデフォルト
> 実装を1つ足すだけで全スクリーンに波及させられる、という拡張性が
> 目的であるため、この設計判断は妥当と判断している。

### インボーカー

インボーカーは、コマンドマッパーが決定した「コマンド名」を受け取り、
実際にそのコマンドを実行する。コマンド名をキーにした実行関数のテーブル
として持つ。

```lua
-- インボーカー: コマンド名 → 実行関数 のテーブル
local Invoker = {}

Invoker.commands = {
    -- "d"押下時: 削除を確認するスクリーンに切り替えるだけ（実際の削除はしない）
    confirm_delete = function(args)
        set_current_screen(ConfirmDeleteScreen.new(args.target))
    end,

    -- ConfirmDeleteScreen で "y" が押されたときに呼ばれる
    delete = function(args)
        -- 実際の削除処理を実行
        -- 成功: ファイル一覧のスクリーンに戻す
        -- 失敗: state.message にエラーをセットしてファイル一覧に戻す、
        --       またはエラー内容を持ったポップアップ用スクリーンに切り替える
        set_current_screen(list_screen)
    end,

    -- ConfirmDeleteScreen で "n" が押されたときに呼ばれる
    cancel = function(args)
        set_current_screen(list_screen)
    end,

    search = function(args)
        -- terminal.read_line(...)を呼び、検索状態をセットする
    end,

    toggle_hidden = function(args)
        -- show_hiddenを反転する
    end,

    -- ...（代表例のみ）
}

-- 呼び出しの入口
function Invoker.run(command_name, args)
    local fn = Invoker.commands[command_name]
    if not fn then
        return nil  -- 未知のコマンド名（エラー処理は今は代表例に留める）
    end
    return fn(args)
end

return Invoker
```

呼び出し側（コマンドマッパーが決定したコマンドを受けて）は、グローバルな
`on_key`の中で以下のように使う。

```lua
local Invoker = require("invoker")

-- on_key の中で
local command_name, args = screen:command_mapper(key)
if command_name then
    local err = Invoker.run(command_name, args)
end
draw()
```

> **後日の訂正**: 上記の`Invoker.run(command_name, args)`・
> `Invoker.commands[...] = function(args)`は、実装段階で`state`を
> 明示的な第三引数（コマンド関数側は第二引数）として受け取る形に変更された。
> `state`をクロージャで暗黙に捕捉せず、呼び出しのたびに引数として渡す
> という方針（「アクティブなスクリーンの保持」の訂正でも同じ理由により
> `push_screen`等が`state`を受け取るようにしている）を、コマンド実行の
> 経路全体に一貫して適用したもの。実際のシグネチャは
> `Invoker.run(command_name, args, state)`・
> `Invoker.commands.xxx = function(args, state) ... end`であり、
> `set_current_screen(...)`の呼び出しも上記の訂正の通り
> `push_screen(state, ...)`/`select_screen(state)`に置き換わっている。
> 詳細は`docs/fm-internal-api.md`の「コマンド登録」を参照。

### 呼び出し側の全体構成（グローバルな`draw`/`on_key`）

Luaの`:`（コロン）記法で定義したメソッドは、暗黙的に`self`を第一引数
として受け取る。呼び出し側も`:`を使わないと`self`が渡されず、意図した
引数がずれてしまう点に注意する。

`view`はコマンドマッパー・インボーカーの実行後に直接呼ぶのではなく、
`on_key`とは別の**グローバルな`draw()`**を経由して呼ぶ。`draw()`は
「データ準備 → アクティブなスクリーンの`view`呼び出し」の2ステップを
持つ。こうすることで、`on_init`から最初の画面を描くときも同じ`draw()`を
呼べばよく、データ準備のコードが重複しない。

```lua
function on_key(key)
    local current_screen = get_current_screen()  -- 現在のスクリーンを取得（仮）
    local command_name, args = current_screen:command_mapper(key)
    if command_name then
        Invoker.run(command_name, args)
    end
    draw()
end

function draw()
    local data = prepare_data()  -- データ準備（ソート・フィルタなど）
    local current_screen = get_current_screen()
    current_screen:view(data)
end

function on_init()
    -- 初期化処理
    draw()
end
```

`get_current_screen()`（アクティブなスクリーンをどう判断し、どう保持
するか）の具体的な実装は未定義（代表例として関数呼び出しの形だけ示す）。

### コマンドマッパーの継承・上書き

キーマップ（キー→コマンド名の対応）は、以下の流れで組み立てる。

1. **ユーザーコンフィグ**（キー→コマンド名の対応）を読み込む
2. それに**組み込みの定義**（メッセージウィンドウのOK/キャンセルなど、
   ユーザーが設定しなくても最初から存在すべきもの）をマージし、
   「基本のキーマップテーブル」とする
3. 画面バリエーション系のスクリーン（1列表示・2列表示など）は、基本の
   キーマップを**継承**しつつ、必要な部分だけ上書き・追加する
4. 性質が全く違うスクリーン（ポップアップなど）は、基本のキーマップを
   継承せず、**新規にテーブルを作る**

キーマップの値（コマンド名）は文字列に限定する。理由は以下の2点。

- **ユーザーコンフィグとの相性**: 設定ファイルは基本的に文字列・数値・
  真偽値しか書けない。関数のような値を持たせると、ユーザーコンフィグと
  組み込み定義を同じ形式でマージできなくなる
- **役割分担の明確さ**: コマンド名が文字列なら`Invoker.commands[文字列]`
  とそのまま対応する。関数を値に持たせると、キーマップの役割が「キー→
  コマンド名の対応」から「キー→実行ロジックの一部」に広がり、コマンド
  マッパーとインボーカーの役割分担が曖昧になる

なお、文字列のテーブル引き自体はLuaにおいて軽い処理であり（内部的に
ハッシュテーブルで実装され、文字列はインターン化される）、かつキー入力
のたびに1回発生するだけの頻度であるため、パフォーマンス上の懸念はない。

```lua
-- 基本のキーマップ（ユーザーコンフィグ + 組み込み定義のマージ結果）
local base_keymap = merge(user_config.keymap, builtin_keymap)

-- 1列表示スクリーンのコマンドマッパー: 基本を継承しつつ一部を上書き
local ListScreenKeymap = setmetatable({}, { __index = base_keymap })
ListScreenKeymap["v"] = "toggle_layout"  -- 追加
-- 変更がなければ base_keymap のものがそのまま使われる（__index経由）

-- ポップアップのコマンドマッパー: 継承せず新規
local PopupKeymap = {
    ["y"] = "confirm_yes",
    ["n"] = "confirm_no",
    ["escape"] = "confirm_cancel",
}
```

### コマンドマッパーの2段階の責務

`command_mapper`は、「キー→コマンド名のテーブル引き」と「コマンドごとの
引数組み立て」という2段階の処理を行い、最終的に`command_name, args`の
ペアを返す。

```lua
function Screen:command_mapper(key)
    local command_name = self.keymap[key]
    if not command_name then
        return nil
    end

    -- コマンドごとに必要な引数を組み立てる（代表例のみ）
    local args = nil
    if command_name == "delete" then
        args = { target = self:current_file() }
    elseif command_name == "search" then
        args = { x = 0, y = self.height - 1, max_width = self.width }
    end
    -- toggle_hidden などは引数不要なので args = nil のまま

    return command_name, args
end
```

### アクティブなスクリーンの保持

「今アクティブなスクリーンはどれか」は、特別な仕組みは必要とせず、
モジュールレベルのローカル変数（そのスクリーンの**インスタンスそのもの**
を保持する）で表現できる。

```lua
-- fm.lua（あるいは screen_manager.lua のような専用モジュール）の中

local current_screen = nil  -- 今アクティブなスクリーンのインスタンス

local function get_current_screen()
    return current_screen
end

local function set_current_screen(screen)
    current_screen = screen
end
```

スクリーンを切り替えるコマンド（例えば「1列表示⇔2列表示」を切り替える
`toggle_layout`）は、インボーカーの実行関数の中から`set_current_screen`
を呼ぶ。

```lua
Invoker.commands.toggle_layout = function(args)
    if get_current_screen() == list_screen then
        set_current_screen(grid_screen)
    else
        set_current_screen(list_screen)
    end
end
```

`current_screen`に入るのは文字列や識別子ではなく、`ListView.new()`や
`GridView.new()`のような、あらかじめ作られたスクリーンの**インスタンス**
である。そのため`current_screen:view(data)`や
`current_screen:command_mapper(key)`のように、そのインスタンスの
メソッドをそのまま呼べる。

Luaでは`local`で宣言した変数はモジュールの外から直接参照できず、
`get_current_screen`/`set_current_screen`のような関数を通してのみ
アクセスできる（簡易的なカプセル化になる）。

> **後日の訂正**: 上記の`set_current_screen`方式は実装段階で見直された。
> `confirm_delete`/`confirm_find`のような割り込み画面は、切り替え元の
> スクリーンのインスタンス（`previous_screen`）を自分で保持し、`delete`/
> `cancel`/`search`の`args`経由でインボーカーにまで運んで、「y/n確定後や
> キャンセル後にどこへ戻るか」を毎回明示的に指定していた。この「戻り先を
> 覚えて運ぶ」処理自体がコマンドの本質と無関係な配線になっていたため、
> 「戻る」という概念自体をスクリーン遷移の仕組みから無くす方式に変更した。
>
> - `default_screen`（標準画面。一覧/2段組など、割り込みが無い時に表示
>   する画面）と`push_screen(screen)`（次に見せたい割り込み画面を置く
>   だけの関数）を用意する
> - `select_screen()`が、`push_screen`で置かれた画面があればそれを、
>   なければ`default_screen`を`current_screen`として採用する。この判定は
>   コマンドを実際に実行した直後にのみ行う（実行していない時に行うと、
>   割り込み画面をpushしていないのに`default_screen`へ戻ってしまう）
> - `confirm_delete`/`confirm_find`は`push_screen(...)`するだけ。
>   `delete`/`cancel`/`search`は何もpushしない（＝結果的に`default_screen`
>   に戻る）。「戻る」ための処理はコマンド側に一切書かない
> - `toggle_layout`（1列⇔2段組）のような、割り込みとは無関係な標準画面
>   自体の切り替えは、`current_screen`ではなく`default_screen`を
>   `set_default_screen`で書き換えることで表現する
>
> 併せて、確認ダイアログの`view`が切り替え元スクリーンの`view`を呼んで
> 「下敷き」をフル再描画する処理（後述）もこの時点で廃止した。`draw()`が
> 一律に`screen.clear()`していた処理をやめ、一覧・2段組スクリーンが
> 自分の`view`の中で`screen.clear()`する形に変更。確認ダイアログは自分の
> メッセージ行を画面幅いっぱいにパディングして上書きするだけで、前フレーム
> （直前に表示されていた一覧/2段組）の内容はそのまま端末に残り続けるため、
> 切り替え元スクリーンへの参照は`view`のためにも不要になった。
>
> **さらに後日の訂正**: `default_screen`/`pushed_screen`/`current_screen`は
> 当初`fm.lua`のモジュールローカル変数だったが、`state`（`panes`など）を
> クロージャで暗黙に捕捉せず引数として明示的に渡すという方針を、この3つの
> 変数にも一貫して適用するため`state.screen = { default, pushed, current }`
> に移した。`get_current_screen()`/`push_screen(screen)`/
> `get_default_screen()`/`set_default_screen(screen)`/`select_screen()`は
> いずれも`state`を明示的な第一引数として受け取る
> （`get_current_screen(state)`/`push_screen(state, screen)`など）。
> 詳細は`docs/fm-internal-api.md`の「画面描画・スクリーン管理」を参照。

### 確認ダイアログの実現方法（ブロッキングループを使わない）

ケース1（削除）の当初の検討では、`y`/`n`の入力を「インボーカーの中で
ブロッキングループを回して待つ」という形で書いていた。しかしこれだと、
確認メッセージの表示だけが`view`のパイプラインを経由しない特別な
描画経路になってしまう（ClaudeCodeによるレビューで指摘された懸念）。

この懸念は、確認ダイアログも**「メッセージ表示用のスクリーン」**として
定義することで解消する。形は他のスクリーンと同じ（`view`と
`command_mapper`を持つ）で、表示内容を確認メッセージだけに絞る。

```lua
local ConfirmDeleteScreen = setmetatable({}, { __index = Screen })
ConfirmDeleteScreen.__index = ConfirmDeleteScreen

function ConfirmDeleteScreen.new(target)
    local self = Screen.new()
    self.target = target
    return setmetatable(self, ConfirmDeleteScreen)
end

function ConfirmDeleteScreen:view(data)
    -- 確認メッセージを画面に表示するだけ
    screen.write(0, data.display.height - 1, "本当に削除しますか？ (y/n)")
end

function ConfirmDeleteScreen:command_mapper(key)
    if key == "y" then return "delete", { target = self.target } end
    if key == "n" then return "cancel" end
    return nil
end
```

**流れ**

1. `d`押下: ファイル一覧の`command_mapper`が`"confirm_delete"`を返す →
   インボーカーが`set_current_screen(ConfirmDeleteScreen.new(target))`
   を実行 → 同じ`on_key`周期の中で`draw()`が呼ばれ、
   `ConfirmDeleteScreen`の`view`が確認メッセージを表示する
2. `y`押下: （次の`on_key`周期）`ConfirmDeleteScreen`の`command_mapper`が
   `"delete"`を返す → インボーカーの`delete`が実際の削除を実行し、成功・
   失敗いずれの場合も次のスクリーンを設定する
3. `n`押下: （次の`on_key`周期）`ConfirmDeleteScreen`の`command_mapper`が
   `"cancel"`を返す → インボーカーの`cancel`が`list_screen`に戻すだけ

**スクリーン切り替えのタイミング**

`set_current_screen`は、呼ばれた**直後の`draw()`から**有効になる。次の
`on_key`呼び出しを待つ必要はない。

| タイミング | `current_screen` | 呼ばれるもの |
|---|---|---|
| `d`押下、`on_key`の前半 | ファイル一覧 | ファイル一覧の`command_mapper` |
| `d`押下、インボーカー実行中 | ファイル一覧→`ConfirmDeleteScreen`に切り替え | ─ |
| `d`押下、`draw()`呼び出し | `ConfirmDeleteScreen` | `ConfirmDeleteScreen`の`view` |
| `y`押下、`on_key`の前半 | `ConfirmDeleteScreen`（前の周期のまま） | `ConfirmDeleteScreen`の`command_mapper` |

**削除失敗時の2つのバリエーション**

- **即座にファイル一覧へ戻す**: `delete`コマンドの中で`state.message`に
  エラーをセットし、`set_current_screen(list_screen)`を呼ぶ。ファイル
  一覧の`view`が`state.message`を見てエラーを表示する
- **エラーポップアップを経由する**: `delete`コマンドの中で
  `set_current_screen(ErrorPopupScreen.new(err))`を呼ぶ。OK押下時、
  `ErrorPopupScreen`の`command_mapper`が`"dismiss_error"`のような
  コマンドを返し、インボーカーがそこで`list_screen`に戻す

どちらのバリエーションも、「スクリーンを切り替える」という同じ仕組みで
説明できる。この結果、`view`が唯一の描画経路であるという原則を崩さずに
確認ダイアログ・エラー表示の両方を実現できる。

> **後日の訂正**: このセクションの`set_current_screen`を使った記述は、
> 「アクティブなスクリーンの保持」の訂正で述べた`push_screen`/
> `default_screen`方式に置き換わっている。`confirm_delete`は
> `push_screen(state, ConfirmDeleteScreen.new(target))`を呼ぶだけ、
> `cancel`は何もしない（＝`default_screen`に戻る）。「削除失敗時の2つの
> バリエーション」も同様に、`delete`が何もpushしなければ標準画面に戻る
> 形になる（`state`を明示的な引数として渡す点については、上記の
> 「さらに後日の訂正」を参照）。

---

## 基本パターン（総括）

ここまでの検討を通じて、fmで発生するあらゆる画面遷移は、以下の3ステップ
の繰り返しとして説明できることが分かった。

1. **キー入力**
2. **何らかの処理**（コマンド実行・状態変更・何もしない、のいずれか）
3. **画面表示**

「キー入力と画面表示が常にワンセットである」という制約さえ守れば、間に
挟む処理の複雑さ（コマンドの有無、確認や追加入力の有無、成功・失敗の
分岐）は自由に変えられる。削除・検索・隠しファイル切替・外部コマンド
実行・確認ダイアログ・エラーポップアップは、すべてこの1つのパターンの
バリエーションとして説明できる。

「複数のコマンドを連続実行したいケース」は例外に見えるが、実際には
例外ではない。1回のキー入力につき1回の処理という原則を破る必要はなく、
仮に複数のコマンドを連続実行したい場面が生じても、インボーカーの中で
複数のコマンドを順に呼べばよい（画面表示は最後に1回だけ行われる）。

当初「テンプレート記法をどう拡張するか」という実装レベルの問いから
始まった検討が、最終的に「キー入力→処理→画面表示」という単純な骨格に
収束した。この骨格を土台に、スクリーン・ビュー・コマンドマッパー・
インボーカーという4つの要素を組み合わせることで、確認ダイアログ・
検索・表示バリエーションの切り替え・外部コマンド実行など、当初挙げた
8つのユースケースすべてを、特別な例外を設けることなく説明できる。

> **後日の訂正**: 上記の「基本パターン」は`read_line`のような、Rust側が
> 複数キー入力をまとめて監視してから返す入力方式を暗黙の前提から外して
> いた。次のセクションで、この矛盾と解決策を記録する。

---

## `on_key`の戻り値による入力モード指定（`read_line`との整合性の見直し）

### 見つかった矛盾

確認ダイアログで採用した「スクリーン切り替え方式」は、**1キー入力ごとに
`on_key`が1回呼ばれ、その都度`return`する**という前提（Rust側は常に
1文字ずつキーを渡す）に立っている。

一方`read_line`は、**Rust側が内部でループし、Enter/Escapeまで複数キー
入力を監視し続けてから、まとめて確定文字列を返す**という前提に立って
いる。

検索を「削除確認と同じスクリーン切り替え方式」で書こうとすると、検索用の
入力スクリーンに切り替えた後も、Rust側は相変わらず1文字ずつしか`on_key`
を呼んでくれない。そのため`read_line`（複数キーをRustがブロッキングで
待つ関数）とは根本的に噛み合わない。

### 解決の方向性

`on_key`の**戻り値**を使って、「次にRustがどのような入力モードでキーを
待つべきか」をLua側からRustに指定できるようにする。

```lua
function on_key(key)
    -- 通常のスクリーン切り替え処理
    draw()
    return "normal"       -- 次も1文字ずつのキー入力を待ってほしい
end
```

検索スクリーンに切り替えた直後は：

```lua
function on_key(key)
    -- FindInputScreen に切り替える
    draw()
    return "line_input"   -- 次はRust側で行入力モード（read_line相当）に入ってほしい
end
```

Rust側は戻り値を見て、`"line_input"`が返ってきたら、内部で行編集ループ
（Enter/Escapeまでキーを監視し、その間は入力欄をエコー表示する）に入り、
確定した文字列を持って改めて`on_key`を呼ぶ。`"normal"`ならこれまで通り
1文字ずつ渡す。

これにより、「スクリーン切り替え方式」と「行入力（`read_line`）」は、
矛盾する2つの別方式ではなく、**Rustへの入力モード指定という1つの仕組みの
中に統合**される。`on_key`の戻り値がその都度「次のキー入力の受け方」を
宣言する、という形になる。

### Rustのメインループへの影響（正確な記録）

これまで`terminal.read_line`は「Luaからの、ただの関数呼び出し」として
説明され、その根拠として「Rustのメインループ構造自体は変わらない」ことが
挙げられていた（`fm-mode-interface-design.md`参照）。

しかし今回の解決策は、**Rustのメインループ自体に変更が必要**になる。
具体的には、今の`loop { key = read_key(); on_key(key) }`という構造が、
`on_key`の戻り値を見て次に「1文字ずつ読むか」「行入力モードで読むか」を
分岐する構造に変わる。「メインループは変わらない」という以前の前提は
誤りだったため、この場で訂正する。

これは悪いことではなく、むしろ「検索専用の特殊な関数」を1つ増やすより、
入力モードの切り替えという汎用的な仕組みに統合されている分、設計として
は筋が良いと判断している。

この仕組みの具体的なインタフェース（戻り値の型、Rust側APIの詳細）は、
まだ検討中である。
