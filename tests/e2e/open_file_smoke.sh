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
#
# run_fm: 引数(log以外)をキー入力のまとまり(chunk)として順に送り込み、
# 疑似端末の画面をlogに記録する。各chunkの間、および最初のchunkを送る前には
# 自動でsleepが挟まる。呼び出し側はsleepやprintfの書き方を意識しなくてよい。
#
# sleepが必要な理由:
# - 最初: fmがenable_raw_mode()する前にキーが届くと、rawバイトが疑似端末の
#   cookedモード処理で化ける(例: \r が \n になる)
# - chunkの間: lessなど別プロセスの終了処理とfm本体の入力再開が競合し、
#   キーを取りこぼすことがある
STARTUP_DELAY=1.5
CHUNK_DELAY=0.5

run_fm() {
    local log="$1"
    shift
    (
        cd "$WORKDIR"
        (
            sleep "$STARTUP_DELAY"
            for chunk in "$@"; do
                printf '%b' "$chunk"
                sleep "$CHUNK_DELAY"
            done
        ) | timeout 8 script -qec "stty rows 24 cols 80; TERM=xterm '$BIN'" "$log" \
            >/dev/null 2>&1
    )
}

fail=0

echo "==> テキストファイル(a_text.txt)をlessで開けるか確認"
run_fm "$WORKDIR/text.log" 'jj\rq' 'q'
if grep -aq 'hello world' "$WORKDIR/text.log"; then
    echo "OK: lessでテキスト内容が表示された"
else
    echo "FAIL: テキスト内容が見つからなかった"
    fail=1
fi

echo "==> バイナリファイル(b_binary.bin)をxxd経由でlessに表示できるか確認"
run_fm "$WORKDIR/binary.log" 'jjj\rq' 'q'
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
