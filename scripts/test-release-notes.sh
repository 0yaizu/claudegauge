#!/usr/bin/env bash
# scripts/release-notes.sh のテスト。使い方: scripts/test-release-notes.sh
set -u
unset GITHUB_SERVER_URL # 実行する環境に左右されないようにする

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUT="$ROOT/scripts/release-notes.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok() { pass=$((pass + 1)); }
ng() {
  fail=$((fail + 1))
  echo "FAIL: $1" >&2
}

# assert_eq 説明 期待値 実際の値
assert_eq() {
  if [[ "$2" == "$3" ]]; then ok; else ng "$1 (期待: [$2] / 実際: [$3])"; fi
}

# assert_has 説明 全文 部分文字列
assert_has() {
  if [[ "$2" == *"$3"* ]]; then ok; else ng "$1 (含まれない: [$3])"; fi
}

assert_lacks() {
  if [[ "$2" != *"$3"* ]]; then ok; else ng "$1 (含まれてはいけない: [$3])"; fi
}

# ---- validate ----
for tag in v0.1.0 pre-v0.0.2 beta-v10.20.30; do
  if "$SUT" validate "$tag" 2>/dev/null; then ok; else ng "validate が $tag を受け付けない"; fi
done
bad_tags=("" v1.2 V1.2.3 v1.2.3-rc1 "v1.2.3 " " v1.2.3" "pre-v1.2.3;id" "x/../v1.2.3" 'v1.2.3
' 'v1.2.3
v9.9.9' "pre-1.2.3" "vv1.2.3" "v1.2.3.4" "rc-v1.2.3")
for tag in "${bad_tags[@]}"; do
  if "$SUT" validate "$tag" 2>/dev/null; then ng "validate が不正なタグを受け付けた: [$tag]"; else ok; fi
done

# ---- channel ----
assert_eq "channel: v は stable" "stable" "$("$SUT" channel v0.1.0)"
assert_eq "channel: pre-v は preview" "preview" "$("$SUT" channel pre-v0.0.2)"
assert_eq "channel: beta-v は preview" "preview" "$("$SUT" channel beta-v0.0.2)"

# ---- prev-tag ----
REPO_DIR="$WORK/repo"
mkdir "$REPO_DIR"
(
  cd "$REPO_DIR" || exit 1
  git init -q -b main
  git config user.name test
  git config user.email test@example.invalid
  git config commit.gpgsign false
  git config tag.gpgsign false
  commit_at() { # 日付 メッセージ
    GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git commit -q --allow-empty -m "$2"
  }
  commit_at "2026-01-01T00:00:00Z" c1
  git tag v0.1.0
  commit_at "2026-02-01T00:00:00Z" c2
  git tag pre-v0.1.1
  git tag not-a-release
  git tag v0.1.2-rc1
  commit_at "2026-03-01T00:00:00Z" c3
  git tag beta-v0.2.0
  # main に含まれない枝のタグは対象外
  git switch -q -c side
  commit_at "2026-04-01T00:00:00Z" side
  git tag v9.9.9
  git switch -q main
  commit_at "2026-05-01T00:00:00Z" c4
)
assert_eq "prev-tag: 直近のリリースタグ" "beta-v0.2.0" "$(cd "$REPO_DIR" && "$SUT" prev-tag v0.3.0)"
assert_eq "prev-tag: 対象タグ自身は除く" "pre-v0.1.1" "$(cd "$REPO_DIR" && "$SUT" prev-tag beta-v0.2.0)"
# 同じコミットに複数のタグがあるときは、タグ名の降順 (v、pre-v、beta-v の順)
TIE_DIR="$WORK/tie"
mkdir "$TIE_DIR"
(
  cd "$TIE_DIR" || exit 1
  git init -q -b main
  git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m one
  git tag beta-v0.0.9
  git tag pre-v0.2.0
  git tag v0.1.0
  git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m two
)
assert_eq "prev-tag: 同じコミットなら v が先" "v0.1.0" "$(cd "$TIE_DIR" && "$SUT" prev-tag v0.3.0)"

# ---- changes ----
(
  cd "$REPO_DIR" || exit 1
  mkdir -p Sources docs
  echo "hello-sources" >Sources/a.txt
  echo "secret-docs" >docs/other.md
  git add -A
  GIT_AUTHOR_DATE="2026-06-01T00:00:00Z" GIT_COMMITTER_DATE="2026-06-01T00:00:00Z" \
    git commit -q -m "feat: ソースを足した"
)
changes="$(cd "$REPO_DIR" && "$SUT" changes beta-v0.2.0)"
assert_has "changes: コミット一覧" "$changes" "feat: ソースを足した"
assert_eq "changes: 直前より前のコミット (c3) は含まない" "0" "$(printf '%s\n' "$changes" | grep -c ' c3$' || true)"
assert_eq "changes: 直前より後のコミット (c4) は含む" "1" "$(printf '%s\n' "$changes" | grep -c ' c4$' || true)"
assert_has "changes: Sources の差分を含む" "$changes" "+hello-sources"
assert_lacks "changes: docs の中身は含まない" "$changes" "+secret-docs"
assert_lacks "changes: 直前がなければ差分を出さない" "$(cd "$REPO_DIR" && "$SUT" changes "")" "## 差分"
if (cd "$REPO_DIR" && "$SUT" changes "bad tag" >/dev/null 2>&1); then
  ng "changes が不正な直前のタグを受け付けた"; else ok; fi
(
  cd "$REPO_DIR" || exit 1
  awk 'BEGIN { for (i = 0; i < 20000; i++) print "line-" i "-xxxxxxxxxxxx" }' >Sources/big.txt
  git add -A
  git commit -q -m "big"
)
big="$(cd "$REPO_DIR" && "$SUT" changes beta-v0.2.0)"
assert_has "changes: 長いときは切る" "$big" "長いので、ここで切りました"
if [[ "${#big}" -le 30100 ]]; then ok; else ng "changes: 長さの上限 (${#big})"; fi

EMPTY_DIR="$WORK/empty"
mkdir "$EMPTY_DIR"
(cd "$EMPTY_DIR" && git init -q -b main && git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m init)
assert_eq "prev-tag: タグがなければ空" "" "$(cd "$EMPTY_DIR" && "$SUT" prev-tag v0.1.0)"

# ---- highlights ----
hl() { printf '%s' "$1" | "$SUT" highlights; }

out="$(hl '{"highlights":[{"kind":"feature","text":"新機能A"},{"kind":"fix","text":"不具合B"},{"kind":"docs","text":"文書C"}]}')"
assert_eq "highlights: 種類ごとの絵文字" "- ✨ 新機能A
- 🐛 不具合B
- 📝 文書C" "$out"

out="$(hl '{"highlights":[{"kind":"feature","text":"一行目\n二行目\t三行目"}]}')"
assert_eq "highlights: 改行とタブは空白 1 つにする" "- ✨ 一行目 二行目 三行目" "$out"

out="$(hl '{"highlights":[{"kind":"fix","text":"@someone さんに感謝"}]}')"
assert_lacks "highlights: @ メンションを無効にする" "$out" "@someone"
assert_has "highlights: @ は全角にする" "$out" "＠someone"

long="$(printf 'あ%.0s' $(seq 1 300))"
out="$(hl "{\"highlights\":[{\"kind\":\"fix\",\"text\":\"$long\"}]}")"
line_len=$(printf '%s' "$out" | jq -Rs length)
assert_eq "highlights: 長い文を切り詰める (接頭辞 4 文字 + 200 文字)" "204" "$line_len"

out="$(hl '{"highlights":[{"kind":"fix","text":"見​え‮ない⁦文字"}]}')"
assert_eq "highlights: 見えない制御文字を取り除く" "- 🐛 見えない文字" "$out"

out="$(hl '{"highlights":[{"kind":"fix","text":"[詳細](https://example.invalid/x) と `コード` と <b>太字</b>"}]}')"
assert_eq "highlights: リンクや HTML になる記号を取り除く" "- 🐛 詳細(https：//example.invalid/x) と コード と b太字/b" "$out"

# 取り除いた結果、://  が組み上がる入力でも、URL にならない
out="$(hl '{"highlights":[{"kind":"fix","text":"https::////evil.invalid と http:[]//x と http:​//y"}]}')"
assert_lacks "highlights: 組み上がった :// も残さない" "$out" "://"

assert_eq "highlights: 項目がすべて不正なら生成失敗の扱い" \
  "- ⚠️ ハイライトを自動で作れませんでした。公開する前に、ここへ手で書いてください。" \
  "$(hl '{"highlights":[{"kind":"other","text":"x"},{"kind":"fix"}]}')"

out="$(hl '{"highlights":[{"kind":"other","text":"種類が不明"},{"kind":"fix","text":"残る"}]}')"
assert_eq "highlights: 不明な種類は捨てる" "- 🐛 残る" "$out"

many='{"highlights":['
for i in 1 2 3 4 5 6 7 8 9 10; do many="$many{\"kind\":\"fix\",\"text\":\"項目$i\"},"; done
many="${many%,}]}"
count="$(hl "$many" | grep -c '^- ')"
assert_eq "highlights: 最大 8 件" "8" "$count"

out="$(hl '{"highlights":[{"kind":"fix","text":"{{TAG}} と {{COMPARE_LINK}}"}]}')"
assert_has "highlights: テンプレートの記号はそのまま通す" "$out" "{{TAG}} と {{COMPARE_LINK}}"

assert_eq "highlights: 空配列" "- 利用者に見える変更はありません。" "$(hl '{"highlights":[]}')"
assert_eq "highlights: 空文字は生成失敗の扱い" \
  "- ⚠️ ハイライトを自動で作れませんでした。公開する前に、ここへ手で書いてください。" "$(hl '')"
assert_eq "highlights: 壊れた JSON は生成失敗の扱い" \
  "- ⚠️ ハイライトを自動で作れませんでした。公開する前に、ここへ手で書いてください。" "$(hl '{not json')"
assert_eq "highlights: 形が違う JSON は生成失敗の扱い" \
  "- ⚠️ ハイライトを自動で作れませんでした。公開する前に、ここへ手で書いてください。" "$(hl '{"other":1}')"

# ---- render ----
printf -- '- ✨ 見出しの項目\n- 🐛 修正の項目\n' >"$WORK/hl.md"

stable="$("$SUT" render v0.1.0 pre-v0.0.1 0yaizu/claudegauge "$WORK/hl.md")"
assert_has "render(stable): 見出し" "$stable" "# ClaudeGauge — v0.1.0"
assert_has "render(stable): バージョンのバッジ" "$stable" "badge/version-v0.1.0-ff6b6b"
assert_has "render(stable): 状態のバッジ" "$stable" "badge/status-stable-4fc08d"
assert_has "render(stable): 配布ファイル名" "$stable" "ClaudeGauge-v0.1.0.zip"
assert_has "render(stable): 差分のリンク" "$stable" "https://github.com/0yaizu/claudegauge/compare/pre-v0.0.1...v0.1.0"
assert_has "render(stable): ハイライト" "$stable" "- ✨ 見出しの項目
- 🐛 修正の項目"
assert_lacks "render(stable): 警告を出さない" "$stable" "[!WARNING]"
assert_lacks "render(stable): 置き換え漏れがない" "$stable" "{{"

pre="$("$SUT" render pre-v0.0.2 pre-v0.0.1 0yaizu/claudegauge "$WORK/hl.md")"
assert_has "render(pre): バッジの - は 2 つにする" "$pre" "badge/version-pre--v0.0.2-ff6b6b"
assert_has "render(pre): 状態のバッジ" "$pre" "badge/status-pre--release-orange"
assert_has "render(pre): 警告を出す" "$pre" "> [!WARNING]"
assert_lacks "render(pre): 置き換え漏れがない" "$pre" "{{"

ghe="$(GITHUB_SERVER_URL=https://ghe.example.invalid "$SUT" render v0.1.0 pre-v0.0.1 0yaizu/claudegauge "$WORK/hl.md")"
assert_has "render: GITHUB_SERVER_URL を使う" "$ghe" "https://ghe.example.invalid/0yaizu/claudegauge/compare/pre-v0.0.1...v0.1.0"

first="$("$SUT" render v0.1.0 "" 0yaizu/claudegauge "$WORK/hl.md")"
assert_has "render(初回): 直前がなければコミット一覧へ" "$first" "https://github.com/0yaizu/claudegauge/commits/v0.1.0"

# ハイライトに & や \ や {{ }} が入っても、そのまま出る
printf -- '- 🐛 A & B \\1 {{TAG}}\n' >"$WORK/hl-special.md"
special="$("$SUT" render v0.1.0 "" 0yaizu/claudegauge "$WORK/hl-special.md")"
assert_has "render: 特殊文字をそのまま出す" "$special" '- 🐛 A & B \1 {{TAG}}'

if "$SUT" render "v1.2" "" 0yaizu/claudegauge "$WORK/hl.md" >/dev/null 2>&1; then
  ng "render が不正なタグを受け付けた"; else ok; fi
if "$SUT" render v0.1.0 "bad tag" 0yaizu/claudegauge "$WORK/hl.md" >/dev/null 2>&1; then
  ng "render が不正な直前のタグを受け付けた"; else ok; fi
if "$SUT" render v0.1.0 "" "0yaizu/claudegauge/extra" "$WORK/hl.md" >/dev/null 2>&1; then
  ng "render が不正なリポジトリ名を受け付けた"; else ok; fi

echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
