#!/usr/bin/env bash
# リリースノートを組み立てる補助。draft-release.yml から呼ぶ。
#
#   release-notes.sh validate TAG                      タグ名の形を検査する
#   release-notes.sh channel TAG                       stable か preview を出力する
#   release-notes.sh prev-tag TAG                      直前のリリースタグを出力する (なければ空)
#   release-notes.sh changes PREV_TAG                  直前から HEAD までの変更の材料を出力する
#   release-notes.sh highlights                        標準入力の JSON から、ハイライトの箇条書きを出力する
#   release-notes.sh render TAG PREV_TAG REPO FILE     雛形に値を入れて、リリースノート全体を出力する
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ROOT/.github/release-notes-template.md"
NOTICE="$ROOT/.github/release-notes-preview-notice.md"

TAG_RE='^(v|pre-v|beta-v)[0-9]+\.[0-9]+\.[0-9]+$'
REPO_RE='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'

MAX_HIGHLIGHTS=8
MAX_TEXT_LENGTH=200
# プロンプトは環境変数で渡る (Linux では 1 つ 128KiB まで)。日本語は 1 文字 3 バイトなので、余裕を見て 3 万字。
MAX_CHANGES_LENGTH=30000
FAILED_LINE='- ⚠️ ハイライトを自動で作れませんでした。公開する前に、ここへ手で書いてください。'
NONE_LINE='- 利用者に見える変更はありません。'

die() {
  echo "$*" >&2
  exit 1
}

is_tag() { [[ "${1-}" =~ $TAG_RE ]]; }

cmd_validate() {
  is_tag "${1-}" || die "タグ名は v1.2.3 / pre-v1.2.3 / beta-v1.2.3 の形にしてください: ${1-}"
}

cmd_channel() {
  cmd_validate "${1-}"
  case "$1" in
    v*) echo stable ;;
    *) echo preview ;;
  esac
}

cmd_prev_tag() {
  local tag="${1-}" t list
  cmd_validate "$tag"
  # 作成日が新しい順 (同じ時刻なら、タグ名の降順で v、pre-v、beta-v の順)。HEAD から辿れるタグだけを見る。
  # 出力を先に変数へ取るので、git が失敗したときは、そのまま失敗にする。
  list="$(git tag --list 'v[0-9]*' 'pre-v[0-9]*' 'beta-v[0-9]*' --merged HEAD \
    --sort=-version:refname --sort=-creatordate)"
  while IFS= read -r t; do
    [[ "$t" == "$tag" ]] && continue
    is_tag "$t" || continue
    echo "$t"
    break
  done <<<"$list"
}

# 直前のリリースから HEAD までの変更の材料 (コミット一覧と差分) を出力する。
# Claude にはツールを渡さず、この出力だけを読ませる。
cmd_changes() {
  local prev="${1-}" out
  if [[ -n "$prev" ]] && ! is_tag "$prev"; then
    die "直前のタグの形が正しくありません: $prev"
  fi
  if [[ -n "$prev" ]]; then
    out="$(
      echo '## コミット (git log --oneline)'
      git log --oneline --no-decorate "$prev..HEAD"
      echo
      echo '## 変更したファイル (git diff --stat)'
      git diff --no-ext-diff --no-textconv --stat "$prev..HEAD"
      echo
      echo '## 差分 (Sources と README.md)'
      git diff --no-ext-diff --no-textconv "$prev..HEAD" -- Sources README.md
    )"
  else
    out="$(
      echo '## コミット (git log --oneline)'
      git log --oneline --no-decorate
    )"
  fi
  if [[ "${#out}" -gt "$MAX_CHANGES_LENGTH" ]]; then
    out="${out:0:$MAX_CHANGES_LENGTH}
(長いので、ここで切りました)"
  fi
  printf '%s\n' "$out"
}

# 標準入力の JSON {"highlights":[{"kind":"feature|fix|docs","text":"..."}]} を箇条書きにする。
# モデルの出力は信用せず、種類は絵文字に対応づけ、文は 1 行に整えて長さを切る。
# 文からは、Markdown のリンクや HTML になる記号 ([ ] < > `) と、
# 見えない制御文字 (ゼロ幅の文字や向きを変える文字) を取り除く。
# URL の :// は全角のコロンに置き換え (取り除くと、残りの文字がつながって ://  に戻るため)、@ も全角にする。
# 公開の前に、人がドラフトを読む前提なので、これ以上の検査はしない。
cmd_highlights() {
  local json lines
  json="$(cat)"
  if [[ -z "${json//[[:space:]]/}" ]]; then
    echo "$FAILED_LINE"
    return 0
  fi
  # shellcheck disable=SC2016
  if ! lines="$(
    printf '%s' "$json" | jq -r \
      --argjson max "$MAX_HIGHLIGHTS" --argjson len "$MAX_TEXT_LENGTH" '
      if (type == "object") and ((.highlights | type) == "array") then
        ([.highlights[]
          | select(type == "object" and (.kind | type) == "string" and (.text | type) == "string")
          | ({"feature": "✨", "fix": "🐛", "docs": "📝"}[.kind]) as $emoji
          | select($emoji != null)
          | (.text | gsub("[\\p{Cf}\\[\\]<>`]"; "") | gsub("://"; "：//") | gsub("[\\p{Cc}\\s]+"; " ") | gsub("@"; "＠") | sub("^ "; "") | sub(" $"; "") | .[:$len]) as $text
          | select($text != "")
          | "- \($emoji) \($text)"
        ]) as $items
        | if ($items | length) == 0 and (.highlights | length) > 0 then error("有効な項目がない")
          else $items[:$max][] end
      else error("形が違う") end' 2>/dev/null
  )"; then
    echo "$FAILED_LINE"
    return 0
  fi
  if [[ -z "$lines" ]]; then
    echo "$NONE_LINE"
  else
    echo "$lines"
  fi
}

# TEMPLATE を 1 行ずつ読み、{{KEY}} を値に置き換える。
# 値は環境変数から渡す (awk の -v だと \ が解釈されるため)。
# 複数行の値は、記号だけの行を丸ごと置き換え、値の中の {{ }} は再び置き換えない。
cmd_render() {
  local tag="${1-}" prev="${2-}" repo="${3-}" hl_file="${4-}"
  cmd_validate "$tag"
  if [[ -n "$prev" ]] && ! is_tag "$prev"; then
    die "直前のタグの形が正しくありません: $prev"
  fi
  [[ "$repo" =~ $REPO_RE ]] || die "リポジトリ名の形が正しくありません: $repo"
  [[ -r "$hl_file" ]] || die "ハイライトのファイルを読めません: $hl_file"

  local server="${GITHUB_SERVER_URL:-https://github.com}" channel status compare notice=""
  channel="$(cmd_channel "$tag")"
  if [[ "$channel" == stable ]]; then
    status='stable-4fc08d'
  else
    status='pre--release-orange'
    notice="$(cat "$NOTICE")"
  fi
  if [[ -n "$prev" ]]; then
    compare="$server/$repo/compare/$prev...$tag"
  else
    compare="$server/$repo/commits/$tag"
  fi

  R_TAG="$tag" R_TAG_BADGE="${tag//-/--}" R_STATUS_BADGE="$status" R_COMPARE_LINK="$compare" \
    R_PREVIEW_NOTICE="$notice" R_HIGHLIGHTS="$(cat "$hl_file")" \
    awk '
      function repl(s, key, val,   i, out) {
        out = ""
        while ((i = index(s, key)) > 0) {
          out = out substr(s, 1, i - 1) val
          s = substr(s, i + length(key))
        }
        return out s
      }
      $0 == "{{PREVIEW_NOTICE}}" { print ENVIRON["R_PREVIEW_NOTICE"]; next }
      $0 == "{{HIGHLIGHTS}}"     { print ENVIRON["R_HIGHLIGHTS"]; next }
      {
        line = $0
        line = repl(line, "{{TAG_BADGE}}", ENVIRON["R_TAG_BADGE"])
        line = repl(line, "{{STATUS_BADGE}}", ENVIRON["R_STATUS_BADGE"])
        line = repl(line, "{{COMPARE_LINK}}", ENVIRON["R_COMPARE_LINK"])
        line = repl(line, "{{TAG}}", ENVIRON["R_TAG"])
        print line
      }
    ' "$TEMPLATE"
}

main() {
  local cmd="${1-}"
  [[ $# -gt 0 ]] && shift
  case "$cmd" in
    validate) cmd_validate "$@" ;;
    channel) cmd_channel "$@" ;;
    prev-tag) cmd_prev_tag "$@" ;;
    changes) cmd_changes "$@" ;;
    highlights) cmd_highlights ;;
    render) cmd_render "$@" ;;
    *) die "使い方: $0 validate|channel|prev-tag|changes|highlights|render ..." ;;
  esac
}

main "$@"
