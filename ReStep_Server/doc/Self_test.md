# セルフテスト

API一式のセルフテストを実行します。

> 共通仕様は [API_common.md](API_common.md) を参照してください。

---

## パラメータ一覧

| 項目 | 必須 | 型 | 説明 |
|------|------|------|------|
| `user_api_url` | 条件付き | string | ユーザー系APIのURL |
| `wallet_api_url` | 条件付き | string | ウォレット系APIのURL |
| `profile_api_url` | 条件付き | string | プロフィール系APIのURL |
| `stats_api_url` | 条件付き | string | 統計系APIのURL |
| `target_url` | 条件付き | string | `user_api_url` の代替（後方互換） |

**条件**

- `user_api_url` を指定する場合は他3つも指定、または同一パスから自動推定される
- `target_url` は `user_api_url` と同義

---

## リクエスト例

全APIのURL指定:

```json
{
  "user_api_url": "https://example.com/user_api.php",
  "wallet_api_url": "https://example.com/user_wallet_api.php",
  "profile_api_url": "https://example.com/user_profile_api.php",
  "stats_api_url": "https://example.com/user_stats_api.php"
}
```

または `target_url` / `user_api_url` のみ指定すると、同一パスから他URLを自動推定します。

---

## レスポンス例

```json
{
  "ok": true,
  "urls": {
    "user_api_url": "...",
    "wallet_api_url": "...",
    "profile_api_url": "...",
    "stats_api_url": "..."
  },
  "tested_at": "YYYY-MM-DD HH:MM:SS",
  "test_user": {
    "login_id": "...",
    "email": "..."
  },
  "results": [
    {
      "name": "...",
      "passed": true,
      "response": {}
    }
  ]
}
```
