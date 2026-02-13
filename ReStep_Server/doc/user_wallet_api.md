# ユーザーウォレットAPI

コイン・スタンプ・チャレンジに関するAPIです。

> 共通仕様は [API_common.md](API_common.md) を参照してください。

特記がない限り、すべてログイン必須です。

---

## アクション一覧

| action | 認証 | 必須パラメータ | 任意パラメータ | 備考 |
|--------|------|----------------|----------------|------|
| `ping` | 必須 | - | - | |
| `admin_ping` | 管理者 | - | - | |
| `coin_register` | 必須 | `balance` | - | 0〜1,000,000,000 |
| `coin_get` | 必須 | - | - | |
| `coin_use` | 必須 | `amount` | `reason`, `client_request_id` | 1〜1,000,000,000 |
| `coin_earn` | 必須 | `amount` | `reason`, `client_request_id` | 1〜1,000,000,000 |
| `coin_add` | 管理者 | `user_id`, `amount` | `reason`, `client_request_id` | 1〜1,000,000,000 |
| `coin_history` | 必須 | - | `limit`, `before_id` | limit: 1〜200 |
| `stamp_get` | 必須 | - | - | |
| `stamp_sync` | 必須 | `date_key`, `current_earned` | `client_request_id` | current_earned: 0〜100,000 |
| `stamp_spend` | 必須 | `amount` | `reason`, `client_request_id` | 1〜1,000,000,000 |
| `stamp_add` | 必須 | `amount` | `reason`, `client_request_id` | 1〜1,000,000,000 |
| `stamp_history` | 必須 | - | `limit`, `before_id` | limit: 1〜200 |
| `challenge_list` | 必須 | - | - | |
| `challenge_status` | 必須 | - | `year`, `month` | 未指定時は当月 |
| `challenge_claim` | 必須 | `key` | `year`, `month`, `client_request_id` | 月次報酬のみ year/month |

---

## アクション詳細

### `ping`

認証済み疎通確認。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |

**レスポンス** `200`

```json
{
  "message": "ok",
  "user_id": 123
}
```

---

### `admin_ping`

管理者用疎通確認。

| 項目 | 内容 |
|------|------|
| 認証 | 管理者のみ |
| 必須 | - |

**レスポンス** `200`

```json
{
  "message": "ok",
  "admin_id": 1
}
```

---

### `coin_register`

ウォレット初期登録（移行用途）。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `balance` (int: 0〜1,000,000,000) |

**動作**

ウォレット未作成なら作成し初期残高を付与。

**レスポンス** `200`

```json
{
  "user_id": 123,
  "balance": 50,
  "registered": true,
  "transaction_id": 10
}
```

---

### `coin_get`

コイン残高を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |

**レスポンス** `200`

```json
{
  "user_id": 123,
  "balance": 50
}
```

---

### `coin_use`

コインを消費。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `amount` (int: 1〜1,000,000,000) |
| 任意 | `reason` (string), `client_request_id` (string: max 64) |

**レスポンス** `200`

```json
{
  "message": "ok",
  "user_id": 123,
  "used": 5,
  "balance": 45,
  "transaction_id": 99,
  "idempotent": false
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `409 insufficient_coins` | 残高不足 |

---

### `coin_earn`

コインを獲得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `amount` (int: 1〜1,000,000,000) |
| 任意 | `reason` (string), `client_request_id` (string) |

**レスポンス** `200`

```json
{
  "message": "ok",
  "user_id": 123,
  "added": 5,
  "balance": 55,
  "transaction_id": 100,
  "idempotent": false
}
```

---

### `coin_add`

管理者によるコイン付与。

| 項目 | 内容 |
|------|------|
| 認証 | 管理者のみ |
| 必須 | `user_id` (int), `amount` (int: 1〜1,000,000,000) |
| 任意 | `reason` (string), `client_request_id` (string) |

**レスポンス** `200`

```json
{
  "message": "ok",
  "admin_id": 1,
  "user_id": 123,
  "added": 5,
  "balance": 55,
  "transaction_id": 101,
  "idempotent": false
}
```

---

### `coin_history`

コイン取引履歴を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |
| 任意 | `limit` (int: 1〜200, default: 50), `before_id` (int) |

**レスポンス** `200`

```json
{
  "user_id": 123,
  "balance": 55,
  "items": [
    {
      "id": 101,
      "delta": 5,
      "type": "earn",
      "reason": "...",
      "meta": {},
      "balance_after": 55,
      "created_at": "..."
    }
  ],
  "next_before_id": 101
}
```

---

### `stamp_get`

スタンプ残高を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |

**レスポンス** `200`

```json
{
  "user_id": 123,
  "balance": 2,
  "total_earned": 10
}
```

---

### `stamp_sync`

当日獲得分のスタンプを同期（差分加算）。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `date_key` (string: max 10), `current_earned` (int: 0〜100,000) |
| 任意 | `client_request_id` (string) |

**レスポンス** `200`

```json
{
  "user_id": 123,
  "balance": 4,
  "earned_today": 2,
  "added": 2
}
```

---

### `stamp_spend`

スタンプを消費。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `amount` (int: 1〜1,000,000,000) |
| 任意 | `reason` (string), `client_request_id` (string) |

**レスポンス** `200`

```json
{
  "message": "ok",
  "user_id": 123,
  "used": 3,
  "balance": 2,
  "transaction_id": 28,
  "idempotent": false
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `409 insufficient_stamps` | 残高不足 |

---

### `stamp_add`

スタンプを追加。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `amount` (int: 1〜1,000,000,000) |
| 任意 | `reason` (string), `client_request_id` (string) |

**レスポンス** `200`

```json
{
  "message": "ok",
  "user_id": 123,
  "added": 3,
  "balance": 5,
  "transaction_id": 27,
  "idempotent": false
}
```

---

### `stamp_history`

スタンプ取引履歴を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |
| 任意 | `limit` (int: 1〜200, default: 50), `before_id` (int) |

**レスポンス** `200`

```json
{
  "user_id": 123,
  "balance": 2,
  "items": [
    {
      "id": 28,
      "delta": -3,
      "type": "spend",
      "reason": "...",
      "balance_after": 2,
      "created_at": "..."
    }
  ],
  "next_before_id": 28
}
```

---

### `challenge_list`

チャレンジ定義一覧を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |

**レスポンス** `200`

```json
{
  "monthly": [...],
  "cumulative": [...]
}
```

---

### `challenge_status`

チャレンジ達成状況を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |
| 任意 | `year` (int: 2020〜2100), `month` (int: 1〜12) |

未指定時は当月。

**レスポンス** `200`

```json
{
  "period_key": "YYYY-MM",
  "claimed_monthly": [],
  "claimed_cumulative": [],
  "unlocks": {
    "battle": false,
    "poker": false,
    "slot": false
  }
}
```

---

### `challenge_claim`

チャレンジ報酬を請求（冪等）。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `key` (string) |
| 任意 | `year` (int), `month` (int)（月次報酬のみ）, `client_request_id` (string) |

**レスポンス** `200`

```json
{
  "message": "ok",
  "key": "...",
  "period_key": "YYYY-MM",
  "reward_type": "coin|unlock",
  "balance": 100,
  "idempotent": false,
  "unlocks": null
}
```
