# ClaudeGauge

Claude の使用制限（5 時間セッションと週間の上限）をゲージで表示し、上限に届く時期も予測する、macOS 用の小さなメニューバーアプリです。

> [!WARNING]
> **非公式のアプリです。自己責任で使ってください。**
>
> - ClaudeGauge は Keychain から **Claude Code の OAuth トークン**を読み、公式に文書化されていない Anthropic のエンドポイント（`/api/oauth/usage`）に送ります。そのトークンを別のアプリから使うことを、Anthropic の利用規約が認めていない可能性があります。使う前に最新の規約を読み、認められていなければ使わないでください。
> - このエンドポイントは、予告なく変わったり使えなくなったりすることがあります。また、これを使うアカウントを Anthropic が制限する可能性もあります。
> - このプロジェクトは Anthropic とは無関係で、承認も受けていません。「Claude」は Anthropic の商標です。アプリのアイコンは独自に作ったものです。

- メニューバーには入れ子のドーナツ（外側が 5 時間セッション、内側が週間）と、その横に使用率を表示します。横棒 2 本のスタイルも選べます。
- ポップオーバーには使用率、リセット時点の予測（`Forecast: 120% (100% at 21:40)`）、リセット時刻と残り時間、最終更新の時刻を表示します。
- 色は、70% 未満が緑、70% 以上が黄、90% 以上が赤です。
- ログイン時の自動起動、更新間隔（1 / 3 / 5 / 10 分）、メニューバーのスタイルは、ポップオーバーの設定で変えられます。

## 動作環境

- macOS 26 以降（ポップオーバーに Liquid Glass を使っています）。
- この Mac でログイン済みの Claude Code。ClaudeGauge は、Claude Code が保存した認証情報を読みます。
- ビルドには、Xcode と Swift 6.2 のツールチェーンが必要です。

## ビルドと実行

```sh
./scripts/bundle.sh          # build/ClaudeGauge.app を作成（ad-hoc 署名）
open build/ClaudeGauge.app
swift test                   # Core のテストを実行
```

Dock にアイコンは出ません。メニューバーにあるゲージを探してください。

アプリは **ad-hoc 署名で、公証（notarization）を受けていません**。自分でビルドしたアプリは、そのまま開けます。ビルド済みの `.app` を別の Mac にコピーすると Gatekeeper に止められるので、右クリックから「開く」を選ぶか、その Mac でビルドしてください。

## 仕組み

ClaudeGauge はログインキーチェーンから Claude Code の OAuth アクセストークンを読み（項目名は `Claude Code-credentials`、`/usr/bin/security` を経由します）、`GET https://api.anthropic.com/api/oauth/usage` を呼びます。ネットワークへのリクエストはこれだけで、通信先もこのホストだけです。

- 使うのは、アクセストークンとその期限だけです。同じ Keychain 項目にはほかのツールの認証情報（とリフレッシュトークン）も入っています。ClaudeGauge はそれらをモデルにデコードせず、保存もログ出力もしません。ただし項目全体は解析のあいだ短時間だけアプリのメモリを通ります。
- トークンの更新はしません。トークンの期限が切れているときは `Open Claude Code once to refresh` と表示するので、Claude Code を起動してから Reload を押してください。
- 保存するのは、使用率、時刻、設定だけです（`UserDefaults`）。トークンはどこにも書き込みません。
- 更新するのは、Reload を押したとき（1 分に 1 回まで）と、自動更新のタイマーが来たときだけです。HTTP 429 を受けたときや Keychain を読めないときは、更新の間隔を延ばします。アプリの起動やポップオーバーを開いただけでは、リクエストを送りません。

予測の計算式、更新のスケジュール、表示のルールは、[docs/spec.md](docs/spec.md)（英語）に書いてあります。

## 注意点

初回は `security` が `Claude Code-credentials` を使ってよいかを macOS が確認します。「常に許可」ではなく 1 回だけの「許可」を選んでください。「常に許可」を選ぶとその項目のアクセスリストに `/usr/bin/security` が加わり、以後はどのプログラムでも `security` 経由で、確認なしにその項目を読めるようになります。

ログイン時の自動起動には `SMAppService` を使います。アプリはシステム設定の「一般」›「ログイン項目と機能拡張」›「ログイン時に開く」に表示されます。登録されるのは今ある場所のアプリなので、先に `ClaudeGauge.app` を `/Applications` にコピーしてください。`build/` や `~/Downloads` のようにユーザーが書き込める場所に置くと、そこを差し替えられたときに、差し替えたものがログインのたびに実行されます。アプリを移動したときは、設定し直してください。

ClaudeGauge は ad-hoc 署名（Hardened Runtime つき）で、公証を受けておらず、App Sandbox も使っていません。`/usr/bin/security` を起動する必要があるためです。他人が作ったバイナリは実行せず、ソースからビルドしてください。保存される状態（`~/Library/Preferences` の `lastUsage`）には使用率と時刻しか入っていませんが、ローカルのどのプロセスからでも書き換えられます。

## ディレクトリ構成

```
Sources/ClaudeGaugeCore      Foundation だけで書いたロジック（認証情報、API クライアント、予測、更新ポリシー、表示用の文字列）
Sources/ClaudeGauge          SwiftUI のアプリ（メニューバーのラベル、ポップオーバー、設定）
Tests/ClaudeGaugeCoreTests   Core の Swift Testing によるテスト
Resources/                   Info.plist、AppIcon.icns
scripts/bundle.sh            .app をビルドして ad-hoc 署名する
docs/spec.md                 将来の Windows 版と共有する動作の仕様
design/                      アプリアイコンの元画像（AppIcon-1024.png）と、それを描くスクリプト（icon/make_icon.swift）
```

## 今後の予定

- 週間の内訳（Claude Code / Chats / Cowork）と、モデル別の週間上限の表示。取得と解析は実装済みで、表示はまだしていません。
- Windows 版の作成。

## ライセンス

[MIT License](LICENSE)
