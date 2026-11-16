# リリースの運用

ClaudeGaugeのリリースは、GitHub Actionsで行います。
流れは、ドラフトのリリースを作り、人が確かめて公開し、公開をきっかけにビルドと添付が動く、というものです。
判断の理由は`docs/decisions.md`にあります。

## タグの名前

| 種類 | 形 | 例 |
| --- | --- | --- |
| 安定版 | `v1.2.3` | `v0.1.0` |
| プレビュー版 | `pre-v1.2.3`、`beta-v1.2.3` | `pre-v0.0.2` |

「プレビュー版」と呼びます(「先行版」とは呼びません)。プレビュー版は、GitHubのpre-releaseとして作られます。
形が正規表現`^(v|pre-v|beta-v)[0-9]+\.[0-9]+\.[0-9]+$`に合うかは、`release.yml`、`draft-release.yml`、`scripts/release-notes.sh`が、それぞれ検査します。

## リリースの手順

1. 出したい内容が、`main`に入っていることを確かめます。CIが通っていることも見ます。
2. Actionsタブで`Draft release`を選び、「Run workflow」を押します。入力欄`tag`に、タグ名を書きます(自由入力です)。ブランチは`main`にします。
3. ワークフローが、ドラフトのリリースを作ります。実行ログの「Summary」にも、組み立てたリリースノートが出ます。
4. Releasesの画面で、ドラフトを開き、内容を確かめて、必要なら直します。ハイライトが「自動で作れませんでした」の1行になっているときは、ここで手で書きます。
5. 「Publish release」を押します。この時点で、タグが、ドラフトを作った時点の`main`の先頭のコミットに作られます(タグを作れるのは、保護の例外にあたる権限を持つ人だけです)。
6. `release.yml`が動き、ビルドして、`ClaudeGauge-<タグ>.zip`と`.sha256`を添付します。数分かかります。完了したら、Assetsを確かめます。

作ったドラフトを使わないときは、Releasesの画面から、ドラフトを削除します。ドラフトの段階では、タグはできていません。

## ワークフロー

### `ci.yml`

`main`へのpush、PR、手動で動きます。macOS(`macos-26`)では`swift test`とリリースノート用スクリプトのテストを、ubuntu(`ubuntu-24.04`)ではスクリプトのテストを動かします。ubuntuでも動かすのは、`draft-release.yml`が動く環境と、同じにするためです。

### `draft-release.yml`

手動で動きます(`workflow_dispatch`)。2つのjobに分かれています。

- `highlights`: `main`のときだけ動きます。環境`release-notes`を使い、Claudeのトークンを持つのは、このjobだけです。権限は`contents: read`だけです。
  1. タグの形を検査し、同名のタグがないことを確かめ、直前のリリースのタグを探します。
  2. `scripts/release-notes.sh changes`で、直前のリリースから`HEAD`までの変更の材料を集めます。コミット一覧、変更したファイル、`Sources`と`README.md`の差分です。3万字で切ります。
  3. 作業フォルダを空にして、リポジトリ内のClaude向けの設定を読ませません。
  4. `anthropics/claude-code-action`で、Haiku(`claude-haiku-5-5`)に、ハイライトを書かせます。ツールは渡しません。結果は、JSON Schemaで形を決めた構造化出力で受け取ります。
  5. このステップは、`continue-on-error: true`です。失敗しても、ドラフトは作られます。
- `draft`: `highlights`が成功したときに動きます。書き込みの権限(`contents: write`)を持ちますが、Claudeのトークンは持ちません。
  1. タグの検査を、もう一度行います。同名のタグと、同名のリリース(ドラフトを含む)がないことを確かめます。GitHubのAPIが、404以外のエラーを返したときは、失敗にします。
  2. モデルの出力を、`release-notes.sh highlights`で整えます。種類は絵文字に対応づけ、文は1行にして200字で切り、見えない制御文字とMarkdownのリンクやタグになる記号を取り除き、`@`と`://`は全角の文字に置き換えます。最大8件です。
  3. `release-notes.sh render`で、雛形に差し込みます。
  4. `gh release create --draft --target <コミット> --title <タグ>`でドラフトを作ります。プレビュー版には`--prerelease`を付けます。

### `release.yml`

リリースを公開したとき(`release: published`)に動きます。

1. タグの形を検査し、バージョンを決めます。
2. 対象のコミットが、`main`の履歴に含まれることを確かめます。
3. `swift test`、`scripts/bundle.sh`(`VERSION`を渡す)でビルドします。
4. `lipo -archs`が`arm64`だけであることを確かめます。
5. `ditto`でzipを作り、`shasum -a 256`でチェックサムを作ります。zipを展開して、署名が有効なことを確かめます。
6. `actions/attest`で、ビルドの由来の証明(attestation)を付けます。
7. `gh release upload --clobber`で、リリースに添付します。同名のファイルは上書きします。
8. 安定版(`v1.2.3`の形)のときだけ、`notify-tap`ジョブが、Homebrewのtap(`0yaizu/homebrew-tap`)の`bump.yml`を起動します。tapは、最新の安定版を自分で調べ、zipの由来の証明(attestation)を検証して、caskの`version`と`sha256`を更新します(詳細は後述の`notify-tap`)。プレビュー版では動きません。

### `notify-tap`(`release.yml`のジョブ)

`build`の完了後に、安定版のときだけ動きます。環境`tap-dispatch`の秘密`TAP_DISPATCH_TOKEN`(`0yaizu/homebrew-tap`だけを対象にした、`Actions: Read and write`のfine-grained PAT)で、`gh workflow run bump.yml`を呼びます。何も渡しません。
環境`tap-dispatch`は、`v[0-9]*`のタグから動くジョブだけに限っています。`pre-v`、`beta-v`のタグでは、環境に入れず、ジョブは動きません(条件で、そもそも起動しません)。
トークンの有効期限は1年までなので、切れる前に作り直して、`gh secret set TAP_DISPATCH_TOKEN --env tap-dispatch --repo 0yaizu/claudegauge`で登録し直します。

### `dependabot.yml`

アクションの更新を、週に1回、提案します(公開から7日たったものだけ)。

## リリースノートの雛形

`.github/release-notes-template.md`に、次の記号を書いてあります。`scripts/release-notes.sh render`が、値を入れます。

| 記号 | 入る値 |
| --- | --- |
| `{{TAG}}` | タグ名 |
| `{{TAG_BADGE}}` | タグ名。バッジに使うため、`-`を2つにします(`pre--v0.0.2`) |
| `{{STATUS_BADGE}}` | 安定版は`stable-4fc08d`、プレビュー版は`pre--release-orange` |
| `{{PREVIEW_NOTICE}}` | プレビュー版だけ、`.github/release-notes-preview-notice.md`の警告 |
| `{{HIGHLIGHTS}}` | ハイライトの箇条書き |
| `{{COMPARE_LINK}}` | 直前のタグとの比較のリンク。直前がなければ、コミット一覧のリンク |

ハイライトの文面の決まりは、`draft-release.yml`のプロンプトにあります。使う人に見える変更だけを、3〜5件(最大8件)、「〜しました」の形で、短くわかりやすく書かせます。見える変更が1つもなければ、「軽微な修正をしました。」の1行になります。生成に失敗したときは、「ハイライトを自動で作れませんでした。公開する前に、ここへ手で書いてください。」の1行になります。

直前のリリースは、`main`の履歴から辿れる最新のタグです。接頭語は問いません。同じコミットに複数あるときは、タグ名の降順(`v`、`pre-v`、`beta-v`)です。

## 初めての設定

### 環境`release-notes`

Settings → Environments → New environmentで、`release-notes`を作ります。「Deployment branches and tags」は「Selected branches and tags」にして、`main`のブランチだけを許可します。秘密の登録先は、リポジトリ全体ではなく、この環境です。環境の秘密は、`environment: release-notes`を宣言した、`main`上のjobだけが読めます。

### Claudeのトークン

1. ユーザー自身のターミナルで、`claude setup-token`を実行します。ProまたはMaxの購読が要ります。長期のトークンが、一度だけ表示されます。
2. 次のコマンドで、環境の秘密として登録します。値は、聞かれたときに貼ります。`--body`で値を渡すと、シェルの履歴に残るので、使いません。
   ```sh
   gh secret set CLAUDE_CODE_OAUTH_TOKEN --env release-notes --repo 0yaizu/claudegauge
   ```
3. 表示されたトークンは、画面とクリップボードから消します。

このトークンの使用量は、ユーザーの購読の枠から引かれます。AIエージェントは、トークンの値を扱いません。チャットに貼るよう頼むこともしません。

### タグの保護(ルールセット)

タグの名前`v[0-9]*`、`pre-v[0-9]*`、`beta-v[0-9]*`の、作成、更新、削除、強制pushを、ルールセットで禁じています。例外は、保護の例外に指定した権限だけです。このため、`GITHUB_TOKEN`ではタグを作れません。`main`にも、ルールセットがあります。環境の「`main`だけ」という制限は、`main`の保護を前提にしています。

## 注意

- 「Immutable releases」は、オフのままにします(`docs/decisions.md`)。
- ワークフローを変えるときは、`GITHUB_TOKEN`の権限を、必要な最小にします。外から来る値(タグの入力、コミットのメッセージ、モデルの出力)は、`run:`に直接埋め込まず、環境変数で渡します。
- アクションを足すときは、コミットのSHAで固定します。
- `claude_args`は、`claude-code-action`の解析を通ります。空文字の値や、括弧を含む値は、変わることがあります。変えたときは、ローカルの`claude -p`か、実行ログで、意図どおりに渡っているかを確かめます。
- プロンプトは、環境変数として渡るので、Linuxでは1つ約128KiBの上限があります。材料の上限は、これを超えないよう、3万字にしています(`scripts/release-notes.sh`の`MAX_CHANGES_LENGTH`)。
