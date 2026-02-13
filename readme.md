# ReStep

ReStep は、iOS アプリ (`ReStep/`) と API サーバー (`ReStep_Server/`) を 1 つのリポジトリで管理するモノレポ構成のプロジェクトです。  
「歩く・続ける・楽しむ」を軸に、歩数/位置情報/通知/すれ違い(Bluetooth) を使った行動継続体験を提供します。

## 企画概要
- プロジェクト名: ReStep
- コンセプト: 「“努力しない健康習慣”をつくるアプリ」
- 対象: 20〜40代の、健康行動が続かない層
- 目的: 日常行動を起点に、健康習慣を自然に定着させる
- MVP開発期間: 2026/1/27〜2/22

### 背景と課題

- 健康意識があっても継続しにくい
- 忙しさにより健康行動が後回しになる
- 既存アプリは入力負担や「やる気頼み」の設計で離脱されやすい

### MVPで重視した価値

- 歩数を起点とした自動行動記録
- ご褒美（スタンプ/体験）による行動フィードバック
- 無理のない短期目標設定

### 今後の拡張方針

- 位置情報を活用した行動トリガー
- AIによる行動誘導
- 最適タイミング通知
- 食事・睡眠・体重などの記録
- 健康データ連携の拡張

## アプリ概要

- **コンセプト**: 運動を「頑張るもの」ではなく、日常の中で自然に続く行動へ変える
- **解決したい課題**: 健康意識はあっても、歩行や運動習慣が継続しにくい
- **提供価値**:
	- 歩数・カロリー・距離の可視化による達成感
	- スタンプ/ご褒美やチャレンジによる継続動機
	- 位置情報や Bluetooth 連動（すれ違い体験）による“外に出る理由”の創出
- **想定ユーザー**: 忙しくて運動が後回しになりがちな人、ゲーム感覚で習慣化したい人

## リポジトリ構成

```text
.
├─ ReStep/                 # iOSアプリ (SwiftUI)
│  ├─ App/
│  ├─ Auth/
│  ├─ Encounter/
│  ├─ Chocozap/
│  ├─ Inventory/
│  ├─ Profile/
│  ├─ Services/
│  └─ ...
├─ ReStep_Server/          # APIサーバー (Docker + PHP + MariaDB + Nginx + Cloudflare Tunnel)
│  ├─ docker-compose.yml
│  ├─ Dockerfile
│  ├─ .env.sample
│  ├─ data/
│  └─ mariadb/
├─ script/
│  ├─ setup.sh             # EC2(Ubuntu) 初期セットアップ用（手動実行）
│  └─ ec2-user-data.sh     # EC2 User data 用（起動時自動実行）
├─ ReStep.xcodeproj
└─ readme.md
```

## 主な機能（実装ベース）

- 認証: ログイン / 新規登録 / セッション復元 (`Auth/`)
- ホーム・チャレンジ・目標・すれ違い・設定のタブ構成 (`App/ContentView.swift`)
- 歩数/カロリー/距離の同期（HealthKit を利用する統計同期処理） (`Services/StatsSyncManager.swift`)
- 位置情報連動（近隣スポット・スタンプ体験） (`App/LocationManager.swift`, `Chocozap/`)
- Bluetooth すれ違い体験と通知 (`Bluetooth/`, `Encounter/`, `Services/NotificationManager.swift`)
- プロファイル/目標値管理（歩数目標・消費カロリー目標など） (`Profile/`)

## 技術スタック

### iOS アプリ
- Swift 6.2
- SwiftUI
- iOS Deployment Target: 17.0
- CoreLocation / CoreBluetooth / UserNotifications / HealthKit

### API サーバー
- PHP-FPM + Nginx
- MariaDB 11
- Docker Compose
- phpMyAdmin
- Cloudflare Tunnel

## セットアップ

## 0) EC2 初期セットアップ（任意）

このリポジトリには EC2 向けに 2 種類のスクリプトがあります。

- `script/setup.sh`: 既存EC2インスタンスに SSH ログイン後、手動実行する用
- `script/ec2-user-data.sh`: EC2 作成時の「ユーザーデータ（オプション）」へ貼り付ける用

### A. script/setup.sh（手動実行）

前提:
- Ubuntu 系
- `root` 権限（`sudo`）
- Tailscale の Auth Key

実行:

```bash
chmod +x script/setup.sh
sudo TAILSCALE_AUTHKEY="tskey-xxxx" ./script/setup.sh
```

### B. script/ec2-user-data.sh（起動時自動実行）

1. `script/ec2-user-data.sh` を開き、以下を置き換え:

```bash
TAILSCALE_AUTHKEY="REPLACE_WITH_TAILSCALE_AUTHKEY"
```

2. EC2 作成画面の「ユーザーデータ（オプション）」に、スクリプト全文を貼り付け

3. 起動後、以下で実行ログ確認:

```bash
sudo tail -n 200 /var/log/user-data.log
```

この2スクリプトで行うこと:
- Docker Engine / Compose plugin のインストール
- Docker サービスの自動起動設定
- Tailscale のインストールと起動
- `tailscale up --ssh` の実行（設定時）

## 1) API サーバー起動

作業ディレクトリを移動:

```bash
cd ReStep_Server
```

環境変数ファイルを作成:

```bash
cp .env.sample .env
```

`.env` の主要項目を環境に合わせて編集してください:

- `DB_ROOT_PASSWORD`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `TS_IP`, `NGINX_HOST`, `NGINX_PORT`
- `CORS_ORIGIN`
- `CLOUDFLARE_TUNNEL_TOKEN`（Cloudflare Tunnel を使う場合）

コンテナ起動:

```bash
docker compose up -d --build
```

状態確認:

```bash
docker compose ps
docker compose logs -f
```

## 2) iOS アプリ起動

iOS アプリ開発には macOS + Xcode が必要です。

```bash
open ReStep.xcodeproj
```

Xcode でビルド・実行先（シミュレータ/実機）を選択して Run してください。

## API 設定（iOS）

API エンドポイントは `ReStep/Info.plist` の値を基準に解決されます。

- `API_BASE_URL`
- `API_ENDPOINT`
- `PROFILE_API_ENDPOINT`
- `STATS_API_ENDPOINT`
- `WALLET_API_ENDPOINT`

`API_BASE_URL` を指定すると、未指定の個別エンドポイントは以下に自動解決されます。

- `user_api.php`
- `user_profile_api.php`
- `user_stats_api.php`
- `user_wallet_api.php`

補足: 実行時に `UserDefaults` で API の上書きも可能です（`Services/UserAPIClient.swift`）。

## デモ時の最短手順

1. `ReStep_Server` を `docker compose up -d --build` で起動
2. `docker compose logs -f nginx` で受信確認できる状態にする
3. Xcode で `ReStep.xcodeproj` を実行
4. ログイン後、ホーム/目標/すれ違い機能を順にデモ

## 運用コマンド（サーバー）

```bash
# 停止
docker compose down

# 再起動
docker compose restart nginx

# 特定サービスのログ
docker compose logs -f php
docker compose logs -f mariadb
```

## 注意事項

- iOS 実機で `localhost` は端末自身を指すため、必要に応じて API ホストを実IP/FQDN に変更してください。
- `cloudflared` サービスを利用しない場合は `.env` の設定を見直すか、compose の対象サービスを限定してください。

## 参考

- サーバー詳細: `ReStep_Server/README.md`
- iOS API 設定: `ReStep/Info.plist`, `ReStep/Services/UserAPIClient.swift`
