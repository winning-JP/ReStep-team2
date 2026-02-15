<?php
header("Content-Type: application/json; charset=utf-8");
require_once "config.php";

/* ============================
   HELPERS
============================ */
function send_response($status, $data = [])
{
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function send_error($status, $code, $message, $detail = null)
{
    $err = ["code" => $code, "message" => $message];
    if ($detail !== null) $err["detail"] = $detail;
    send_response($status, ["error" => $err]);
}

/* ============================
   AUTH via COOKIE
============================ */
function require_login($pdo)
{
    $refresh = $_COOKIE["refresh_token"] ?? "";
    if (!$refresh) send_error(401, "unauthenticated", "Not logged in");

    $hash = hash("sha256", $refresh);
    $stmt = $pdo->prepare("
        SELECT u.*
        FROM user_refresh_tokens rt
        JOIN users u ON u.id = rt.user_id
        WHERE rt.token_hash = ?
          AND rt.revoked_at IS NULL
          AND rt.expires_at > NOW()
        LIMIT 1
    ");
    $stmt->execute([$hash]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) send_error(401, "unauthenticated", "Not logged in");
    return $user;
}

/* ============================
   S3 (MinIO) HELPERS
============================ */
function s3_config()
{
    return [
        "endpoint" => getenv("MINIO_ENDPOINT") ?: "http://minio:9000",
        "access_key" => getenv("MINIO_ROOT_USER") ?: "minioadmin",
        "secret_key" => getenv("MINIO_ROOT_PASSWORD") ?: "minioadmin",
        "bucket" => getenv("MINIO_BUCKET") ?: "restep-uploads",
        "public_url" => getenv("MINIO_PUBLIC_URL") ?: "http://minio:9000",
        "region" => "us-east-1"
    ];
}

function s3_sign($method, $uri, $headers, $payload_hash, $secret_key, $access_key, $region, $service = "s3")
{
    $datetime = gmdate("Ymd\THis\Z");
    $date = gmdate("Ymd");

    $canonical_headers = "";
    $signed_header_names = [];
    ksort($headers);
    foreach ($headers as $k => $v) {
        $canonical_headers .= strtolower($k) . ":" . trim($v) . "\n";
        $signed_header_names[] = strtolower($k);
    }
    $signed_headers = implode(";", $signed_header_names);

    $canonical_request = implode("\n", [
        $method,
        $uri,
        "",  // query string
        $canonical_headers,
        $signed_headers,
        $payload_hash
    ]);

    $scope = "{$date}/{$region}/{$service}/aws4_request";
    $string_to_sign = implode("\n", [
        "AWS4-HMAC-SHA256",
        $datetime,
        $scope,
        hash("sha256", $canonical_request)
    ]);

    $date_key = hash_hmac("sha256", $date, "AWS4" . $secret_key, true);
    $region_key = hash_hmac("sha256", $region, $date_key, true);
    $service_key = hash_hmac("sha256", $service, $region_key, true);
    $signing_key = hash_hmac("sha256", "aws4_request", $service_key, true);
    $signature = hash_hmac("sha256", $string_to_sign, $signing_key);

    $authorization = "AWS4-HMAC-SHA256 Credential={$access_key}/{$scope}, SignedHeaders={$signed_headers}, Signature={$signature}";

    return ["authorization" => $authorization, "x-amz-date" => $datetime];
}

function s3_ensure_bucket($cfg)
{
    $uri = "/{$cfg['bucket']}";
    $datetime = gmdate("Ymd\THis\Z");
    $host = parse_url($cfg["endpoint"], PHP_URL_HOST) . ":" . (parse_url($cfg["endpoint"], PHP_URL_PORT) ?: 9000);

    $headers = [
        "host" => $host,
        "x-amz-content-sha256" => "UNSIGNED-PAYLOAD",
        "x-amz-date" => $datetime
    ];

    $auth = s3_sign("PUT", $uri, $headers, "UNSIGNED-PAYLOAD", $cfg["secret_key"], $cfg["access_key"], $cfg["region"]);
    $headers["authorization"] = $auth["authorization"];
    $headers["x-amz-date"] = $auth["x-amz-date"];

    $header_lines = [];
    foreach ($headers as $k => $v) {
        $header_lines[] = "{$k}: {$v}";
    }

    $ch = curl_init($cfg["endpoint"] . $uri);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PUT");
    curl_setopt($ch, CURLOPT_HTTPHEADER, $header_lines);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 5);
    curl_exec($ch);
    curl_close($ch);
}

function s3_put_object($cfg, $key, $data, $content_type)
{
    $uri = "/{$cfg['bucket']}/{$key}";
    $payload_hash = hash("sha256", $data);
    $host = parse_url($cfg["endpoint"], PHP_URL_HOST) . ":" . (parse_url($cfg["endpoint"], PHP_URL_PORT) ?: 9000);

    $headers = [
        "content-length" => strlen($data),
        "content-type" => $content_type,
        "host" => $host,
        "x-amz-content-sha256" => $payload_hash,
        "x-amz-date" => gmdate("Ymd\THis\Z")
    ];

    $auth = s3_sign("PUT", $uri, $headers, $payload_hash, $cfg["secret_key"], $cfg["access_key"], $cfg["region"]);
    $headers["authorization"] = $auth["authorization"];
    $headers["x-amz-date"] = $auth["x-amz-date"];

    $header_lines = [];
    foreach ($headers as $k => $v) {
        $header_lines[] = "{$k}: {$v}";
    }

    $ch = curl_init($cfg["endpoint"] . $uri);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PUT");
    curl_setopt($ch, CURLOPT_HTTPHEADER, $header_lines);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    $result = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    if ($http_code !== 200) {
        return ["ok" => false, "error" => "S3 PUT failed: HTTP {$http_code} - {$err} - {$result}"];
    }

    $public_url = rtrim($cfg["public_url"], "/") . "/{$cfg['bucket']}/{$key}";
    return ["ok" => true, "url" => $public_url, "key" => $key];
}

function s3_delete_object($cfg, $key)
{
    $uri = "/{$cfg['bucket']}/{$key}";
    $host = parse_url($cfg["endpoint"], PHP_URL_HOST) . ":" . (parse_url($cfg["endpoint"], PHP_URL_PORT) ?: 9000);

    $headers = [
        "host" => $host,
        "x-amz-content-sha256" => "UNSIGNED-PAYLOAD",
        "x-amz-date" => gmdate("Ymd\THis\Z")
    ];

    $auth = s3_sign("DELETE", $uri, $headers, "UNSIGNED-PAYLOAD", $cfg["secret_key"], $cfg["access_key"], $cfg["region"]);
    $headers["authorization"] = $auth["authorization"];
    $headers["x-amz-date"] = $auth["x-amz-date"];

    $header_lines = [];
    foreach ($headers as $k => $v) {
        $header_lines[] = "{$k}: {$v}";
    }

    $ch = curl_init($cfg["endpoint"] . $uri);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "DELETE");
    curl_setopt($ch, CURLOPT_HTTPHEADER, $header_lines);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    curl_exec($ch);
    curl_close($ch);
}

/* ============================
   MAIN: IMAGE UPLOAD
============================ */
if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    send_error(405, "method_not_allowed", "Only POST allowed");
}

$user = require_login($pdo);
$uid = (int)$user["id"];

// multipart/form-data でアップロード
if (!isset($_FILES["image"])) {
    send_error(422, "validation_error", "image file is required");
}

$file = $_FILES["image"];
if ($file["error"] !== UPLOAD_ERR_OK) {
    send_error(422, "upload_error", "Upload failed", "error_code=" . $file["error"]);
}

// サイズ制限 (10MB)
$max_size = 10 * 1024 * 1024;
if ($file["size"] > $max_size) {
    send_error(413, "file_too_large", "File size exceeds 10MB limit");
}

// MIMEタイプチェック（ブラウザ互換性のため HEIC は受け付けない）
$allowed_types = ["image/jpeg", "image/png", "image/webp"];
$finfo = new finfo(FILEINFO_MIME_TYPE);
$mime = $finfo->file($file["tmp_name"]);
if (!in_array($mime, $allowed_types)) {
    send_error(422, "invalid_type", "Only JPEG, PNG, WebP allowed", $mime);
}

// 拡張子決定
$ext_map = [
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/webp" => "webp"
];
$ext = $ext_map[$mime] ?? "jpg";

// カテゴリ（オプション）
$category = isset($_POST["category"]) ? preg_replace('/[^a-z0-9_-]/', '', strtolower($_POST["category"])) : "general";

// S3 キー生成
$date_prefix = date("Y/m/d");
$unique = bin2hex(random_bytes(16));
$key = "{$category}/{$date_prefix}/{$uid}_{$unique}.{$ext}";

// アップロード
$data = file_get_contents($file["tmp_name"]);
$cfg = s3_config();

// バケット確認（初回のみ）
s3_ensure_bucket($cfg);

$result = s3_put_object($cfg, $key, $data, $mime);

if (!$result["ok"]) {
    send_error(500, "upload_failed", "Failed to upload to storage", $result["error"]);
}

send_response(200, [
    "message" => "ok",
    "url" => $result["url"],
    "key" => $result["key"],
    "user_id" => $uid,
    "size" => $file["size"],
    "content_type" => $mime
]);
