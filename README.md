# ClaudeGauge

<div align="center">

[![Release][release-badge]][release-url] [![CI][ci-badge]][ci-url] [![License][license-badge]][license-url]

![Platform][platform-badge]

</div>

[release-badge]: https://img.shields.io/github/v/release/0yaizu/claudegauge?style=for-the-badge&logo=github&color=ff6b6b
[release-url]: https://github.com/0yaizu/claudegauge/releases/latest
[ci-badge]: https://img.shields.io/github/actions/workflow/status/0yaizu/claudegauge/ci.yml?style=for-the-badge&label=CI
[ci-url]: https://github.com/0yaizu/claudegauge/actions/workflows/ci.yml
[license-badge]: https://img.shields.io/github/license/0yaizu/claudegauge?style=for-the-badge
[license-url]: LICENSE
[platform-badge]: https://img.shields.io/badge/platform-macOS%2026%2B%20%7C%20Apple%20Silicon-000000?style=for-the-badge&logo=apple

<div align="center">
  <video src="https://github.com/user-attachments/assets/9cd79232-ef21-42a2-91df-ac153f4cdb54" controls></video>
  <p>Claudeの使用状況をメニューバーに表示する、macOS用の小さなアプリです。</p>
</div>

> [!WARNING]
> これは非公式のアプリです。Anthropic社のClaudeとは無関係です。使用する場合は自己責任で使用してください。

## 特徴

- Claudeの使用状況をメニューバーにグラフ付きで表示
- ユーザーの使用状況から予測を表示

予測の計算式、更新のスケジュール、表示のルールは、[docs/spec.md](docs/spec.md)に記載されています。

## 動作環境

- Apple Siliconを搭載したMac
- macOS 26以降
- ログイン済のClaude Code CLI（v2.1.323で動作確認済）

## インストール
### 自前ダウンロード
1. [Releases](https://github.com/0yaizu/claudegauge/releases/latest)から`ClaudeGauge-*.zip`をダウンロードします。
2. zipを展開し、`ClaudeGauge.app`を`/Applications`に移動します。
3. `ClaudeGauge.app`を開きます。

> [!NOTE]
> 署名を受けていないアプリなので、初回起動時、起動を阻止される可能性があります。「システム設定」の「プライバシーとセキュリティ」から「このまま開く」を選んでください。

## 開発環境、ビルド、テスト
- Xcode
- Swift 6.2以降

```sh
./scripts/bundle.sh          # build/ClaudeGauge.app を作成（ad-hoc 署名）
open build/ClaudeGauge.app
swift test                   # Core のテストを実行
```

## プライバシー

ClaudeGaugeはmacOSのキーチェーンからClaude CodeのOAuthアクセストークンを読み取り、そのトークンを使って、使用状況をAnthropicのエンドポイント（`api.anthropic.com`）から取得します。
アクセストークンは使用状況の取得にだけ使い、どこにも保存しません。

取得したデータは全てローカルで処理されます。ユーザーの認証情報および使用統計情報は、`api.anthropic.com`以外のサーバーに送信しません。

ClaudeGaugeは、`/usr/bin/security`コマンドを経由してKeychainを読みます。通常は確認のダイアログが出ませんが、ログインキーチェーンがロックされているときなどは、macOSが確認を求めることがあります。その場合は「許可」を選択してください。

アプリが認証情報をどう扱うかは、次のコードから確かめられます。

- [認証情報の読み取り](Sources/ClaudeGaugeCore/Credentials/KeychainCredentialSource.swift)
- [APIの呼び出し](Sources/ClaudeGaugeCore/API/UsageAPIClient.swift)
- [保存する内容](Sources/ClaudeGaugeCore/Storage/UsageStore.swift)

## 今後の予定

- モデル別の使用上限や追加クレジットの使用状況の表示
- 自動アップデート確認、自動アップデート
- 表示内容のカスタム設定
- 詳細設定画面の追加
- Windows版の作成

## ライセンス

[MIT License](LICENSE)
