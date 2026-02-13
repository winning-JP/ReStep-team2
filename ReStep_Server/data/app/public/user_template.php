<?php
header("Content-Type: application/json; charset=utf-8");
require_once "config.php";

/* ============================
   CONFIG
============================ */
const REFRESH_TTL = 2592000;

/* ============================
   HELPERS
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
   COOKIE HELPERS（必要なら）
============================ */
function clear_cookie()
{
    setcookie("refresh_token", "", time() - 3600, "/");
}

/* ============================
   AUTH via COOKIE（user_api.php と同等）
============================ */
function require_user_cookie($pdo)
{
    $refresh = $_COOKIE["refresh_token"] ?? "";
    if (!$refresh) return null;

    $hash = hash("sha256", $refresh);

    $stmt = $pdo->prepare("
        SELECT u.*, rt.id AS token_id
        FROM user_refresh_tokens rt
        JOIN users u ON u.id = rt.user_id
        WHERE rt.token_hash = ?
          AND rt.revoked_at IS NULL
          AND rt.expires_at > NOW()
        LIMIT 1
    ");
    $stmt->execute([$hash]);
    return $stmt->fetch(PDO::FETCH_ASSOC);
}

function require_login($pdo)
{
    $user = require_user_cookie($pdo);
    if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");
    return $user;
}

function require_admin($pdo)
{
    $user = require_login($pdo);
    if (!$user["is_admin"]) send_error(403, "forbidden", "Admin only", null, null, "auth.admin_only");
    return $user;
}

/* ============================
   ACTION
============================ */
$action = $_POST["action"] ?? "";

switch ($action) {

    /*
     * ===== 例: ログイン必須のAPI =====
     * Request:
     *   { "action": "ping" }
     * Response:
     *   { "message": "ok", "user_id": 123 }
     */
    case "ping": {
            $user = require_login($pdo);

            send_response(200, [
                "message" => "ok",
                "user_id" => (int)$user["id"]
            ]);
            break;
        }

        /*
     * ===== 例: 管理者必須のAPI =====
     * Request:
     *   { "action": "admin_ping" }
     */
    case "admin_ping": {
            $admin = require_admin($pdo);

            send_response(200, [
                "message" => "ok",
                "admin_id" => (int)$admin["id"]
            ]);
            break;
        }

        /*
     * ===== ここに新しい action を追加していく =====
     */

    default:
        send_error(400, "bad_request", "Unknown action", null, null, "error.unknown_action");
}