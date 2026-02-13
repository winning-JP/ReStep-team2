# ユーザーAPI

認証・アカウント管理のAPIです。

> 共通仕様は [API_common.md](API_common.md) を参照してください。

---

## アクション一覧

| action | 認証 | 必須パラメータ | 任意パラメータ | 備考 |
|--------|------|----------------|----------------|------|
| `register` | 不要 | `login_id`, `email`, `password` | `device_name` | 初期コイン50付与 |
| `login` | 不要 | `identifier`, `password` | `device_name` | |
| `status` | 任意 | - | - | |
| `devices` | 必須 | - | - | |
| `logout` | 任意 | - | - | |
| `logout_all` | 必須 | - | - | |
| `revoke_device` | 必須 | `token_id` | - | |
| `update_profile` | 必須 | いずれか1つ以上 | - | `login_id` / `email` / `password` |
| `close_account` | 必須 | `password` | - | |
| `admin_users` | 管理者 | - | - | |
| `admin_force_logout` | 管理者 | `user_id` | - | |

---

## アクション詳細

### `register`

新規ユーザー登録を行い、認証トークンを発行します。

| 項目 | 内容 |
|------|------|
| 認証 | 不要 |
| 必須 | `login_id` (string), `email` (string), `password` (string) |
| 任意 | `device_name` (string) |

**動作**

ユーザー作成、リフレッシュトークン発行、初期コイン50付与、`refresh_token` Cookie設定。

**レスポンス** `201`

```json
{
  "message": "Registered",
  "user": {
    "login_id": "...",
    "email": "...",
    "is_admin": 0
  }
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `400 bad_request` | 必須パラメータ不足 |
| `409 conflict` | login_id または email が重複 |

---

### `login`

認証を行い、新しいリフレッシュトークンを発行します。

| 項目 | 内容 |
|------|------|
| 認証 | 不要 |
| 必須 | `identifier` (string: login_id または email), `password` (string) |
| 任意 | `device_name` (string) |

**レスポンス** `200`

```json
{
  "message": "Login OK",
  "user": {
    "login_id": "...",
    "email": "...",
    "is_admin": 0
  }
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `401 auth_failed` | 認証失敗 |

---

### `status`

現在の認証状態を確認します。

| 項目 | 内容 |
|------|------|
| 認証 | 任意（Cookie） |
| 必須 | - |

**レスポンス** `200`

ログイン時:

```json
{
  "logged_in": true,
  "user": {
    "login_id": "...",
    "email": "...",
    "is_admin": 0,
    "created_at": "YYYY-MM-DD HH:MM:SS"
  }
}
```

未ログイン時:

```json
{
  "logged_in": false
}
```

---

### `devices`

発行済みトークン（端末）の一覧を取得します。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |

**レスポンス** `200`

```json
{
  "devices": [
    {
      "id": 1,
      "created_at": "...",
      "expires_at": "...",
      "revoked_at": null,
      "device_name": "...",
      "ip_address": "...",
      "user_agent": "...",
      "is_current": 1
    }
  ]
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `401 unauthenticated` | 未認証 |

---

### `logout`

現在のトークンを失効させます。

| 項目 | 内容 |
|------|------|
| 認証 | 任意 |
| 必須 | - |

**動作**

現在のトークンを失効（あれば）し、Cookie を削除。

**レスポンス** `200`

```json
{
  "message": "Logged out"
}
```

---

### `logout_all`

すべてのトークンを失効させます。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |

**動作**

全トークン失効、Cookie削除。

**レスポンス** `200`

```json
{
  "message": "Logged out from all devices"
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `401 unauthenticated` | 未認証 |

---

### `revoke_device`

指定したトークンを失効させます。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `token_id` (int) |

**動作**

指定トークンを失効（本人のもののみ）。

**レスポンス** `200`

```json
{
  "message": "Device revoked",
  "token_id": 123
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `400 bad_request` | token_id 不足 |
| `403 forbidden` | 他人のトークン |
| `404 not_found` | トークン未存在 |

---

### `update_profile`

ログインID、メール、パスワードを更新します。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `login_id` / `email` / `password` のいずれか1つ以上 |

**レスポンス** `200`

```json
{
  "message": "Profile updated",
  "user": {
    "login_id": "...",
    "email": "...",
    "is_admin": 0
  }
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `400 bad_request` | 変更項目なし |
| `409 conflict` | login_id または email が重複 |

---

### `close_account`

アカウントを削除します。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `password` (string) |

**動作**

ユーザー関連データを削除し、Cookie を削除。

**レスポンス** `200`

```json
{
  "message": "Account closed"
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `401 auth_failed` | パスワード不一致 |

---

### `admin_users`

全ユーザー一覧を取得します（管理者専用）。

| 項目 | 内容 |
|------|------|
| 認証 | 管理者のみ |
| 必須 | - |

**レスポンス** `200`

```json
{
  "users": [
    {
      "id": 1,
      "login_id": "...",
      "email": "...",
      "is_admin": 0
    }
  ]
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `401 unauthenticated` | 未認証 |
| `403 forbidden` | 権限なし |

---

### `admin_force_logout`

指定ユーザーを強制ログアウトさせます（管理者専用）。

| 項目 | 内容 |
|------|------|
| 認証 | 管理者のみ |
| 必須 | `user_id` (int) |

**動作**

対象ユーザーの全トークンを失効。

**レスポンス** `200`

```json
{
  "message": "User forcibly logged out",
  "user_id": 123
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `401 unauthenticated` | 未認証 |
| `403 forbidden` | 権限なし |
