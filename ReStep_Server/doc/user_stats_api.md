# ユーザー統計API

日次/週次/月次の統計と連続記録のAPIです。

> 共通仕様は [API_common.md](API_common.md) を参照してください。

すべてログイン必須です。

---

## アクション一覧

| action | 認証 | 必須パラメータ | 任意パラメータ | 備考 |
|--------|------|----------------|----------------|------|
| `seed_continuity` | 必須 | `current_streak`, `longest_streak` | `last_active_date` | 1〜36,500 |
| `record_continuity` | 必須 | - | `date` | 未指定なら本日 |
| `get_continuity` | 必須 | - | - | |
| `save_daily` | 必須 | `date`, `steps`, `calories`, `distance_km` | - | steps: 0〜100,000 |
| `get_daily` | 必須 | `date` | - | |
| `get_range` | 必須 | `from`, `to` | - | 範囲最大366日 |
| `get_weekly_summary` | 必須 | - | `date` | 未指定なら本日 |
| `get_monthly_summary` | 必須 | - | `year`, `month` | 未指定なら当月 |

---

## アクション詳細

### `seed_continuity`

連続記録の初期値を投入/更新。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `current_streak` (int: 1〜36,500), `longest_streak` (int: 1〜36,500) |
| 任意 | `last_active_date` (string: "YYYY/MM/DD") |

**レスポンス** `200`

```json
{
  "current_streak": 1,
  "longest_streak": 1,
  "last_active_date": "YYYY/MM/DD",
  "seeded": true,
  "idempotent": false
}
```

---

### `record_continuity`

活動日を記録。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |
| 任意 | `date` (string: "YYYY/MM/DD") 未指定なら本日 |

**レスポンス** `200`

```json
{
  "current_streak": 1,
  "longest_streak": 1,
  "last_active_date": "YYYY/MM/DD",
  "idempotent": true
}
```

---

### `get_continuity`

連続記録を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |

**レスポンス** `200`

```json
{
  "current_streak": 1,
  "longest_streak": 1,
  "last_active_date": "YYYY/MM/DD",
  "updated_at": "YYYY-MM-DD HH:MM:SS"
}
```

---

### `save_daily`

日次記録を保存（UPSERT）。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `date` (string: "YYYY/MM/DD"), `steps` (int: 0〜100,000), `calories` (int: 0〜10,000), `distance_km` (float: 0〜200) |

**レスポンス** `200`

```json
{
  "message": "saved"
}
```

---

### `get_daily`

指定日の記録を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `date` (string: "YYYY/MM/DD") |

**レスポンス** `200`

```json
{
  "date": "YYYY/MM/DD",
  "steps": 0,
  "calories": 0,
  "distance_km": 0.0,
  "updated_at": null
}
```

---

### `get_range`

期間範囲の記録を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | `from` (string: "YYYY/MM/DD"), `to` (string: "YYYY/MM/DD") |
| 制約 | 範囲は最大366日 |

**レスポンス** `200`

```json
{
  "items": [
    {
      "date": "YYYY/MM/DD",
      "steps": 0,
      "calories": 0,
      "distance_km": 0.0
    }
  ]
}
```

---

### `get_weekly_summary`

週次集計を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |
| 任意 | `date` (string: "YYYY/MM/DD") 未指定なら本日 |

**レスポンス** `200`

```json
{
  "week_start": "YYYY/MM/DD",
  "week_end": "YYYY/MM/DD",
  "total_steps": 0,
  "total_calories": 0,
  "total_distance_km": 0.0,
  "days_recorded": 0,
  "avg_steps": 0,
  "avg_calories": 0,
  "avg_distance_km": 0.0
}
```

---

### `get_monthly_summary`

月次集計を取得。

| 項目 | 内容 |
|------|------|
| 認証 | 必須 |
| 必須 | - |
| 任意 | `year` (int: 2000〜2100), `month` (int: 1〜12) |

未指定時は当月。

**レスポンス** `200`

```json
{
  "year": 2026,
  "month": 2,
  "days_in_month": 28,
  "total_steps": 0,
  "total_calories": 0,
  "total_distance_km": 0.0,
  "days_recorded": 0,
  "avg_steps": 0,
  "avg_calories": 0,
  "avg_distance_km": 0.0
}
```
