# fm

ターミナルで動作するファイルマネージャ。

Rust と Lua の2層構造で、Rust は OS とのやり取りを行う薄いインタフェース層、
Lua がファイルマネージャとしての制御ロジックを持つ。ロジックを Lua 側に
置くことで、試作や変更をしやすくすることを狙っている。

個人的な学習・実験目的のプロジェクトで、最低限の機能を実装した段階。

## 必要環境

- Rust 1.70+ (edition 2021)
- macOS または Linux
- ファイルを開く機能で `less` / `xxd` / `grep` を利用する

## ビルドと実行

```sh
cargo build
cargo run
```

## 設定ファイル

設定ファイルの優先順位

1. 環境変数 `FM_CONFIG`
2. `~/.config/fm/config.toml`
3. 組み込みの規定値

## プロジェクト構成

```
fm/
├─ src/       Rust コード（インタフェース層）
├─ lua/       Lua コード（アプリケーション層）
├─ tests/
│  ├─ rust/  Rust の単体・結合テスト
│  ├─ lua/   Lua の単体テスト
│  └─ e2e/   実バイナリを疑似端末上で動かすスモークテスト（手動実行用）
└─ docs/      ドキュメント
```

## テスト

```sh
cargo test
busted tests/lua/
for f in tests/e2e/*.sh; do bash "$f"; done
```

Lint:

```sh
cargo clippy
luacheck lua/
```

## License

MIT License. 詳細は [LICENSE](LICENSE) を参照。
