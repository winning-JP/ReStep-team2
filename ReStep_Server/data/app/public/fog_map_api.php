<?php
header("Content-Type: application/json; charset=utf-8");
require_once "config.php";

/* ============================
   HELPERS (shared with wallet)
============================ */
function send_response($status, $data = [])
{
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function send_error($status, $code, $message, $detail = null, $field_errors = null, $i18n_key = null)
{
    $err = [
        "code" => $code,
        "message" => $message
    ];
    if ($detail !== null) $err["detail"] = $detail;
    if ($field_errors) $err["fields"] = $field_errors;
    if ($i18n_key) $err["i18n_key"] = $i18n_key;
    send_response($status, ["error" => $err]);
}

/* ============================
   JSON SUPPORT
============================ */
if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    send_error(405, "method_not_allowed", "Only POST allowed");
}

if (stripos($_SERVER["CONTENT_TYPE"] ?? "", "application/json") !== false) {
    $raw = file_get_contents("php://input");
    if ($raw) {
        $json = json_decode($raw, true);
        if (is_array($json)) $_POST = array_merge($_POST, $json);
    }
}

/* ============================
   AUTH via COOKIE
============================ */
function require_login($pdo)
{
    $refresh = $_COOKIE["refresh_token"] ?? "";
    if (!$refresh) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");

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
    if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");
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
        "public_url" => rtrim(getenv("MINIO_PUBLIC_URL") ?: "http://minio:9000", "/"),
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
        "",
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

function s3_delete_object_key($cfg, $key)
{
    if ($key === "") return;
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

function s3_key_from_public_url($cfg, $url)
{
    if (!$url) return null;
    $url = trim((string)$url);
    if ($url === "") return null;

    $prefix = $cfg["public_url"] . "/" . $cfg["bucket"] . "/";
    if (strpos($url, $prefix) !== 0) return null;

    $key = substr($url, strlen($prefix));
    return $key === false ? null : ltrim($key, "/");
}

function s3_delete_by_public_url($url)
{
    $cfg = s3_config();
    $key = s3_key_from_public_url($cfg, $url);
    if ($key === null || $key === "") return;
    s3_delete_object_key($cfg, $key);
}

/* ============================
   ACTION
============================ */
$action = $_POST["action"] ?? "";

switch ($action) {

    case "visit_sync": {
            // 訪問地点を一括同期
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $visits_raw = $_POST["visits"] ?? [];
            if (!is_array($visits_raw) || count($visits_raw) === 0) {
                send_error(422, "validation_error", "visits array is required");
            }
            if (count($visits_raw) > 500) {
                send_error(422, "validation_error", "Too many visits (max 500)");
            }

            $inserted = 0;
            $pdo->beginTransaction();
            try {
                $ins = $pdo->prepare("INSERT INTO fog_visits (user_id, latitude, longitude, visited_at) VALUES (?, ?, ?, ?)");

                foreach ($visits_raw as $v) {
                    $lat = isset($v["latitude"]) ? (float)$v["latitude"] : null;
                    $lng = isset($v["longitude"]) ? (float)$v["longitude"] : null;
                    $at = isset($v["visited_at"]) ? (string)$v["visited_at"] : date("Y-m-d H:i:s");

                    if ($lat === null || $lng === null) continue;
                    if ($lat < -90 || $lat > 90 || $lng < -180 || $lng > 180) continue;

                    $ins->execute([$uid, $lat, $lng, $at]);
                    $inserted++;
                }

                $pdo->commit();

                send_response(200, [
                    "message" => "ok",
                    "user_id" => $uid,
                    "inserted" => $inserted
                ]);
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "visit_list": {
            // 訪問地点一覧（ページング）
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $limit_raw = $_POST["limit"] ?? 1000;
            $limit = max(1, min(5000, (int)$limit_raw));

            $after_id_raw = $_POST["after_id"] ?? null;
            $after_id = ($after_id_raw !== null && $after_id_raw !== "") ? (int)$after_id_raw : null;

            try {
                if ($after_id) {
                    $stmt = $pdo->prepare("
                        SELECT id, latitude, longitude, visited_at
                        FROM fog_visits
                        WHERE user_id = ? AND id > ?
                        ORDER BY id ASC
                        LIMIT " . (int)$limit . "
                    ");
                    $stmt->execute([$uid, $after_id]);
                } else {
                    $stmt = $pdo->prepare("
                        SELECT id, latitude, longitude, visited_at
                        FROM fog_visits
                        WHERE user_id = ?
                        ORDER BY id ASC
                        LIMIT " . (int)$limit . "
                    ");
                    $stmt->execute([$uid]);
                }

                $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
                $items = [];
                $next_after_id = null;

                foreach ($rows as $r) {
                    $items[] = [
                        "id" => (int)$r["id"],
                        "latitude" => (float)$r["latitude"],
                        "longitude" => (float)$r["longitude"],
                        "visited_at" => $r["visited_at"]
                    ];
                    $next_after_id = (int)$r["id"];
                }

                send_response(200, [
                    "user_id" => $uid,
                    "items" => $items,
                    "next_after_id" => $next_after_id
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "waypoint_add": {
            // ウェイポイント追加
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $lat = isset($_POST["latitude"]) ? (float)$_POST["latitude"] : null;
            $lng = isset($_POST["longitude"]) ? (float)$_POST["longitude"] : null;

            if ($lat === null || $lng === null) send_error(422, "validation_error", "latitude and longitude required");
            if ($lat < -90 || $lat > 90 || $lng < -180 || $lng > 180) send_error(422, "validation_error", "Invalid coordinates");

            $title = isset($_POST["title"]) ? mb_substr((string)$_POST["title"], 0, 100) : null;
            $note = isset($_POST["note"]) ? (string)$_POST["note"] : null;
            $photo_url = isset($_POST["photo_url"]) ? mb_substr((string)$_POST["photo_url"], 0, 500) : null;

            try {
                $ins = $pdo->prepare("INSERT INTO waypoints (user_id, latitude, longitude, title, note, photo_url) VALUES (?, ?, ?, ?, ?, ?)");
                $ins->execute([$uid, $lat, $lng, $title, $note, $photo_url]);
                $wp_id = (int)$pdo->lastInsertId();

                send_response(200, [
                    "message" => "ok",
                    "waypoint_id" => $wp_id,
                    "user_id" => $uid
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "waypoint_list": {
            // ウェイポイント一覧
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            try {
                $stmt = $pdo->prepare("
                    SELECT id, latitude, longitude, title, note, photo_url, created_at
                    FROM waypoints
                    WHERE user_id = ?
                    ORDER BY created_at DESC
                ");
                $stmt->execute([$uid]);
                $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

                $items = [];
                foreach ($rows as $r) {
                    $items[] = [
                        "id" => (int)$r["id"],
                        "latitude" => (float)$r["latitude"],
                        "longitude" => (float)$r["longitude"],
                        "title" => $r["title"],
                        "note" => $r["note"],
                        "photo_url" => $r["photo_url"],
                        "created_at" => $r["created_at"]
                    ];
                }

                send_response(200, [
                    "user_id" => $uid,
                    "items" => $items
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "waypoint_update": {
            // ウェイポイント更新
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $wp_id = isset($_POST["waypoint_id"]) ? (int)$_POST["waypoint_id"] : null;
            if (!$wp_id) send_error(422, "validation_error", "waypoint_id is required");

            // 所有権確認
            $check = $pdo->prepare("SELECT id, title, note, photo_url FROM waypoints WHERE id = ? AND user_id = ?");
            $check->execute([$wp_id, $uid]);
            $existing = $check->fetch(PDO::FETCH_ASSOC);
            if (!$existing) send_error(404, "not_found", "Waypoint not found");

            // 更新可能フィールド
            $title = isset($_POST["title"]) ? mb_substr((string)$_POST["title"], 0, 100) : $existing["title"];
            $note = isset($_POST["note"]) ? (string)$_POST["note"] : $existing["note"];
            $photo_url = array_key_exists("photo_url", $_POST) ? (
                $_POST["photo_url"] === null ? null : mb_substr((string)$_POST["photo_url"], 0, 500)
            ) : $existing["photo_url"];

            try {
                $stmt = $pdo->prepare("UPDATE waypoints SET title = ?, note = ?, photo_url = ? WHERE id = ? AND user_id = ?");
                $stmt->execute([$title, $note, $photo_url, $wp_id, $uid]);

                // 写真変更時は旧オブジェクトを削除
                $old_photo = $existing["photo_url"] ?? null;
                if ($old_photo && $old_photo !== $photo_url) {
                    try {
                        s3_delete_by_public_url($old_photo);
                    } catch (Exception $e) {
                        error_log("waypoint_update old photo delete failed: " . $e->getMessage());
                    }
                }

                send_response(200, [
                    "message" => "ok",
                    "waypoint_id" => $wp_id,
                    "user_id" => $uid,
                    "title" => $title,
                    "note" => $note,
                    "photo_url" => $photo_url
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "waypoint_delete": {
            // ウェイポイント削除
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $wp_id = isset($_POST["waypoint_id"]) ? (int)$_POST["waypoint_id"] : null;
            if (!$wp_id) send_error(422, "validation_error", "waypoint_id is required");

            try {
                // 先に写真URLを取得してから削除
                $sel = $pdo->prepare("SELECT photo_url FROM waypoints WHERE id = ? AND user_id = ?");
                $sel->execute([$wp_id, $uid]);
                $row = $sel->fetch(PDO::FETCH_ASSOC);
                $old_photo = $row["photo_url"] ?? null;

                $stmt = $pdo->prepare("DELETE FROM waypoints WHERE id = ? AND user_id = ?");
                $stmt->execute([$wp_id, $uid]);
                $deleted = $stmt->rowCount() > 0;

                if ($deleted && $old_photo) {
                    try {
                        s3_delete_by_public_url($old_photo);
                    } catch (Exception $e) {
                        error_log("waypoint_delete photo delete failed: " . $e->getMessage());
                    }
                }

                send_response(200, [
                    "message" => "ok",
                    "deleted" => $deleted,
                    "waypoint_id" => $wp_id
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    default:
        send_error(400, "bad_request", "Unknown action", null, null, "error.unknown_action");
}
