# ClaudeGauge開発ガイド(AIエージェント向け)

このファイルは、このリポジトリで作業するAIエージェントとコントリビューターが、最初に読む文書です。
作業の前提、守る決まり、コードの配置構造について記載されています。
判断の理由は`docs/decisions.md`、リリースの運用は`docs/release.md`にあります。現在の状況と未決事項は、手元だけのメモ`docs/status.md`にあります。このメモはGitに含めないので、ない環境では、ユーザーに聞いてください。

## このプロジェクト

ClaudeGaugeは、Claudeのサブスクリプションの使用状況(5時間のセッションや週間の上限)を、macOSのメニューバーに表示する個人開発のアプリです。
使用率とリセット時刻に加えて、今のペースが続いた場合の予測を出します。

- リポジトリ: https://github.com/0yaizu/claudegauge(公開、MIT)
- 対象: Apple Silicon、macOS26以降。Intel Macは対象外です。
- バンドルID: `io.github.0yaizu.ClaudeGauge`。Dockには出ません(`LSUIElement`)。
- 言語: アプリの表示は英語です。READMEと`docs/`の文書は日本語です。ユーザーとのやり取りも日本語で行います。
- Windows版を、`windows/`で作っています(初期段階です)。挙動の決まりは`docs/spec.md`に書き、macOS版とWindows版で共有します。`ClaudeGaugeCore`は画面に依存させません。

## 絶対に守ること

### 認証情報

- トークンの更新(refresh)はしません。refreshTokenは、読まず、使わず、保存しません。別のアプリから更新すると、Claude Codeが持つトークンを無効にするおそれがあるためです。
- 使うのは、`claudeAiOauth.accessToken`と`expiresAt`だけです。同じKeychain項目にある、他のMCPサーバーの認証情報(`mcpOAuth`)は、型に読み込まず、ログにも保存にも使いません。
- トークンはメモリにもディスクにも残さず、取得のたびにKeychainから読みます。
- エラーやログに、APIのレスポンスの本文やトークンを入れません。
- 詳しい決まりは`docs/spec.md`の2章にあります。

### 非公式のエンドポイント

使用状況の取得に使う`GET https://api.anthropic.com/api/oauth/usage`は、非公式で、仕様が公開されていません。予告なく変わることがあります。Claude Codeのトークンを別のアプリから使うことが、Anthropicの利用規約で制限されている可能性もあります。

- READMEの警告(非公式、自己責任)を消したり弱めたりしません。
- 本物のトークンでAPIを呼んで確かめるときは、そのたびにユーザーの了承を取ります。
- Claude Codeのトークンを使って、Messages APIなど別のAPIを呼ぶ処理は作りません。

### 秘密と個人情報

- トークンやキーをチャットに貼らせません。登録はユーザー自身が行います(手順は`docs/release.md`)。
- 外部のサービスへ送る内容(リクエスト、検索、ヘッダーなど)に、ユーザーの名前やメールアドレスを入れません。

### 外に出る操作

push、リリースの公開、リポジトリの設定の変更、外部サービスへの送信は、ユーザーに頼まれた範囲だけで行います。実行する前に内容を見せて、確認を取ります。

## コマンド

```sh
swift test                          # ClaudeGaugeCoreのテスト(Swift Testing)
./scripts/bundle.sh                 # build/ClaudeGauge.app を作る(ad-hoc署名)
VERSION=1.2.3 ./scripts/bundle.sh   # Info.plistのバージョンを上書きする(リリースのビルド用)
open build/ClaudeGauge.app
scripts/test-release-notes.sh       # リリースノート用スクリプトのテスト(bashとjqが要る)
```

Windows版のコマンドです。Rust1.100以降が要ります。

```sh
cd windows
cargo test                          # claudegauge-coreのテスト
```

## コードの配置構造

SwiftPM、swift-tools-version6.2、Swift6です。ターゲットは3つです。

- `Sources/ClaudeGaugeCore`: 画面に依存しないロジック。テストはここにだけあります。
  - `UsageService.swift`: 認証情報の取得、期限の判定、API取得、状態の遷移をまとめます。
  - `Credentials/`: `/usr/bin/security`でKeychainを読みます(`KeychainCredentialSource`、`ProcessCommandRunner`)。
  - `API/`: `UsageAPIClient`、`HTTPClient`、レスポンスの読み取り(`UsageResponse`、`UsageMapper`、`FlexibleISO8601`)。
  - `Domain/`: 設定(`AppSettings`)、更新の間隔(`RefreshPolicy`)、予測(`WindowForecast`)、表示用のモデル(`MenuBarModel`、`WindowRowModel`)、表記(`DisplayFormatter`)など。
  - `Storage/UsageStore.swift`: `UserDefaults`への保存。保存するのは秘密でない状態だけです。
- `Sources/ClaudeGauge`: AppKitとSwiftUIの画面。テストはありません。
  - `ClaudeGaugeApp.swift`: `AppDelegate`と、空の`Settings`シーン。
  - `StatusItemController.swift`: `NSStatusItem`と`NSMenu`。詳細パネルは、メニューの項目として載せたSwiftUIの`PopoverView`です。
  - `AppModel.swift`: 取得のループ、Reload、設定。
  - `MenuBarGaugeView`、`NestedDonutView`、`StackedBarsView`、`StatusImageRenderer`、`UsageBar`、`WindowRowView`、`SettingsView`、`SettingsControls`、`LoginItem`。
- `Tests/ClaudeGaugeCoreTests`: Coreのテスト。`Fakes.swift`にテスト用の偽物、`TestSupport.swift`に時刻などの補助があります。

そのほかのディレクトリです。

- `scripts/`: `bundle.sh`(ビルドと署名)、`release-notes.sh`と`test-release-notes.sh`(リリースノート)。
- `.github/workflows/`: `ci.yml`、`release.yml`、`draft-release.yml`。`.github/release-notes-*.md`はリリースノートの雛形です。
- `Resources/`: `Info.plist`とアイコン。`design/`はアイコンの元データです。
- `windows/`: Windows版のCargoのワークスペース。今は、画面に依存しないロジックを置く`claudegauge-core`だけがあり、中身は空です。

## 開発の進め方

- テスト駆動で進めます。先にテストを書き、期待した理由で失敗すること(RED)を確かめてから、実装して通します(GREEN)。完了の報告には、REDとGREENの結果を入れます。文言だけの変更など、テストを省くときは、理由を書きます。
- 画面の層(`Sources/ClaudeGauge`)にはテストがありません。判断が要るロジックは、Coreに置いてテストします。見た目を変えたときは、アプリを起動して実機で確かめます。画面を撮るときは、必要な範囲だけにして、確認したあとで画像を消します。
- Swift6の並行性の検査を保ちます。`let`と`struct`を優先し、既存の値を書き換えずに、新しい値を返します。ファイルは小さく保ちます(200〜400行が目安、最大800行)。
- コードを変えたら、別の観点でレビューを受けます。認証情報、外部との通信、ワークフローに触れたときは、セキュリティの観点のレビューも受けます。ワークフローの設計では、このレビューで、トークンが漏れる経路が見つかり、設計を変えました(`docs/decisions.md`)。
- 見た目と挙動の決まりは`docs/spec.md`にあります。コードと食い違うときは、どちらかだけを直さず、両方をそろえます。
- 判断の理由を`docs/decisions.md`に書くのは、コードやコミットから理由が読み取れず、知らずに覆すと害があるものだけです。それ以外の理由は、コードのコメントか、PRの説明に書きます。
- コメントには、コードから読み取れない理由(なぜそうしたか、どんな制約があるか)だけを書きます。コードを見れば分かる説明は、書かず、見つけたら消します。文章は、厳密な正確さより読みやすさを優先します。例外や条件を全部書いて長くするより、要点が一読で分かる短さにします。
- READMEやdocsの日本語は、英数字と日本語の間に半角スペースを入れません(例: `Swift6.2以降`)。たとえ話や飾りの言葉を避け、誰が何をするかを書きます。

## Gitの決まり

- ブランチの作成、コミット、PRの作成は、ユーザーに頼まれたときだけ行います。実行する前に、ブランチ名、コミットメッセージ、PRの本文を見せて、確認を取ります。ユーザーが内容を指定したときは、確認を省いてかまいません。
- コミットメッセージは、`type: 件名`の形で、件名は「〜した」の完了形にします(例: `fix: 横棒の塗りの右端を丸くした`)。typeは`feat`、`fix`、`refactor`、`docs`、`test`、`chore`、`perf`、`ci`です。本文は書きません。
- PRのタイトルには、typeの接頭語も絵文字も付けません。コミットの件名をそのまま写さず、何のためのPRかが一行で分かる「〜した」の文にします。
- コミットの作者は、ユーザー本人です。AIの名前を、共同の作者として足しません。

## 作業の進め方(ユーザーとのやり取り)

- 回答は短く、結論を先に書きます。選択肢を出すときは、推奨を1つ決めて、理由を添えます。
- 調べて分かることは、聞かずに調べます。ユーザーが決めることだけを聞きます。
- できたことと、確かめていないことを、分けて報告します。確かめていないことを、できたと言いません。

## 文書の一覧

- `docs/spec.md`: 挙動の決まり(データ源、認証情報、予測、更新の間隔、表示)。
- `docs/decisions.md`: 判断とその理由。
- `docs/release.md`: リリースの運用(タグ、ワークフロー、リリースノートの自動下書き、設定)。
- `docs/status.md`: 現在の状況、未確認のこと、未決事項、次にやること。頻繁に変わるため、Gitに含めない手元だけのメモです。あれば、作業を始める前に読みます。
