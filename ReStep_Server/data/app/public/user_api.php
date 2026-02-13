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
    if ($detail) $err["detail"] = $detail;
    if ($field_errors) $err["fields"] = $field_errors;
    if ($i18n_key) $err["i18n_key"] = $i18n_key;

    send_response($status, ["error" => $err]);
}

function random_token($bytes = 48)
{
    return rtrim(strtr(base64_encode(random_bytes($bytes)), "+/", "-_"), "=");
}

/* ============================
    JSON SUPPORT
============================ */
if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    send_error(405, "method_not_allowed", "Only POST allowed");
}

// JSONリクエスト時は本文をPOSTにマージ
if (stripos($_SERVER["CONTENT_TYPE"] ?? "", "application/json") !== false) {
    $raw = file_get_contents("php://input");
    if ($raw) {
        $json = json_decode($raw, true);
        if ($json) $_POST = array_merge($_POST, $json);
    }
}

/* ============================
    COOKIE HELPERS
============================ */
function set_refresh_cookie($refresh)
{
    setcookie("refresh_token", $refresh, [
        "expires" => time() + REFRESH_TTL,
        "path" => "/",
        "httponly" => true,
        "samesite" => "Strict"
    ]);
}

function clear_cookie()
{
    setcookie("refresh_token", "", time() - 3600, "/");
}

/* ============================
   CLIENT INFO HELPERS
============================ */
function get_client_ip()
{
    $ip = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['HTTP_CLIENT_IP'] ?? $_SERVER['REMOTE_ADDR'] ?? '';
    if (strpos($ip, ',') !== false) {
        $parts = explode(',', $ip);
        $ip = trim($parts[0]);
    }
    return $ip;
}

function derive_device_name($user_agent)
{
    if (!$user_agent) return '不明な端末';
    $ua = strtolower($user_agent);
    if (strpos($ua, 'iphone') !== false) return 'iPhone';
    if (strpos($ua, 'ipad') !== false) return 'iPad';
    if (strpos($ua, 'android') !== false) return 'Android端末';
    if (strpos($ua, 'windows') !== false) return 'Windows PC';
    if (strpos($ua, 'macintosh') !== false || strpos($ua, 'mac os') !== false) return 'Mac';
    if (strpos($ua, 'linux') !== false) return 'Linux';
    return mb_substr($user_agent, 0, 40);
}

/* ============================
   USER AUTH via COOKIE
============================ */
function require_user_cookie($pdo)
{
    // refresh_tokenからユーザーを特定（有効期限・未失効のみ）
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

function require_admin_cookie($pdo)
{
    $user = require_user_cookie($pdo);

    if (!$user) send_error(401, "unauthenticated", "Not logged in");
    if (!$user["is_admin"]) send_error(403, "forbidden", "Admin only");

    return $user;
}

/* ============================
   ACTION
============================ */
$action = $_POST["action"] ?? "";

switch ($action) {

    /* ---------- REGISTER ---------- */
    case "register":
        // 必須項目を取得し、ユーザー作成 + リフレッシュトークン発行
        $login_id = trim($_POST["login_id"] ?? "");
        $email    = trim($_POST["email"] ?? "");
        $pw       = $_POST["password"] ?? "";

        if (!$login_id || !$email || !$pw) {
            send_error(400, "bad_request", "Missing required fields", null, null, "error.missing_fields");
        }

        $hash = password_hash($pw, PASSWORD_DEFAULT);

        try {
            $pdo->beginTransaction();
            // users作成

            $pdo->prepare("
            INSERT INTO users(login_id,email,password)
            VALUES (?,?,?)
        ")->execute([$login_id, $email, $hash]);

            $user_id = $pdo->lastInsertId();

            $stmt = $pdo->prepare("SELECT * FROM users WHERE id = ? LIMIT 1");
            $stmt->execute([$user_id]);
            $user = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!$user) {
                throw new RuntimeException("User fetch failed");
            }

            // トークンを作成して端末情報と一緒に保存
            $refresh = random_token();
            $hash_token = hash("sha256", $refresh);
            $exp = date("Y-m-d H:i:s", time() + REFRESH_TTL);

            $user_agent = $_SERVER['HTTP_USER_AGENT'] ?? null;
            $ip_address = get_client_ip();
            $device_name = trim($_POST['device_name'] ?? '') ?: derive_device_name($user_agent);

            $pdo->prepare("
            INSERT INTO user_refresh_tokens
                (user_id, token_hash, expires_at, device_name, ip_address, user_agent)
            VALUES (?,?,?,?,?,?)
        ")->execute([
                $user["id"],
                $hash_token,
                $exp,
                $device_name,
                $ip_address,
                $user_agent
            ]);

            // 初期コイン付与（ウォレット作成 + 取引ログ）
            $initial_coins = 50;

            $pdo->prepare("
            INSERT INTO user_wallets (user_id, balance)
            VALUES (?, ?)
        ")->execute([$user["id"], $initial_coins]);

            $pdo->prepare("
            INSERT INTO coin_transactions
                (user_id, delta, type, reason, meta, balance_after, client_request_id)
            VALUES
                (?, ?, ?, ?, ?, ?, ?)
        ")->execute([
                $user["id"],
                $initial_coins,
                "init",
                "registration_bonus",
                json_encode(["source" => "registration_bonus"], JSON_UNESCAPED_UNICODE),
                $initial_coins,
                null
            ]);

            $pdo->commit();

            // 認証用Cookieをセット
            set_refresh_cookie($refresh);

            send_response(201, [
                "message" => "Registered",
                "user" => [
                    "login_id" => $user["login_id"],
                    "email"    => $user["email"],
                    "is_admin" => $user["is_admin"]
                ]
            ]);
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }

            if ($e->getCode() === "23000") {
                send_error(409, "conflict", "Login ID or email already exists", null, null, "error.user_exists");
            }

            send_error(500, "db_error", "Database error", null, null, "error.db");
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }

            send_error(500, "server_error", "Registration failed");
        }
        break;

    /* ---------- LOGIN ---------- */
    case "login":
        // login_id または email で検索し、パスワード検証
        $id = trim($_POST["identifier"] ?? "");
        $pw = $_POST["password"] ?? "";

        try {
            $stmt = $pdo->prepare("
                SELECT * FROM users
                WHERE login_id=? OR email=?
                LIMIT 1
            ");
            $stmt->execute([$id, $id]);
            $user = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!$user || !password_verify($pw, $user["password"])) {
                send_error(401, "auth_failed", "Invalid credentials", null, null, "error.invalid_credentials");
            }

            // 新しいリフレッシュトークンを発行
            $refresh = random_token();
            $hash    = hash("sha256", $refresh);
            $exp     = date("Y-m-d H:i:s", time() + REFRESH_TTL);

            $user_agent = $_SERVER['HTTP_USER_AGENT'] ?? null;
            $ip_address = get_client_ip();
            $device_name = trim($_POST['device_name'] ?? '') ?: derive_device_name($user_agent);

            $pdo->beginTransaction();
            // 端末情報込みでトークン保存

            $pdo->prepare(
                "INSERT INTO user_refresh_tokens(user_id, token_hash, expires_at, device_name, ip_address, user_agent) VALUES (?,?,?,?,?,?)"
            )->execute([$user["id"], $hash, $exp, $device_name, $ip_address, $user_agent]);

            $pdo->commit();

            set_refresh_cookie($refresh);

            send_response(200, [
                "message" => "Login OK",
                "user" => [
                    "login_id" => $user["login_id"],
                    "email"    => $user["email"],
                    "is_admin" => $user["is_admin"]
                ]
            ]);
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            send_error(500, "db_error", "Database error", null, null, "error.db");
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            send_error(500, "server_error", "Login failed");
        }
        break;

    /* ---------- STATUS ---------- */
    case "status":
        // Cookie認証の状態確認
        $user = require_user_cookie($pdo);

        if (!$user) {
            send_response(200, ["logged_in" => false]);
        }

        send_response(200, [
            "logged_in" => true,
            "user" => [
                "login_id" => $user["login_id"],
                "email"    => $user["email"],
                "is_admin" => $user["is_admin"],
                "created_at" => $user["created_at"]
            ]
        ]);
        break;

    /* ---------- DEVICES ---------- */
    case "devices":
        // ユーザーの発行済みトークン一覧を返す
        $user = require_user_cookie($pdo);
        if (!$user) send_error(401, "unauthenticated", "Not logged in");

        $stmt = $pdo->prepare(
            "SELECT id, created_at, expires_at, revoked_at, device_name, ip_address, user_agent FROM user_refresh_tokens WHERE user_id = ?"
        );
        $stmt->execute([$user["id"]]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // 現在使用中のトークンをフラグ付け
        $current_token_id = $user["token_id"] ?? null;
        foreach ($rows as &$r) {
            $r["is_current"] = ($current_token_id !== null && (int)$r["id"] === (int)$current_token_id) ? 1 : 0;
        }

        send_response(200, ["devices" => $rows]);
        break;

    /* ---------- LOGOUT ---------- */
    case "logout":
        // 現在のトークンを失効し、Cookieを削除
        $user = require_user_cookie($pdo);
        if ($user) {
            try {
                $pdo->beginTransaction();
                $pdo->prepare(
                    "UPDATE user_refresh_tokens
                    SET revoked_at=NOW()
                    WHERE id=?"
                )->execute([$user["token_id"]]);
                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                send_error(500, "db_error", "Database error", null, null, "error.db");
            } catch (Throwable $e) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                send_error(500, "server_error", "Logout failed");
            }
        }

        clear_cookie();
        send_response(200, ["message" => "Logged out"]);
        break;

    /* ---------- LOGOUT ALL ---------- */
    case "logout_all":
        // 全端末のトークンを失効
        $user = require_user_cookie($pdo);
        if (!$user) send_error(401, "unauthenticated", "Not logged in");
        try {
            $pdo->beginTransaction();
            $pdo->prepare("
                UPDATE user_refresh_tokens
                SET revoked_at=NOW()
                WHERE user_id=?
            ")->execute([$user["id"]]);
            $pdo->commit();
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            send_error(500, "db_error", "Database error", null, null, "error.db");
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            send_error(500, "server_error", "Logout failed");
        }

        clear_cookie();
        send_response(200, ["message" => "Logged out from all devices"]);
        break;

    /* ---------- REVOKE DEVICE ---------- */
    case "revoke_device":
        // 指定トークンを失効（本人のトークンのみ）
        $user = require_user_cookie($pdo);
        if (!$user) send_error(401, "unauthenticated", "Not logged in");

        $token_id = isset($_POST['token_id']) ? (int)$_POST['token_id'] : 0;
        if ($token_id <= 0) send_error(400, "bad_request", "token_id required", null, null, "error.token_id_required");

        try {
            $pdo->beginTransaction();

            $stmt = $pdo->prepare("SELECT user_id FROM user_refresh_tokens WHERE id = ? LIMIT 1");
            $stmt->execute([$token_id]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row) send_error(404, "not_found", "Token not found");
            if ((int)$row['user_id'] !== (int)$user['id']) send_error(403, "forbidden", "Not allowed to revoke this token");

            $pdo->prepare("UPDATE user_refresh_tokens SET revoked_at = NOW() WHERE id = ?")->execute([$token_id]);
            $pdo->commit();
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            send_error(500, "db_error", "Database error", null, null, "error.db");
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            send_error(500, "server_error", "Revoke failed");
        }

        send_response(200, ["message" => "Device revoked", "token_id" => $token_id]);
        break;

    /* ---------- ADMIN USERS ---------- */
    case "admin_users":
        // 管理者のみ、ユーザー一覧取得
        require_admin_cookie($pdo);

        $stmt = $pdo->query("
            SELECT id, login_id, email, is_admin
            FROM users
        ");

        send_response(200, ["users" => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
        break;

    /* ---------- ADMIN FORCE LOGOUT ---------- */
    case "admin_force_logout":
        // 管理者が対象ユーザーを強制ログアウト
        require_admin_cookie($pdo);

        $target = (int)($_POST["user_id"] ?? 0);
        if ($target <= 0) send_error(400, "bad_request", "user_id required", null, null, "error.user_id_required");

        try {
            $pdo->beginTransaction();
            $pdo->prepare("
                UPDATE user_refresh_tokens
                SET revoked_at=NOW()
                WHERE user_id=?
            ")->execute([$target]);
            $pdo->commit();
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            send_error(500, "db_error", "Database error", null, null, "error.db");
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            send_error(500, "server_error", "Force logout failed");
        }

        send_response(200, [
            "message" => "User forcibly logged out",
            "user_id" => $target
        ]);
        break;

    /* ---------- UPDATE PROFILE ---------- */
    case "update_profile":
        // ログインID/メール/パスワードの更新
        $user = require_user_cookie($pdo);
        if (!$user) send_error(401, "unauthenticated", "Not logged in");

        $user_id = $user["id"];
        $login_id = isset($_POST["login_id"]) ? trim($_POST["login_id"]) : null;
        $email = isset($_POST["email"]) ? trim($_POST["email"]) : null;
        $pw = $_POST["password"] ?? null;

        if ($login_id === null && $email === null && $pw === null) {
            send_error(400, "bad_request", "Nothing to update", null, null, "error.nothing_to_update");
        }

        if ($login_id) {
            $stmt = $pdo->prepare("SELECT id FROM users WHERE login_id = ? AND id <> ? LIMIT 1");
            $stmt->execute([$login_id, $user_id]);
            if ($stmt->fetch()) send_error(409, "conflict", "login_id already taken", null, ["login_id" => "taken"], "error.login_id_taken");
        }

        if ($email) {
            $stmt = $pdo->prepare("SELECT id FROM users WHERE email = ? AND id <> ? LIMIT 1");
            $stmt->execute([$email, $user_id]);
            if ($stmt->fetch()) send_error(409, "conflict", "email already taken", null, ["email" => "taken"], "error.email_taken");
        }

        $fields = [];
        $params = [];

        if ($login_id) {
            $fields[] = "login_id = ?";
            $params[] = $login_id;
        }
        if ($email) {
            $fields[] = "email = ?";
            $params[] = $email;
        }
        if ($pw) {
            $hash = password_hash($pw, PASSWORD_DEFAULT);
            $fields[] = "password = ?";
            $params[] = $hash;
        }

        if (!empty($fields)) {
            try {
                $pdo->beginTransaction();
                $params[] = $user_id;
                $sql = "UPDATE users SET " . implode(", ", $fields) . " WHERE id = ?";
                $pdo->prepare($sql)->execute($params);
                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                if ($e->getCode() === "23000") {
                    send_error(409, "conflict", "login_id or email already taken", null, null, "error.conflict");
                }
                send_error(500, "db_error", "Database error", null, null, "error.db");
            } catch (Throwable $e) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                send_error(500, "server_error", "Update failed");
            }
        }

        $stmt = $pdo->prepare("SELECT login_id, email, is_admin FROM users WHERE id = ?");
        $stmt->execute([$user_id]);
        $updated = $stmt->fetch(PDO::FETCH_ASSOC);

        send_response(200, [
            "message" => "Profile updated",
            "user" => $updated
        ]);
        break;

    /* ============================================================
       CLOSE ACCOUNT 
    ============================================================ */
    case "close_account": {
            $user = require_user_cookie($pdo);
            if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");

            $user_id = (int)$user["id"];

            $pw = $_POST["password"] ?? null;
            if ($pw === null || $pw === "") {
                send_error(400, "bad_request", "password required", null, ["password" => "required"], "error.password_required");
            }

            $stmt = $pdo->prepare("SELECT password FROM users WHERE id = ? LIMIT 1");
            $stmt->execute([$user_id]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!$row || !password_verify($pw, $row["password"])) {
                send_error(401, "auth_failed", "Invalid password", null, ["password" => "invalid"], "error.invalid_password");
            }

            try {
                $pdo->beginTransaction();

                $pdo->prepare("DELETE FROM challenge_claims WHERE user_id = ?")->execute([$user_id]);

                $pdo->prepare("DELETE FROM stamp_transactions WHERE user_id = ?")->execute([$user_id]);
                $pdo->prepare("DELETE FROM stamp_daily_earned WHERE user_id = ?")->execute([$user_id]);
                $pdo->prepare("DELETE FROM user_stamps WHERE user_id = ?")->execute([$user_id]);
                $pdo->prepare("DELETE FROM coin_transactions WHERE user_id = ?")->execute([$user_id]);
                $pdo->prepare("DELETE FROM user_wallets WHERE user_id = ?")->execute([$user_id]);
                $pdo->prepare("DELETE FROM user_daily_stats WHERE user_id = ?")->execute([$user_id]);
                $pdo->prepare("DELETE FROM user_refresh_tokens WHERE user_id = ?")->execute([$user_id]);
                $pdo->prepare("DELETE FROM user_profiles WHERE user_id = ?")->execute([$user_id]);
                $pdo->prepare("DELETE FROM users WHERE id = ?")->execute([$user_id]);
                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Failed to close account", $e->getMessage(), null, "error.server_error");
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Failed to close account", $e->getMessage(), null, "error.server_error");
            }

            clear_cookie();

            send_response(200, ["message" => "Account closed"]);
            break;
        }

    default:
        send_error(400, "bad_request", "Unknown action", null, null, "error.unknown_action");
}