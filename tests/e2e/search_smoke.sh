#!/usr/bin/env bash
# 実バイナリを疑似端末(pty)上で起動し、検索機能(行入力モード)が実際のRustの
# メインループ・キー入力経路で正しく動作することを確認するスモークテスト。
#
# cargo test / busted には組み込まれていない手動実行用のスクリプト。
# GNU の script(1), stty, timeout, grep が必要(Linux想定)。
#
# 実行方法: bash tests/e2e/search_smoke.sh

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
touch "$WORKDIR/alpha.txt" "$WORKDIR/beta.txt" "$WORKDIR/gamma.log"

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

# ptyのログは送信した全キー入力にわたる生バイト列であり、絞り込み前の一覧も
# 消えずに残っている。「表示されなくなったか」を確認するには、最後に描画された
# フレーム(最後のクリア以降)だけを見る必要がある
last_frame() {
    # 画面クリアシーケンス(ESC [ 2 J)以降の、最後の一塊を取り出す
    tr '\033' '\n' < "$1" | awk 'BEGIN{RS="\n"} /^\[2J/{buf=""} {buf=buf $0 "\n"} END{print buf}'
}

echo "==> '/'で検索文字列を確定すると一致するファイルだけに絞り込まれるか確認"
run_fm "$WORKDIR/confirm.log" '/alpha\rq'
frame=$(last_frame "$WORKDIR/confirm.log")
if echo "$frame" | grep -aq 'alpha.txt' && ! echo "$frame" | grep -aq 'beta.txt'; then
    echo "OK: alpha.txtだけに絞り込まれた"
else
    echo "FAIL: 検索結果の絞り込みが確認できなかった"
    fail=1
fi

echo "==> escapeで検索をキャンセルすると絞り込まれないか確認"
# escapeの直後に間隔なく次のキーが届くと、crossterm側でエスケープシーケンスの
# 一部と誤解釈されて取りこぼされることがあるため、チャンクを分けてsleepを挟む
run_fm "$WORKDIR/cancel.log" '/zzz\x1b' 'q'
frame=$(last_frame "$WORKDIR/cancel.log")
if echo "$frame" | grep -aq 'beta.txt'; then
    echo "OK: キャンセル後も全件表示のまま"
else
    echo "FAIL: キャンセルしたのに絞り込まれたままだった"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "==> 失敗したケースがあります"
    exit 1
fi

echo "==> すべて成功"
