# ReStep Server

ReStep APIサーバーのDocker Compose環境です。

## サービス構成

| サービス | イメージ | 説明 |
|----------|----------|------|
| mariadb | mariadb:11 | データベースサーバー |
| minio | minio/minio:latest | S3互換オブジェクトストレージ |
| minio-init | minio/mc:latest | MinIOバケット初期化 |
| php | カスタムビルド | PHP-FPMアプリケーション |
| nginx | nginx:alpine | APIサーバー |
| phpmyadmin | phpmyadmin:latest | データベース管理ツール |
| cloudflared | cloudflare/cloudflared | Cloudflare Tunnel（外部公開） |

## 環境構築手順

### 1. 前提条件

- Docker および Docker Compose がインストールされていること
- Cloudflare Tunnelのトークンを取得済みであること

### 2. 環境変数の設定

`.env.sample` をコピーして `.env` を作成します。

```bash
cp .env.sample .env
```

`.env` を編集して各値を設定します。

```env
# タイムゾーン
TZ=Asia/Tokyo

# データベース設定
DB_ROOT_PASSWORD=<rootパスワード>
DB_NAME=<データベース名>
DB_USER=<ユーザー名>
DB_PASSWORD=<パスワード>
DB_PORT=3306

# Tailscale IP（MariaDBをTailscale内部で接続する用）
TS_IP=<Tailscale IP>

# Nginx
NGINX_HOST=127.0.0.1
NGINX_PORT=8080

# phpMyAdmin
PMA_UPLOAD_LIMIT=256M

# Cloudflare Tunnel
CLOUDFLARE_TUNNEL_TOKEN=<トンネルトークン>

# ホスト名（Cloudflare Tunnel用）
API_HOST=<APIのホスト名>
PMA_HOST=<phpMyAdminのホスト名>

# MinIO (S3互換ストレージ)
MINIO_ROOT_USER=<MinIOユーザー>
MINIO_ROOT_PASSWORD=<MinIOパスワード>
MINIO_BUCKET=restep-uploads
MINIO_PUBLIC_URL=<公開アクセス用URL>

# CORS設定
CORS_ORIGIN=<許可するオリジン>
```

### 3. コンテナの起動

```bash
docker compose up -d
```

### 4. 動作確認

```bash
# コンテナの状態確認
docker compose ps

# ログ確認
docker compose logs -f
```

## 開発・運用コマンド

### コンテナ操作

```bash
# 全コンテナ起動
docker compose up -d

# 全コンテナ停止
docker compose down

# 特定のコンテナを再起動
docker compose restart nginx

# 設定変更後の再作成
docker compose up -d --force-recreate nginx
```

### ログ確認

```bash
# 全サービスのログ
docker compose logs -f

# 特定サービスのログ
docker compose logs -f nginx
docker compose logs -f php
docker compose logs -f minio
```

### データベース操作

```bash
# MySQLに接続
docker compose exec mariadb mariadb -u root -p

# データベースのバックアップ
docker compose exec mariadb sh -lc "mariadb-dump --no-defaults -u root -p <DB名> > /tmp/backup.sql"

docker cp mariadb:/tmp/backup.sql backup.sql

# データベースのリストア
docker cp backup.sql mariadb:/tmp/backup.sql

docker compose exec mariadb sh -lc "mariadb --no-defaults -u root -p <DB名> < /tmp/backup.sql"
```

### Composer

`composer install` はコンテナ起動時に自動実行されます（`vendor/` が存在しない場合）。

手動で実行する場合:

```bash
# 依存関係を更新
docker compose exec php composer update

# パッケージを追加
docker compose exec php composer require <パッケージ名>
```

## ネットワーク構成

```
[Internet]
    |
[Cloudflare Tunnel] (cloudflared)
    |
[Nginx] :80
    |
[PHP-FPM] :9000
[MariaDB] :3306    [MinIO] :9000 (console :9001)
```

- Nginx は `127.0.0.1:8080` でローカルからアクセス可能
- MariaDB は Tailscale IP 経由で外部接続可能
- MinIO は `9000`（API）と `9001`（Console）を公開
- 外部公開は Cloudflare Tunnel 経由のみ

## トラブルシューティング

### コンテナが起動しない

```bash
# ログを確認
docker compose logs <サービス名>

# コンテナを再作成
docker compose up -d --force-recreate <サービス名>
```

### データベースに接続できない

1. MariaDBコンテナが起動しているか確認
   ```bash
   docker compose ps mariadb
   ```

2. 認証情報が正しいか確認
   ```bash
   docker compose exec mariadb mysql -u <ユーザー名> -p
   ```

3. PHPからの接続を確認
   ```bash
   docker compose exec php php -r "new PDO('mysql:host=mariadb;dbname=<DB名>', '<ユーザー名>', '<パスワード>');"
   ```

### CORSエラーが発生する

1. `.env` の `CORS_ORIGIN` が正しく設定されているか確認
2. Nginxコンテナを再起動
   ```bash
   docker compose up -d --force-recreate nginx
   ```

### Cloudflare Tunnelが接続できない

1. トークンが正しいか確認
2. Cloudflareダッシュボードでトンネルのステータスを確認
3. ログを確認
   ```bash
   docker compose logs cloudflared
   ```

### `docker compose` が permission denied になる

`usermod -aG docker <user>` の直後は、同じSSHセッションにグループ変更が反映されません。

```bash
# 一時反映（または再ログイン）
newgrp docker

# 反映確認
id -nG | grep docker
```

暫定回避としては `sudo docker compose ...` でも実行できます。

## データベース初期化

初回起動時に `data/mariadb/init/` 内のSQLファイルが自動実行されます。

- `01_schema.sql`: テーブル定義

テーブルを再作成する場合:

```bash
# データを削除して再初期化
docker compose down
find data/db -mindepth 1 -delete
docker compose up -d
```

## ディレクトリ構成

```
.
├── docker-compose.yml
├── Dockerfile
├── docker-entrypoint.sh  # コンテナ起動時の初期化スクリプト
├── .env.sample
└── data/
    ├── app/              # PHPアプリケーション
   │   └── public/       # ドキュメントルート
    ├── db/               # MariaDBデータ（永続化）
    ├── mariadb/
    │   └── init/         # DB初期化スクリプト
    └── nginx/
        └── default.conf.template
```
