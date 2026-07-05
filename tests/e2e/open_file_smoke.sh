#!/usr/bin/env bash
# 実バイナリを疑似端末(pty)上で起動し、ファイルを選択したときに
# less / xxd 経由で正しく内容が表示されることを確認するスモークテスト。
#
# cargo test / busted には組み込まれていない手動実行用のスクリプト。
# GNU の script(1), stty, xxd, less, timeout, grep が必要(Linux想定)。
#
# 実行方法: bash tests/e2e/open_file_smoke.sh

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BIN="$REPO_ROOT/target/debug/fm"

WORKDIR=$(mktemp -d)
cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "==> cargo build"
(cd "$REPO_ROOT" && cargo build) >/dev/null

echo "==> 作業ディレクトリを準備: $WORKDIR"
cp -r "$REPO_ROOT/lua" "$WORKDIR/lua"
printf 'hello world\n' > "$WORKDIR/a_text.txt"
# NULバイトを含む、確実にバイナリと判定されるファイル
printf '\x00\x01\x02\xff\x00\xfe\x00binarydata' > "$WORKDIR/b_binary.bin"

# ディレクトリ一覧の並び順: [.., lua/, a_text.txt, b_binary.bin]
# キー入力の間には、rawモード設定前の取りこぼしを避けるためsleepを挟む。
run_fm() {
    local keys="$1"
    local log="$2"
    (
        cd "$WORKDIR"
        eval "$keys" | timeout 8 script -qec "stty rows 24 cols 80; TERM=xterm '$BIN'" "$log" \
            >/dev/null 2>&1
    )
}

fail=0

echo "==> テキストファイル(a_text.txt)をlessで開けるか確認"
run_fm 'sleep 1.5; printf "jj"; sleep 0.5; printf "\r"; sleep 1; printf "q"; sleep 0.5; printf "q"' \
    "$WORKDIR/text.log"
if grep -aq 'hello world' "$WORKDIR/text.log"; then
    echo "OK: lessでテキスト内容が表示された"
else
    echo "FAIL: テキスト内容が見つからなかった"
    fail=1
fi

echo "==> バイナリファイル(b_binary.bin)をxxd経由でlessに表示できるか確認"
run_fm 'sleep 1.5; printf "jjj"; sleep 0.5; printf "\r"; sleep 1; printf "q"; sleep 0.5; printf "q"' \
    "$WORKDIR/binary.log"
if grep -aoE '[0-9a-f]{8}: ' "$WORKDIR/binary.log" | head -1 >/dev/null; then
    echo "OK: xxdのダンプがlessに表示された"
else
    echo "FAIL: xxdのダンプが見つからなかった"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "==> 失敗したケースがあります"
    exit 1
fi

echo "==> すべて成功"
