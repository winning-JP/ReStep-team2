# API ドキュメント

このディレクトリには、APIの仕様書が含まれています。

---

## ドキュメント一覧

| ファイル | 内容 |
|----------|------|
| [API_common.md](API_common.md) | 共通仕様 / 用語集 / 命名規則 / シーケンス図 |
| [user_api.md](user_api.md) | 認証・アカウント管理 |
| [user_wallet_api.md](user_wallet_api.md) | コイン・スタンプ・チャレンジ |
| [user_profile_api.md](user_profile_api.md) | プロフィール |
| [user_stats_api.md](user_stats_api.md) | 統計・連続記録 |
| [Self_test.md](Self_test.md) | セルフテスト |

---

## クイックスタート

1. **共通仕様の確認**: まず [API_common.md](API_common.md) で認証方式やエラー形式を確認
2. **各APIの参照**: 必要なAPIのドキュメントを参照

---

## API概要

| API | エンドポイント | 主な機能 |
|-----|----------------|----------|
| User API | `user_api.php` | 登録、ログイン、認証管理 |
| Wallet API | `user_wallet_api.php` | コイン/スタンプ残高、履歴、チャレンジ |
| Profile API | `user_profile_api.php` | プロフィール取得/更新 |
| Stats API | `user_stats_api.php` | 日次/週次/月次統計、連続記録 |
