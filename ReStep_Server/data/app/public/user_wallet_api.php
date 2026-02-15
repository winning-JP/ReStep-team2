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

function require_int_field($key, $min = null, $max = null)
{
    $v = $_POST[$key] ?? null;
    if ($v === null || $v === "") return [null, "$key is required"];
    if (!is_numeric($v) || (string)(int)$v !== (string)$v && (string)(int)$v !== (string)intval($v)) {
    }
    $iv = (int)$v;
    if ($min !== null && $iv < $min) return [null, "$key must be >= $min"];
    if ($max !== null && $iv > $max) return [null, "$key must be <= $max"];
    return [$iv, null];
}

function require_string_field($key, $maxlen = 255, $required = false)
{
    $v = $_POST[$key] ?? null;
    if (($v === null || $v === "") && $required) return [null, "$key is required"];
    if ($v === null) return [null, null];
    $sv = (string)$v;
    if (mb_strlen($sv) > $maxlen) return [null, "$key is too long"];
    return [$sv, null];
}

/* ============================
   JSON SUPPORT
============================ */
if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    send_error(405, "method_not_allowed", "Only POST allowed");
}

// JSONリクエストをPOSTへマージ
if (stripos($_SERVER["CONTENT_TYPE"] ?? "", "application/json") !== false) {
    $raw = file_get_contents("php://input");
    if ($raw) {
        $json = json_decode($raw, true);
        if (is_array($json)) $_POST = array_merge($_POST, $json);
    }
}

/* ============================
   COOKIE HELPERS
============================ */
function clear_cookie()
{
    setcookie("refresh_token", "", time() - 3600, "/");
}

/* ============================
   AUTH via COOKIE
============================ */
function require_user_cookie($pdo)
{
    // refresh_tokenからユーザーを復元
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
    // ログイン必須
    $user = require_user_cookie($pdo);
    if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");
    return $user;
}

function require_admin($pdo)
{
    // 管理者必須
    $user = require_login($pdo);
    if (!$user["is_admin"]) send_error(403, "forbidden", "Admin only", null, null, "auth.admin_only");
    return $user;
}

/* ============================
   COIN CORE
============================ */
function ensure_wallet_exists($pdo, $user_id)
{
    // ユーザーのウォレット行を作成（既存なら無視）
    $stmt = $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance) VALUES (?, 0)");
    $stmt->execute([$user_id]);
}

/* ============================
   STAMP CORE
============================ */
function ensure_stamp_wallet_exists($pdo, $user_id)
{
    // スタンプ用ウォレット行を作成（既存なら無視）
    $stmt = $pdo->prepare("INSERT IGNORE INTO user_stamps (user_id, balance, total_earned) VALUES (?, 0, 0)");
    $stmt->execute([$user_id]);
}

function get_stamp_balance($pdo, $user_id)
{
    // スタンプ残高を取得
    ensure_stamp_wallet_exists($pdo, $user_id);
    $stmt = $pdo->prepare("SELECT balance, total_earned FROM user_stamps WHERE user_id = ? LIMIT 1");
    $stmt->execute([$user_id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ? ["balance" => (int)$row["balance"], "total_earned" => (int)$row["total_earned"]] : ["balance" => 0, "total_earned" => 0];
}

function apply_stamp_delta($pdo, $user_id, $delta, $type, $reason = null, $meta = null, $client_request_id = null)
{
    // スタンプ増減（トランザクション + 冪等処理）
    if (!is_int($delta)) $delta = (int)$delta;
    if ($delta === 0) {
        send_error(400, "bad_request", "delta must not be 0");
    }

    $pdo->beginTransaction();
    try {
        ensure_stamp_wallet_exists($pdo, $user_id);

        $stmt = $pdo->prepare("SELECT balance, total_earned FROM user_stamps WHERE user_id = ? FOR UPDATE");
        $stmt->execute([$user_id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        $before = $row ? (int)$row["balance"] : 0;
        $total = $row ? (int)$row["total_earned"] : 0;

        $after = $before + $delta;
        if ($after < 0) {
            $pdo->rollBack();
            send_error(409, "insufficient_stamps", "Not enough stamps", ["balance" => $before, "required" => -$delta], null, "stamp.insufficient");
        }

        if ($client_request_id) {
            $check = $pdo->prepare("
                SELECT id, balance_after
                FROM stamp_transactions
                WHERE user_id = ? AND client_request_id = ?
                LIMIT 1
            ");
            $check->execute([$user_id, $client_request_id]);
            $existing = $check->fetch(PDO::FETCH_ASSOC);
            if ($existing) {
                $pdo->commit();
                return [
                    "transaction_id" => (int)$existing["id"],
                    "balance" => (int)$existing["balance_after"],
                    "idempotent" => true
                ];
            }
        }

        $new_total = $total;
        if ($delta > 0) {
            $new_total = $total + $delta;
        }

        $up = $pdo->prepare("UPDATE user_stamps SET balance = ?, total_earned = ? WHERE user_id = ?");
        $up->execute([$after, $new_total, $user_id]);

        $meta_json = null;
        if ($meta !== null) {
            $meta_json = is_string($meta) ? json_encode(["value" => $meta], JSON_UNESCAPED_UNICODE) : json_encode($meta, JSON_UNESCAPED_UNICODE);
        }

        $ins = $pdo->prepare("
            INSERT INTO stamp_transactions
                (user_id, delta, type, reason, meta, balance_after, client_request_id)
            VALUES
                (?, ?, ?, ?, ?, ?, ?)
        ");
        $ins->execute([
            $user_id,
            $delta,
            $type,
            $reason,
            $meta_json,
            $after,
            $client_request_id
        ]);

        $tx_id = (int)$pdo->lastInsertId();
        $pdo->commit();

        return [
            "transaction_id" => $tx_id,
            "balance" => $after,
            "idempotent" => false
        ];
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();

        if (($e->getCode() === "23000") && $client_request_id) {
            $stmt = $pdo->prepare("
                SELECT id, balance_after
                FROM stamp_transactions
                WHERE user_id = ? AND client_request_id = ?
                LIMIT 1
            ");
            $stmt->execute([$user_id, $client_request_id]);
            $existing = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($existing) {
                return [
                    "transaction_id" => (int)$existing["id"],
                    "balance" => (int)$existing["balance_after"],
                    "idempotent" => true
                ];
            }
        }

        send_error(500, "db_error", "Database error", $e->getMessage());
    } catch (Exception $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        send_error(500, "server_error", "Server error", $e->getMessage());
    }
}

function get_balance($pdo, $user_id)
{
    // コイン残高を取得
    ensure_wallet_exists($pdo, $user_id);
    $stmt = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1");
    $stmt->execute([$user_id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ? (int)$row["balance"] : 0;
}

function register_wallet_if_missing($pdo, $user_id, $initial_balance)
{
    // 初回ウォレット登録（必要なら初期付与）
    $balance = max(0, (int)$initial_balance);
    $pdo->beginTransaction();
    try {
        $stmt = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? FOR UPDATE");
        $stmt->execute([$user_id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            $pdo->commit();
            return [
                "registered" => false,
                "balance" => (int)$row["balance"],
                "transaction_id" => null
            ];
        }

        $ins = $pdo->prepare("INSERT INTO user_wallets (user_id, balance) VALUES (?, ?)");
        $ins->execute([$user_id, $balance]);

        $tx_id = null;
        if ($balance > 0) {
            $meta_json = json_encode(["source" => "client_migration"], JSON_UNESCAPED_UNICODE);
            $insTx = $pdo->prepare("
                INSERT INTO coin_transactions
                    (user_id, delta, type, reason, meta, balance_after, client_request_id)
                VALUES
                    (?, ?, ?, ?, ?, ?, ?)
            ");
            $insTx->execute([
                $user_id,
                $balance,
                "init",
                "wallet_register",
                $meta_json,
                $balance,
                null
            ]);
            $tx_id = (int)$pdo->lastInsertId();
        }

        $pdo->commit();
        return [
            "registered" => true,
            "balance" => $balance,
            "transaction_id" => $tx_id
        ];
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        if ($e->getCode() === "23000") {
            $stmt = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? LIMIT 1");
            $stmt->execute([$user_id]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            return [
                "registered" => false,
                "balance" => $row ? (int)$row["balance"] : 0,
                "transaction_id" => null
            ];
        }
        send_error(500, "db_error", "Database error", $e->getMessage());
    } catch (Exception $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        send_error(500, "server_error", "Server error", $e->getMessage());
    }
}

function apply_coin_delta($pdo, $user_id, $delta, $type, $reason = null, $meta = null, $client_request_id = null)
{
    // コイン増減（トランザクション + 冪等処理）
    if (!is_int($delta)) $delta = (int)$delta;
    if ($delta === 0) {
        send_error(400, "bad_request", "delta must not be 0");
    }

    $pdo->beginTransaction();
    try {
        ensure_wallet_exists($pdo, $user_id);

        $stmt = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? FOR UPDATE");
        $stmt->execute([$user_id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        $before = $row ? (int)$row["balance"] : 0;

        $after = $before + $delta;
        if ($after < 0) {
            $pdo->rollBack();
            send_error(409, "insufficient_coins", "Not enough coins", ["balance" => $before, "required" => -$delta], null, "coin.insufficient");
        }

        if ($client_request_id) {
            $check = $pdo->prepare("
                SELECT id, balance_after
                FROM coin_transactions
                WHERE user_id = ? AND client_request_id = ?
                LIMIT 1
            ");
            $check->execute([$user_id, $client_request_id]);
            $existing = $check->fetch(PDO::FETCH_ASSOC);
            if ($existing) {
                $pdo->commit();
                return [
                    "transaction_id" => (int)$existing["id"],
                    "balance" => (int)$existing["balance_after"],
                    "idempotent" => true
                ];
            }
        }

        $up = $pdo->prepare("UPDATE user_wallets SET balance = ? WHERE user_id = ?");
        $up->execute([$after, $user_id]);

        $meta_json = null;
        if ($meta !== null) {
            $meta_json = is_string($meta) ? json_encode(["value" => $meta], JSON_UNESCAPED_UNICODE) : json_encode($meta, JSON_UNESCAPED_UNICODE);
        }

        $ins = $pdo->prepare("
            INSERT INTO coin_transactions
                (user_id, delta, type, reason, meta, balance_after, client_request_id)
            VALUES
                (?, ?, ?, ?, ?, ?, ?)
        ");
        $ins->execute([
            $user_id,
            $delta,
            $type,
            $reason,
            $meta_json,
            $after,
            $client_request_id
        ]);

        $tx_id = (int)$pdo->lastInsertId();
        $pdo->commit();

        return [
            "transaction_id" => $tx_id,
            "balance" => $after,
            "idempotent" => false
        ];
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();

        if (($e->getCode() === "23000") && $client_request_id) {
            $stmt = $pdo->prepare("
                SELECT id, balance_after
                FROM coin_transactions
                WHERE user_id = ? AND client_request_id = ?
                LIMIT 1
            ");
            $stmt->execute([$user_id, $client_request_id]);
            $existing = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($existing) {
                return [
                    "transaction_id" => (int)$existing["id"],
                    "balance" => (int)$existing["balance_after"],
                    "idempotent" => true
                ];
            }
        }

        send_error(500, "db_error", "Database error", $e->getMessage());
    } catch (Exception $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        send_error(500, "server_error", "Server error", $e->getMessage());
    }
}

/* ============================
   ACTION
============================ */
$action = $_POST["action"] ?? "";

switch ($action) {

    case "ping": {
            // 疎通確認（ログイン必須）
            $user = require_login($pdo);
            send_response(200, [
                "message" => "ok",
                "user_id" => (int)$user["id"]
            ]);
            break;
        }

    case "admin_ping": {
            // 管理者向け疎通確認
            $admin = require_admin($pdo);
            send_response(200, [
                "message" => "ok",
                "admin_id" => (int)$admin["id"]
            ]);
            break;
        }

        /* ============================
    COIN APIs
    ============================ */

    case "coin_register": {
            // 既存ウォレットが無ければ作成
            $user = require_login($pdo);

            [$balance, $berr] = require_int_field("balance", 0, 1000000000);
            if ($berr) send_error(422, "validation_error", "Invalid fields", null, ["balance" => $berr], "validation.balance");

            $result = register_wallet_if_missing($pdo, (int)$user["id"], $balance);

            send_response(200, [
                "user_id" => (int)$user["id"],
                "balance" => (int)$result["balance"],
                "registered" => (bool)$result["registered"],
                "transaction_id" => $result["transaction_id"]
            ]);
            break;
        }

    case "coin_get": {
            // 現在のコイン残高を返す
            $user = require_login($pdo);
            $balance = get_balance($pdo, (int)$user["id"]);
            send_response(200, [
                "user_id" => (int)$user["id"],
                "balance" => (int)$balance
            ]);
            break;
        }

    case "coin_use": {
            // コイン消費（マイナス増減）
            $user = require_login($pdo);

            [$amount, $err] = require_int_field("amount", 1, 1000000000);
            if ($err) send_error(422, "validation_error", "Invalid fields", null, ["amount" => $err], "validation.amount");

            [$reason, $rerr] = require_string_field("reason", 255, false);
            if ($rerr) send_error(422, "validation_error", "Invalid fields", null, ["reason" => $rerr]);

            [$client_request_id, $cerr] = require_string_field("client_request_id", 64, false);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $cerr]);


            $result = apply_coin_delta(
                $pdo,
                (int)$user["id"],
                -$amount,
                "spend",
                $reason ?? "spend",
                ["amount" => $amount],
                $client_request_id
            );

            send_response(200, [
                "message" => "ok",
                "user_id" => (int)$user["id"],
                "used" => (int)$amount,
                "balance" => (int)$result["balance"],
                "transaction_id" => (int)$result["transaction_id"],
                "idempotent" => (bool)$result["idempotent"]
            ]);
            break;
        }

    case "coin_earn": {
            // コイン獲得（プラス増減）
            $user = require_login($pdo);

            [$amount, $err] = require_int_field("amount", 1, 1000000000);
            if ($err) send_error(422, "validation_error", "Invalid fields", null, ["amount" => $err], "validation.amount");

            [$reason, $rerr] = require_string_field("reason", 255, false);
            if ($rerr) send_error(422, "validation_error", "Invalid fields", null, ["reason" => $rerr]);

            [$client_request_id, $cerr] = require_string_field("client_request_id", 64, false);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $cerr]);

            $result = apply_coin_delta(
                $pdo,
                (int)$user["id"],
                +$amount,
                "earn",
                $reason ?? "earn",
                ["amount" => $amount],
                $client_request_id
            );

            send_response(200, [
                "message" => "ok",
                "user_id" => (int)$user["id"],
                "added" => (int)$amount,
                "balance" => (int)$result["balance"],
                "transaction_id" => (int)$result["transaction_id"],
                "idempotent" => (bool)$result["idempotent"]
            ]);
            break;
        }

    case "coin_add": {
            // 管理者によるコイン付与
            $admin = require_admin($pdo);

            [$target_user_id, $uerr] = require_int_field("user_id", 1, null);
            [$amount, $aerr] = require_int_field("amount", 1, 1000000000);

            $fieldErr = [];
            if ($uerr) $fieldErr["user_id"] = $uerr;
            if ($aerr) $fieldErr["amount"] = $aerr;
            if ($fieldErr) send_error(422, "validation_error", "Invalid fields", null, $fieldErr);

            [$reason, $rerr] = require_string_field("reason", 255, false);
            if ($rerr) send_error(422, "validation_error", "Invalid fields", null, ["reason" => $rerr]);

            [$client_request_id, $cerr] = require_string_field("client_request_id", 64, false);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $cerr]);

            $result = apply_coin_delta(
                $pdo,
                (int)$target_user_id,
                +$amount,
                "admin_add",
                $reason ?? "admin_add",
                ["amount" => $amount, "admin_id" => (int)$admin["id"]],
                $client_request_id
            );

            send_response(200, [
                "message" => "ok",
                "admin_id" => (int)$admin["id"],
                "user_id" => (int)$target_user_id,
                "added" => (int)$amount,
                "balance" => (int)$result["balance"],
                "transaction_id" => (int)$result["transaction_id"],
                "idempotent" => (bool)$result["idempotent"]
            ]);
            break;
        }

    case "coin_history": {
            // コイン取引履歴（ページング）
            $user = require_login($pdo);

            [$limit, $lerr] = require_int_field("limit", 1, 200);
            if ($lerr) {
                $limit = 50;
            }

            $before_id_raw = $_POST["before_id"] ?? null;
            $before_id = null;
            if ($before_id_raw !== null && $before_id_raw !== "") {
                if (!is_numeric($before_id_raw)) {
                    send_error(422, "validation_error", "Invalid fields", null, ["before_id" => "before_id must be integer"]);
                }
                $before_id = (int)$before_id_raw;
            }

            if ($before_id) {
                $stmt = $pdo->prepare("
                SELECT id, delta, type, reason, meta, balance_after, created_at
                FROM coin_transactions
                WHERE user_id = ? AND id < ?
                ORDER BY id DESC
                LIMIT " . (int)$limit . "
            ");
                $stmt->execute([(int)$user["id"], $before_id]);
            } else {
                $stmt = $pdo->prepare("
                SELECT id, delta, type, reason, meta, balance_after, created_at
                FROM coin_transactions
                WHERE user_id = ?
                ORDER BY id DESC
                LIMIT " . (int)$limit . "
            ");
                $stmt->execute([(int)$user["id"]]);
            }

            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            $items = [];
            $next_before_id = null;

            foreach ($rows as $r) {
                $items[] = [
                    "id" => (int)$r["id"],
                    "delta" => (int)$r["delta"],
                    "type" => $r["type"],
                    "reason" => $r["reason"],
                    "meta" => $r["meta"] ? json_decode($r["meta"], true) : null,
                    "balance_after" => (int)$r["balance_after"],
                    "created_at" => $r["created_at"],
                ];
                $next_before_id = (int)$r["id"];
            }

            $balance = get_balance($pdo, (int)$user["id"]);

            send_response(200, [
                "user_id" => (int)$user["id"],
                "balance" => (int)$balance,
                "items" => $items,
                "next_before_id" => $next_before_id
            ]);
            break;
        }

        /* ============================
       STAMP APIs
    ============================ */

    case "stamp_get": {
            // スタンプ残高と累計獲得
            $user = require_login($pdo);
            $result = get_stamp_balance($pdo, (int)$user["id"]);
            send_response(200, [
                "user_id" => (int)$user["id"],
                "balance" => (int)$result["balance"],
                "total_earned" => (int)$result["total_earned"]
            ]);
            break;
        }

    case "stamp_sync": {
            // 端末側の当日獲得分を同期して差分加算
            $user = require_login($pdo);

            [$date_key, $derr] = require_string_field("date_key", 10, true);
            if ($derr) send_error(422, "validation_error", "Invalid fields", null, ["date_key" => $derr]);

            [$current_earned, $cerr] = require_int_field("current_earned", 0, 100000);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["current_earned" => $cerr]);

            [$client_request_id, $crerr] = require_string_field("client_request_id", 64, false);
            if ($crerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $crerr]);

            $pdo->beginTransaction();
            try {
                $stmt = $pdo->prepare("SELECT earned FROM stamp_daily_earned WHERE user_id = ? AND date_key = ? FOR UPDATE");
                $stmt->execute([(int)$user["id"], $date_key]);
                $row = $stmt->fetch(PDO::FETCH_ASSOC);
                $prev_earned = $row ? (int)$row["earned"] : 0;

                if ($current_earned > $prev_earned) {
                    $added = $current_earned - $prev_earned;

                    if ($row) {
                        $up = $pdo->prepare("UPDATE stamp_daily_earned SET earned = ? WHERE user_id = ? AND date_key = ?");
                        $up->execute([$current_earned, (int)$user["id"], $date_key]);
                    } else {
                        $ins = $pdo->prepare("INSERT INTO stamp_daily_earned (user_id, date_key, earned) VALUES (?, ?, ?)");
                        $ins->execute([(int)$user["id"], $date_key, $current_earned]);
                    }

                    ensure_stamp_wallet_exists($pdo, (int)$user["id"]);
                    $stmt2 = $pdo->prepare("SELECT balance, total_earned FROM user_stamps WHERE user_id = ? FOR UPDATE");
                    $stmt2->execute([(int)$user["id"]]);
                    $wallet = $stmt2->fetch(PDO::FETCH_ASSOC);
                    $balance = $wallet ? (int)$wallet["balance"] : 0;
                    $total = $wallet ? (int)$wallet["total_earned"] : 0;

                    $new_balance = $balance + $added;
                    $new_total = $total + $added;

                    $up2 = $pdo->prepare("UPDATE user_stamps SET balance = ?, total_earned = ? WHERE user_id = ?");
                    $up2->execute([$new_balance, $new_total, (int)$user["id"]]);

                    $meta_json = json_encode(["date_key" => $date_key, "earned_today" => $current_earned], JSON_UNESCAPED_UNICODE);
                    $ins2 = $pdo->prepare("
                        INSERT INTO stamp_transactions
                            (user_id, delta, type, reason, meta, balance_after, client_request_id)
                        VALUES
                            (?, ?, ?, ?, ?, ?, ?)
                    ");
                    $ins2->execute([
                        (int)$user["id"],
                        $added,
                        "sync",
                        "daily_sync",
                        $meta_json,
                        $new_balance,
                        $client_request_id
                    ]);

                    $pdo->commit();

                    send_response(200, [
                        "user_id" => (int)$user["id"],
                        "balance" => (int)$new_balance,
                        "earned_today" => (int)$current_earned,
                        "added" => (int)$added
                    ]);
                } else {
                    $pdo->commit();
                    $result = get_stamp_balance($pdo, (int)$user["id"]);
                    send_response(200, [
                        "user_id" => (int)$user["id"],
                        "balance" => (int)$result["balance"],
                        "earned_today" => (int)$current_earned,
                        "added" => 0
                    ]);
                }
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }
            break;
        }

    case "stamp_spend": {
            // スタンプ消費
            $user = require_login($pdo);

            [$amount, $err] = require_int_field("amount", 1, 1000000000);
            if ($err) send_error(422, "validation_error", "Invalid fields", null, ["amount" => $err], "validation.amount");

            [$reason, $rerr] = require_string_field("reason", 255, false);
            if ($rerr) send_error(422, "validation_error", "Invalid fields", null, ["reason" => $rerr]);

            [$client_request_id, $cerr] = require_string_field("client_request_id", 64, false);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $cerr]);

            $result = apply_stamp_delta(
                $pdo,
                (int)$user["id"],
                -$amount,
                "spend",
                $reason ?? "spend",
                ["amount" => $amount],
                $client_request_id
            );

            send_response(200, [
                "message" => "ok",
                "user_id" => (int)$user["id"],
                "used" => (int)$amount,
                "balance" => (int)$result["balance"],
                "transaction_id" => (int)$result["transaction_id"],
                "idempotent" => (bool)$result["idempotent"]
            ]);
            break;
        }

    case "stamp_add": {
            // スタンプ追加
            $user = require_login($pdo);

            [$amount, $err] = require_int_field("amount", 1, 1000000000);
            if ($err) send_error(422, "validation_error", "Invalid fields", null, ["amount" => $err], "validation.amount");

            [$reason, $rerr] = require_string_field("reason", 255, false);
            if ($rerr) send_error(422, "validation_error", "Invalid fields", null, ["reason" => $rerr]);

            [$client_request_id, $cerr] = require_string_field("client_request_id", 64, false);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $cerr]);

            $result = apply_stamp_delta(
                $pdo,
                (int)$user["id"],
                +$amount,
                "add",
                $reason ?? "add",
                ["amount" => $amount],
                $client_request_id
            );

            send_response(200, [
                "message" => "ok",
                "user_id" => (int)$user["id"],
                "added" => (int)$amount,
                "balance" => (int)$result["balance"],
                "transaction_id" => (int)$result["transaction_id"],
                "idempotent" => (bool)$result["idempotent"]
            ]);
            break;
        }

    case "stamp_history": {
            // スタンプ取引履歴（ページング）
            $user = require_login($pdo);

            [$limit, $lerr] = require_int_field("limit", 1, 200);
            if ($lerr) {
                $limit = 50;
            }

            $before_id_raw = $_POST["before_id"] ?? null;
            $before_id = null;
            if ($before_id_raw !== null && $before_id_raw !== "") {
                if (!is_numeric($before_id_raw)) {
                    send_error(422, "validation_error", "Invalid fields", null, ["before_id" => "before_id must be integer"]);
                }
                $before_id = (int)$before_id_raw;
            }

            try {
                if ($before_id) {
                    $stmt = $pdo->prepare("
                    SELECT id, delta, type, reason, balance_after, created_at
                    FROM stamp_transactions
                    WHERE user_id = ? AND id < ?
                    ORDER BY id DESC
                    LIMIT " . (int)$limit . "
                ");
                    $stmt->execute([(int)$user["id"], $before_id]);
                } else {
                    $stmt = $pdo->prepare("
                    SELECT id, delta, type, reason, balance_after, created_at
                    FROM stamp_transactions
                    WHERE user_id = ?
                    ORDER BY id DESC
                    LIMIT " . (int)$limit . "
                ");
                    $stmt->execute([(int)$user["id"]]);
                }

                $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
                $items = [];
                $next_before_id = null;

                foreach ($rows as $r) {
                    $items[] = [
                        "id" => (int)$r["id"],
                        "delta" => (int)$r["delta"],
                        "type" => $r["type"],
                        "reason" => $r["reason"],
                        "balance_after" => (int)$r["balance_after"],
                        "created_at" => $r["created_at"],
                    ];
                    $next_before_id = (int)$r["id"];
                }

                $result = get_stamp_balance($pdo, (int)$user["id"]);

                send_response(200, [
                    "user_id" => (int)$user["id"],
                    "balance" => (int)$result["balance"],
                    "items" => $items,
                    "next_before_id" => $next_before_id
                ]);
            } catch (PDOException $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                send_error(500, "server_error", "Server error", $e->getMessage());
            }
            break;
        }

        /* ============================
       CHALLENGE APIs
    ============================ */

    case "challenge_list": {
            // チャレンジ定義（固定配列）
            $user = require_login($pdo);

            $monthly = [
                ["key" => "monthly_start", "mode" => "monthly", "required_steps" => 0, "title" => "スタートボーナス", "subtitle" => "コイン+50", "reward_type" => "coin", "reward_value" => "50"],
                ["key" => "monthly_bronze", "mode" => "monthly", "required_steps" => 5000, "title" => "ブロンズ報酬", "subtitle" => "コイン+80", "reward_type" => "coin", "reward_value" => "80"],
                ["key" => "monthly_silver", "mode" => "monthly", "required_steps" => 15000, "title" => "シルバー報酬", "subtitle" => "コイン+120", "reward_type" => "coin", "reward_value" => "120"],
                ["key" => "monthly_gold", "mode" => "monthly", "required_steps" => 30000, "title" => "ゴールド報酬", "subtitle" => "コイン+200", "reward_type" => "coin", "reward_value" => "200"]
            ];

            $cumulative = [
                ["key" => "unlock_battle", "mode" => "cumulative", "required_steps" => 50000, "title" => "すれ違いバトル解放", "subtitle" => "新しいゲームが開放", "reward_type" => "unlock", "reward_value" => "battle"],
                ["key" => "unlock_poker", "mode" => "cumulative", "required_steps" => 100000, "title" => "ポーカー解放", "subtitle" => "新しいゲームが開放", "reward_type" => "unlock", "reward_value" => "poker"],
                ["key" => "unlock_slot", "mode" => "cumulative", "required_steps" => 150000, "title" => "スロット解放", "subtitle" => "新しいゲームが開放", "reward_type" => "unlock", "reward_value" => "slot"]
            ];

            send_response(200, [
                "monthly" => $monthly,
                "cumulative" => $cumulative
            ]);
            break;
        }

    case "challenge_status": {
            // 期間別の達成/解放状況
            $user = require_login($pdo);

            $year_raw = $_POST["year"] ?? null;
            $month_raw = $_POST["month"] ?? null;

            if ($year_raw === null || $month_raw === null) {
                $year = (int)date("Y");
                $month = (int)date("n");
            } else {
                [$year, $yerr] = require_int_field("year", 2020, 2100);
                [$month, $merr] = require_int_field("month", 1, 12);
                if ($yerr) send_error(422, "validation_error", "Invalid fields", null, ["year" => $yerr]);
                if ($merr) send_error(422, "validation_error", "Invalid fields", null, ["month" => $merr]);
            }

            $period_key = sprintf("%04d-%02d", $year, $month);

            $stmt = $pdo->prepare("
                SELECT reward_key
                FROM challenge_claims
                WHERE user_id = ? AND period_key = ?
            ");
            $stmt->execute([(int)$user["id"], $period_key]);
            $monthly_rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            $claimed_monthly = array_map(fn($r) => $r["reward_key"], $monthly_rows);

            $stmt2 = $pdo->prepare("
                SELECT reward_key
                FROM challenge_claims
                WHERE user_id = ? AND period_key = ''
            ");
            $stmt2->execute([(int)$user["id"]]);
            $cumulative_rows = $stmt2->fetchAll(PDO::FETCH_ASSOC);
            $claimed_cumulative = array_map(fn($r) => $r["reward_key"], $cumulative_rows);

            $unlocks = [
                "battle" => in_array("unlock_battle", $claimed_cumulative),
                "poker" => in_array("unlock_poker", $claimed_cumulative),
                "slot" => in_array("unlock_slot", $claimed_cumulative)
            ];

            send_response(200, [
                "period_key" => $period_key,
                "claimed_monthly" => $claimed_monthly,
                "claimed_cumulative" => $claimed_cumulative,
                "unlocks" => $unlocks
            ]);
            break;
        }

    case "challenge_claim": {
            // 報酬の請求（冪等）
            $user = require_login($pdo);

            [$key, $kerr] = require_string_field("key", 64, true);
            if ($kerr) send_error(422, "validation_error", "Invalid fields", null, ["key" => $kerr]);

            $year_raw = $_POST["year"] ?? null;
            $month_raw = $_POST["month"] ?? null;

            $monthly_challenges = [
                "monthly_start" => ["reward_type" => "coin", "reward_value" => 50],
                "monthly_bronze" => ["reward_type" => "coin", "reward_value" => 80],
                "monthly_silver" => ["reward_type" => "coin", "reward_value" => 120],
                "monthly_gold" => ["reward_type" => "coin", "reward_value" => 200]
            ];

            $cumulative_challenges = [
                "unlock_battle" => ["reward_type" => "unlock", "reward_value" => "battle"],
                "unlock_poker" => ["reward_type" => "unlock", "reward_value" => "poker"],
                "unlock_slot" => ["reward_type" => "unlock", "reward_value" => "slot"]
            ];

            $is_monthly = isset($monthly_challenges[$key]);
            $is_cumulative = isset($cumulative_challenges[$key]);

            if (!$is_monthly && !$is_cumulative) {
                send_error(400, "bad_request", "Unknown challenge key");
            }

            if ($is_monthly) {
                if ($year_raw === null || $month_raw === null) {
                    $year = (int)date("Y");
                    $month = (int)date("n");
                } else {
                    [$year, $yerr] = require_int_field("year", 2020, 2100);
                    [$month, $merr] = require_int_field("month", 1, 12);
                    if ($yerr) send_error(422, "validation_error", "Invalid fields", null, ["year" => $yerr]);
                    if ($merr) send_error(422, "validation_error", "Invalid fields", null, ["month" => $merr]);
                }
                $period_key = sprintf("%04d-%02d", $year, $month);
                $reward = $monthly_challenges[$key];
            } else {
                $period_key = "";
                $reward = $cumulative_challenges[$key];
            }

            [$client_request_id, $cerr] = require_string_field("client_request_id", 64, false);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $cerr]);

            $pdo->beginTransaction();
            try {
                $stmt = $pdo->prepare("
                    SELECT id
                    FROM challenge_claims
                    WHERE user_id = ? AND reward_key = ? AND period_key = ?
                    LIMIT 1
                ");
                $stmt->execute([(int)$user["id"], $key, $period_key]);
                $existing = $stmt->fetch(PDO::FETCH_ASSOC);

                if ($existing) {
                    $pdo->commit();
                    $balance = get_balance($pdo, (int)$user["id"]);
                    send_response(200, [
                        "message" => "ok",
                        "key" => $key,
                        "period_key" => $period_key,
                        "reward_type" => $reward["reward_type"],
                        "balance" => (int)$balance,
                        "idempotent" => true,
                        "unlocks" => null
                    ]);
                }

                $ins = $pdo->prepare("
                    INSERT INTO challenge_claims
                        (user_id, reward_key, period_key, client_request_id)
                    VALUES
                        (?, ?, ?, ?)
                ");
                $ins->execute([(int)$user["id"], $key, $period_key, $client_request_id]);

                $new_balance = null;
                if ($reward["reward_type"] === "coin") {
                    ensure_wallet_exists($pdo, (int)$user["id"]);

                    $stmt_coin = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? FOR UPDATE");
                    $stmt_coin->execute([(int)$user["id"]]);
                    $row_coin = $stmt_coin->fetch(PDO::FETCH_ASSOC);
                    $before_coin = $row_coin ? (int)$row_coin["balance"] : 0;

                    $after_coin = $before_coin + (int)$reward["reward_value"];

                    $up_coin = $pdo->prepare("UPDATE user_wallets SET balance = ? WHERE user_id = ?");
                    $up_coin->execute([$after_coin, (int)$user["id"]]);

                    $meta_json = json_encode(["challenge_key" => $key, "period_key" => $period_key], JSON_UNESCAPED_UNICODE);
                    $ins_coin = $pdo->prepare("
                        INSERT INTO coin_transactions
                            (user_id, delta, type, reason, meta, balance_after, client_request_id)
                        VALUES
                            (?, ?, ?, ?, ?, ?, ?)
                    ");
                    $ins_coin->execute([
                        (int)$user["id"],
                        (int)$reward["reward_value"],
                        "challenge",
                        $key,
                        $meta_json,
                        $after_coin,
                        null
                    ]);

                    $new_balance = $after_coin;
                }

                $unlocks = null;
                if ($reward["reward_type"] === "unlock") {
                    $stmt2 = $pdo->prepare("
                        SELECT reward_key
                        FROM challenge_claims
                        WHERE user_id = ? AND period_key = ''
                    ");
                    $stmt2->execute([(int)$user["id"]]);
                    $cumulative_rows = $stmt2->fetchAll(PDO::FETCH_ASSOC);
                    $claimed_cumulative = array_map(fn($r) => $r["reward_key"], $cumulative_rows);

                    $unlocks = [
                        "battle" => in_array("unlock_battle", $claimed_cumulative),
                        "poker" => in_array("unlock_poker", $claimed_cumulative),
                        "slot" => in_array("unlock_slot", $claimed_cumulative)
                    ];
                    $new_balance = get_balance($pdo, (int)$user["id"]);
                }

                $pdo->commit();

                send_response(200, [
                    "message" => "ok",
                    "key" => $key,
                    "period_key" => $period_key,
                    "reward_type" => $reward["reward_type"],
                    "balance" => (int)$new_balance,
                    "idempotent" => false,
                    "unlocks" => $unlocks
                ]);
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();

                if ($e->getCode() === "23000") {
                    $balance = get_balance($pdo, (int)$user["id"]);
                    send_response(200, [
                        "message" => "ok",
                        "key" => $key,
                        "period_key" => $period_key,
                        "reward_type" => $reward["reward_type"],
                        "balance" => (int)$balance,
                        "idempotent" => true,
                        "unlocks" => null
                    ]);
                }

                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }
            break;
        }

    /* ============================
       COIN DAILY USAGE APIs
    ============================ */

    case "coin_daily_usage": {
            // 本日のコイン使用状況を取得
            $user = require_login($pdo);
            $date_key = date("Y-m-d");

            $stmt = $pdo->prepare("SELECT used, daily_limit FROM coin_daily_usage WHERE user_id = ? AND date_key = ? LIMIT 1");
            $stmt->execute([(int)$user["id"], $date_key]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);

            $used = $row ? (int)$row["used"] : 0;
            $daily_limit = $row ? (int)$row["daily_limit"] : 500;

            send_response(200, [
                "user_id" => (int)$user["id"],
                "date_key" => $date_key,
                "used" => $used,
                "daily_limit" => $daily_limit,
                "remaining" => max(0, $daily_limit - $used)
            ]);
            break;
        }

    case "coin_use_daily": {
            // 日次使用量チェック付きコイン消費
            $user = require_login($pdo);

            [$amount, $err] = require_int_field("amount", 1, 1000000000);
            if ($err) send_error(422, "validation_error", "Invalid fields", null, ["amount" => $err], "validation.amount");

            [$reason, $rerr] = require_string_field("reason", 255, false);
            if ($rerr) send_error(422, "validation_error", "Invalid fields", null, ["reason" => $rerr]);

            [$client_request_id, $cerr] = require_string_field("client_request_id", 64, false);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $cerr]);

            $date_key = date("Y-m-d");
            $uid = (int)$user["id"];

            $pdo->beginTransaction();
            try {
                // ウォレット存在確認
                ensure_wallet_exists($pdo, $uid);

                // 日次使用量を確認
                $stmt_daily = $pdo->prepare("SELECT used, daily_limit FROM coin_daily_usage WHERE user_id = ? AND date_key = ? FOR UPDATE");
                $stmt_daily->execute([$uid, $date_key]);
                $daily_row = $stmt_daily->fetch(PDO::FETCH_ASSOC);

                $used = $daily_row ? (int)$daily_row["used"] : 0;
                $daily_limit = $daily_row ? (int)$daily_row["daily_limit"] : 500;
                $remaining = $daily_limit - $used;

                if ($amount > $remaining) {
                    $pdo->rollBack();
                    send_error(429, "daily_limit_exceeded", "Daily coin usage limit exceeded", [
                        "used" => $used,
                        "daily_limit" => $daily_limit,
                        "remaining" => max(0, $remaining),
                        "requested" => $amount
                    ], null, "coin.daily_limit");
                }

                // 冪等チェック
                if ($client_request_id) {
                    $check = $pdo->prepare("SELECT id, balance_after FROM coin_transactions WHERE user_id = ? AND client_request_id = ? LIMIT 1");
                    $check->execute([$uid, $client_request_id]);
                    $existing = $check->fetch(PDO::FETCH_ASSOC);
                    if ($existing) {
                        $pdo->commit();
                        send_response(200, [
                            "message" => "ok",
                            "user_id" => $uid,
                            "used" => $amount,
                            "balance" => (int)$existing["balance_after"],
                            "daily_used" => $used,
                            "daily_limit" => $daily_limit,
                            "daily_remaining" => max(0, $daily_limit - $used),
                            "transaction_id" => (int)$existing["id"],
                            "idempotent" => true
                        ]);
                    }
                }

                // コイン残高チェック＆消費
                $stmt_bal = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? FOR UPDATE");
                $stmt_bal->execute([$uid]);
                $bal_row = $stmt_bal->fetch(PDO::FETCH_ASSOC);
                $coin_balance = $bal_row ? (int)$bal_row["balance"] : 0;

                if ($coin_balance < $amount) {
                    $pdo->rollBack();
                    send_error(409, "insufficient_coins", "Not enough coins", [
                        "balance" => $coin_balance,
                        "required" => $amount
                    ], null, "coin.insufficient");
                }

                $new_balance = $coin_balance - $amount;
                $up_bal = $pdo->prepare("UPDATE user_wallets SET balance = ? WHERE user_id = ?");
                $up_bal->execute([$new_balance, $uid]);

                // コイン取引記録
                $meta_json = json_encode(["amount" => $amount, "daily" => true], JSON_UNESCAPED_UNICODE);
                $ins_tx = $pdo->prepare("
                    INSERT INTO coin_transactions (user_id, delta, type, reason, meta, balance_after, client_request_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ");
                $ins_tx->execute([$uid, -$amount, "spend", $reason ?? "spend", $meta_json, $new_balance, $client_request_id]);
                $tx_id = (int)$pdo->lastInsertId();

                // 日次使用量を更新
                if ($daily_row) {
                    $up = $pdo->prepare("UPDATE coin_daily_usage SET used = used + ? WHERE user_id = ? AND date_key = ?");
                    $up->execute([$amount, $uid, $date_key]);
                } else {
                    $ins = $pdo->prepare("INSERT INTO coin_daily_usage (user_id, date_key, used, daily_limit) VALUES (?, ?, ?, 500)");
                    $ins->execute([$uid, $date_key, $amount]);
                }

                $pdo->commit();

                send_response(200, [
                    "message" => "ok",
                    "user_id" => $uid,
                    "used" => $amount,
                    "balance" => $new_balance,
                    "daily_used" => $used + $amount,
                    "daily_limit" => $daily_limit,
                    "daily_remaining" => max(0, $daily_limit - $used - $amount),
                    "transaction_id" => $tx_id,
                    "idempotent" => false
                ]);
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }
            break;
        }

    /* ============================
       GOLD STAMP APIs
    ============================ */

    case "gold_stamp_get": {
            // ゴールドスタンプ残高取得
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $stmt = $pdo->prepare("SELECT balance, total_earned FROM gold_stamps WHERE user_id = ? LIMIT 1");
            $stmt->execute([$uid]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);

            send_response(200, [
                "user_id" => $uid,
                "balance" => $row ? (int)$row["balance"] : 0,
                "total_earned" => $row ? (int)$row["total_earned"] : 0
            ]);
            break;
        }

    case "gold_stamp_exchange": {
            // コイン5000 → ゴールドスタンプ1枚に交換
            $user = require_login($pdo);
            $uid = (int)$user["id"];
            $cost = 5000;

            [$client_request_id, $cerr] = require_string_field("client_request_id", 64, false);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $cerr]);

            $pdo->beginTransaction();
            try {
                // コイン消費
                ensure_wallet_exists($pdo, $uid);
                $stmt = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? FOR UPDATE");
                $stmt->execute([$uid]);
                $row = $stmt->fetch(PDO::FETCH_ASSOC);
                $coin_balance = $row ? (int)$row["balance"] : 0;

                if ($coin_balance < $cost) {
                    $pdo->rollBack();
                    send_error(409, "insufficient_coins", "Not enough coins for gold stamp exchange", [
                        "balance" => $coin_balance,
                        "required" => $cost
                    ], null, "coin.insufficient");
                }

                // ゴールドスタンプ交換は日次上限の対象外（ゲーム用の制限のため）

                // コイン残高を減算
                $new_coin = $coin_balance - $cost;
                $up_coin = $pdo->prepare("UPDATE user_wallets SET balance = ? WHERE user_id = ?");
                $up_coin->execute([$new_coin, $uid]);

                // コイン取引記録
                $meta_json = json_encode(["type" => "gold_stamp_exchange", "cost" => $cost], JSON_UNESCAPED_UNICODE);
                $ins_tx = $pdo->prepare("
                    INSERT INTO coin_transactions (user_id, delta, type, reason, meta, balance_after, client_request_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ");
                $ins_tx->execute([$uid, -$cost, "spend", "gold_stamp_exchange", $meta_json, $new_coin, $client_request_id]);

                // ゴールドスタンプ付与
                $stmt_gs = $pdo->prepare("SELECT balance, total_earned FROM gold_stamps WHERE user_id = ? FOR UPDATE");
                $stmt_gs->execute([$uid]);
                $gs_row = $stmt_gs->fetch(PDO::FETCH_ASSOC);

                if ($gs_row) {
                    $gs_balance = (int)$gs_row["balance"] + 1;
                    $gs_total = (int)$gs_row["total_earned"] + 1;
                    $up_gs = $pdo->prepare("UPDATE gold_stamps SET balance = ?, total_earned = ? WHERE user_id = ?");
                    $up_gs->execute([$gs_balance, $gs_total, $uid]);
                } else {
                    $gs_balance = 1;
                    $gs_total = 1;
                    $ins_gs = $pdo->prepare("INSERT INTO gold_stamps (user_id, balance, total_earned) VALUES (?, 1, 1)");
                    $ins_gs->execute([$uid]);
                }

                // ゴールドスタンプ取引記録
                $ins_gs_tx = $pdo->prepare("
                    INSERT INTO gold_stamp_transactions (user_id, delta, type, reason, balance_after, client_request_id)
                    VALUES (?, 1, 'exchange', 'coin_to_gold_stamp', ?, ?)
                ");
                $ins_gs_tx->execute([$uid, $gs_balance, $client_request_id]);

                $pdo->commit();

                send_response(200, [
                    "message" => "ok",
                    "user_id" => $uid,
                    "coin_balance" => $new_coin,
                    "coin_used" => $cost,
                    "gold_stamp_balance" => $gs_balance,
                    "gold_stamp_total_earned" => $gs_total
                ]);
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }
            break;
        }

    case "gold_stamp_use": {
            // ゴールドスタンプ消費（コイン上限拡張 or 景品交換）
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            [$amount, $err] = require_int_field("amount", 1, 10000);
            if ($err) send_error(422, "validation_error", "Invalid fields", null, ["amount" => $err]);

            [$use_type, $terr] = require_string_field("use_type", 32, true);
            if ($terr) send_error(422, "validation_error", "Invalid fields", null, ["use_type" => $terr]);

            [$client_request_id, $cerr] = require_string_field("client_request_id", 64, false);
            if ($cerr) send_error(422, "validation_error", "Invalid fields", null, ["client_request_id" => $cerr]);

            if (!in_array($use_type, ["coin_limit_expand", "prize_exchange"])) {
                send_error(400, "bad_request", "use_type must be 'coin_limit_expand' or 'prize_exchange'");
            }

            $pdo->beginTransaction();
            try {
                $stmt = $pdo->prepare("SELECT balance FROM gold_stamps WHERE user_id = ? FOR UPDATE");
                $stmt->execute([$uid]);
                $row = $stmt->fetch(PDO::FETCH_ASSOC);
                $gs_balance = $row ? (int)$row["balance"] : 0;

                if ($gs_balance < $amount) {
                    $pdo->rollBack();
                    send_error(409, "insufficient_gold_stamps", "Not enough gold stamps", [
                        "balance" => $gs_balance,
                        "required" => $amount
                    ], null, "gold_stamp.insufficient");
                }

                $new_gs = $gs_balance - $amount;
                $up = $pdo->prepare("UPDATE gold_stamps SET balance = ? WHERE user_id = ?");
                $up->execute([$new_gs, $uid]);

                // 取引記録
                $ins_tx = $pdo->prepare("
                    INSERT INTO gold_stamp_transactions (user_id, delta, type, reason, balance_after, client_request_id)
                    VALUES (?, ?, 'spend', ?, ?, ?)
                ");
                $ins_tx->execute([$uid, -$amount, $use_type, $new_gs, $client_request_id]);

                $coin_limit_added = 0;
                if ($use_type === "coin_limit_expand") {
                    // 1スタンプ = +10コイン/日の上限拡張
                    $coin_limit_added = $amount * 10;
                    $date_key = date("Y-m-d");
                    $stmt_daily = $pdo->prepare("SELECT daily_limit FROM coin_daily_usage WHERE user_id = ? AND date_key = ? FOR UPDATE");
                    $stmt_daily->execute([$uid, $date_key]);
                    $daily_row = $stmt_daily->fetch(PDO::FETCH_ASSOC);

                    if ($daily_row) {
                        $up_daily = $pdo->prepare("UPDATE coin_daily_usage SET daily_limit = daily_limit + ? WHERE user_id = ? AND date_key = ?");
                        $up_daily->execute([$coin_limit_added, $uid, $date_key]);
                    } else {
                        $ins_daily = $pdo->prepare("INSERT INTO coin_daily_usage (user_id, date_key, used, daily_limit) VALUES (?, ?, 0, ?)");
                        $ins_daily->execute([$uid, $date_key, 500 + $coin_limit_added]);
                    }
                }

                $pdo->commit();

                // 最新のdaily_limitを取得
                $date_key = date("Y-m-d");
                $stmt_dl = $pdo->prepare("SELECT daily_limit, used FROM coin_daily_usage WHERE user_id = ? AND date_key = ? LIMIT 1");
                $stmt_dl->execute([$uid, $date_key]);
                $dl_row = $stmt_dl->fetch(PDO::FETCH_ASSOC);

                send_response(200, [
                    "message" => "ok",
                    "user_id" => $uid,
                    "use_type" => $use_type,
                    "gold_stamps_used" => $amount,
                    "gold_stamp_balance" => $new_gs,
                    "coin_limit_added" => $coin_limit_added,
                    "daily_limit" => $dl_row ? (int)$dl_row["daily_limit"] : 500,
                    "daily_used" => $dl_row ? (int)$dl_row["used"] : 0
                ]);
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }
            break;
        }

    default:
        send_error(400, "bad_request", "Unknown action", null, null, "error.unknown_action");
}