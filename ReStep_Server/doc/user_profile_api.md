# ユーザープロフィールAPI

プロフィールの取得・更新のAPIです。

> 共通仕様は [API_common.md](API_common.md) を参照してください。

すべてログイン必須です。

---

## プロフィール項目

| 項目 | 型 | 制約 |
|------|------|------|
| `nickname` | string | 最大20文字 |
| `bluetooth_user_id` | string | 最大64文字（英数字と`-`） |
| `encounter_visibility` | string | `"public"` / `"private"` |
| `birthday` | string | "YYYY/MM/DD" |
| `gender` | string | "男性" / "女性" / "その他" |
| `height_cm` | float | 120〜220 |
| `weight_kg` | float | 20〜200 |
| `weekly_steps` | int | 0〜30,000 |
| `body_fat` | int | 3〜60 |
| `weekly_exercise` | int | 0〜14 |
| `goal_steps` | int | 1,000〜50,000 |
| `goal_calories` | int | 100〜2,000 |
| `goal_distance_km` | float | 0〜50 |

---

## アクション一覧

| action | 認証 | 必須パラメータ | 任意パラメータ | 備考 |
|--------|------|----------------|----------------|------|
| `get_profile` | 必須 | - | - | |
| `update_profile` | 必須 | `profile` | - | 全項目許可、未指定はnull扱い |
| `patch_profile` | 必須 | `profile` | - | 指定項目のみ更新 |
| `clear_profile_fields` | 必須 | `fields` | - | フィールド名配列 |
| `encounter_sync` | 必須 | `bluetooth_user_id`, `share_nickname` | `nickname` | すれ違い用IDと公開設定を同期 |
| `encounter_lookup` | 必須 | `bluetooth_user_id` | - | すれ違い用IDから表示名を解決 |

---

## アクション詳細

### `get_profile`

プロフィールを取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |

**レスポンス** `200`

```json
{
  "profile": {
    "nickname": null,
    "bluetooth_user_id": null,
    "encounter_visibility": "public",
    "birthday": null,
    "gender": null,
    "height_cm": null,
    "weight_kg": null,
    "weekly_steps": null,
    "body_fat": null,
    "weekly_exercise": null,
    "goal_steps": null,
    "goal_calories": null,
    "goal_distance_km": null,
    "updated_at": null
  }
}
```

---

### `update_profile`

プロフィールを全体更新（未指定項目はnull扱い）。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `profile` (object) |

**レスポンス** `200`

```json
{
  "message": "updated"
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `400 bad_request` | profile が必須 |
| `422 validation_failed` | バリデーションエラー |

---

### `patch_profile`

プロフィールを部分更新（指定項目のみ）。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `profile` (object) |

**レスポンス** `200`

```json
{
  "message": "updated"
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `400 bad_request` | 変更なし |
| `422 validation_failed` | バリデーションエラー |

---

### `clear_profile_fields`

指定項目をクリア（null化）。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `fields` (array: フィールド名の配列) |

**レスポンス** `200`

```json
{
  "message": "cleared"
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `400 bad_request` | fields が必須 |
| `422 validation_failed` | バリデーションエラー |

---

### `encounter_sync`

すれ違い機能で使うBluetoothユーザーIDと、ニックネーム公開設定を同期します。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `bluetooth_user_id` (string), `share_nickname` (bool) |
| 任意 | `nickname` (string: 最大20文字) |

**レスポンス** `200`

```json
{
  "message": "synced",
  "bluetooth_user_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "encounter_visibility": "public",
  "share_nickname": true,
  "nickname": "ユーザー名"
}
```

**エラー**

| コード | 説明 |
|--------|------|
| `400 bad_request` | 必須パラメータ不備 |
| `409 conflict` | bluetooth_user_id 重複 |
| `422 validation_failed` | バリデーションエラー |

---

### `encounter_lookup`

`bluetooth_user_id` から、公開設定を考慮した表示名を取得します。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `bluetooth_user_id` (string) |

**レスポンス** `200`

```json
{
  "found": true,
  "bluetooth_user_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "encounter_visibility": "public",
  "share_nickname": true,
  "nickname": "ユーザー名",
  "display_name": "ユーザー名"
}
```

非公開/未登録時は `display_name` が `"名無しの旅人"` になります。
