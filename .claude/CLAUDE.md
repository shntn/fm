## Project

fm - ターミナルのファイルマネージャ

## Stack

* Rust : 1.70+ (edition 2021)
* mlua : 0.10 (feature = "lua54")
* crossterm : 0.28
* Deployed on macOS and Linux

## Structure

* src/ - Rust コード
* lua/ - Lua スクリプト
* tests/ - テストコード
* target/ - ビルド時に生成されるファイル

## Commands

* Build: `cargo build`
* Run: `cargo run`
* Test:
  - Rust: `cargo test`
  - Lua: `busted tests/lua/`
* Lint:
  - Rust: `carog clippy`
  - Lua: `luacheck lua/` or `luacheck tests/lua/`

## Verification

変更を加えるたびに、以下の順序で実行してください。 

1. `cargo check` - タイプエラーを修正する 
2. `cargo test` - 失敗したテストを修正する
3. `busted tests/lua/` - 失敗したテストを修正する
4. `cargo clippy` - Lintエラーを修正する
5. `luacheck lua/` - Lintエラーを修正する

## Conventions


## Don't


## Preferences

* Git にコミットする前に確認してください
* 新規ファイルを作成するよりも、既存ファイルを編集することを優先してください 
* 変更を加えた後はテストを実行してください
* コードはシンプルに保つ - 過剰な設計は避ける
* 不要なコメントやドキュメント文字列は含めない

## Workflow

* 物事がうまくいかなくなったら、立ち止まって計画を練り直しましょう。無理に押し進めてはいけません
* タスク完了と宣言する前に、型チェック、テスト、リンティングを実行します

## Style

* 小規模で、特定の機能に特化したものを好む 
* ネストされた条件式よりも早期リターンを使用する 
