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
   AUTH
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
   COIN HELPERS
============================ */
function ensure_wallet_exists($pdo, $user_id)
{
    $stmt = $pdo->prepare("INSERT IGNORE INTO user_wallets (user_id, balance) VALUES (?, 0)");
    $stmt->execute([$user_id]);
}

/* ============================
   REWARD LOGIC
============================ */
function roll_treasure_reward()
{
    // 確率テーブル: パズルピース40%, 残念賞20%, 経験値30%, 保留10%
    $roll = mt_rand(1, 100);

    if ($roll <= 40) {
        return ["type" => "puzzle_piece", "value" => mt_rand(0, 8)]; // piece_index 0-8
    } elseif ($roll <= 60) {
        $penalty = [10, 20, 30, 50][mt_rand(0, 3)];
        return ["type" => "coin_penalty", "value" => $penalty];
    } elseif ($roll <= 90) {
        $exp = [10, 20, 30, 50][mt_rand(0, 3)];
        return ["type" => "experience", "value" => $exp];
    } else {
        return ["type" => "reserved", "value" => 0];
    }
}

/* ============================
   ACTION
============================ */
$action = $_POST["action"] ?? "";

switch ($action) {

    case "open_box": {
            // 宝箱を開ける
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $puzzle_id = isset($_POST["puzzle_id"]) ? (int)$_POST["puzzle_id"] : 1;

            $reward = roll_treasure_reward();

            $pdo->beginTransaction();
            try {
                // 履歴記録
                $ins = $pdo->prepare("INSERT INTO treasure_box_history (user_id, reward_type, reward_value) VALUES (?, ?, ?)");
                $ins->execute([$uid, $reward["type"], $reward["value"]]);

                $extra = [];

                switch ($reward["type"]) {
                    case "puzzle_piece":
                        // パズルピース付与（重複チェック）
                        $piece_index = $reward["value"];
                        $ins_p = $pdo->prepare("INSERT IGNORE INTO puzzle_pieces (user_id, puzzle_id, piece_index) VALUES (?, ?, ?)");
                        $ins_p->execute([$uid, $puzzle_id, $piece_index]);
                        $is_new = $ins_p->rowCount() > 0;

                        if (!$is_new) {
                            // 既に持っているピース → 経験値に変換
                            $reward["type"] = "experience";
                            $reward["value"] = 15;
                            $extra["note"] = "duplicate_piece_converted";
                        }

                        // 現在のピース状態取得
                        $stmt_p = $pdo->prepare("SELECT piece_index FROM puzzle_pieces WHERE user_id = ? AND puzzle_id = ?");
                        $stmt_p->execute([$uid, $puzzle_id]);
                        $pieces = array_column($stmt_p->fetchAll(PDO::FETCH_ASSOC), "piece_index");
                        $extra["collected_pieces"] = array_map('intval', $pieces);
                        $extra["total_pieces"] = 9;
                        $extra["is_complete"] = count($pieces) >= 9;
                        break;

                    case "coin_penalty":
                        // コインマイナス
                        ensure_wallet_exists($pdo, $uid);
                        $stmt_w = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? FOR UPDATE");
                        $stmt_w->execute([$uid]);
                        $w_row = $stmt_w->fetch(PDO::FETCH_ASSOC);
                        $balance = $w_row ? (int)$w_row["balance"] : 0;

                        $actual_penalty = min($reward["value"], $balance); // 残高以上は引かない
                        if ($actual_penalty > 0) {
                            $new_balance = $balance - $actual_penalty;
                            $up = $pdo->prepare("UPDATE user_wallets SET balance = ? WHERE user_id = ?");
                            $up->execute([$new_balance, $uid]);

                            $meta_json = json_encode(["type" => "treasure_penalty"], JSON_UNESCAPED_UNICODE);
                            $ins_tx = $pdo->prepare("
                                INSERT INTO coin_transactions (user_id, delta, type, reason, meta, balance_after)
                                VALUES (?, ?, 'spend', 'treasure_penalty', ?, ?)
                            ");
                            $ins_tx->execute([$uid, -$actual_penalty, $meta_json, $new_balance]);
                            $extra["coin_balance"] = $new_balance;
                        } else {
                            $extra["coin_balance"] = $balance;
                        }
                        $extra["actual_penalty"] = $actual_penalty;
                        break;

                    case "experience":
                        // 経験値（将来用 - 今はメタデータとして記録のみ）
                        $extra["exp_gained"] = $reward["value"];
                        break;

                    case "reserved":
                        // 保留（将来用）
                        $extra["note"] = "reserved_for_future";
                        break;
                }

                $pdo->commit();

                send_response(200, array_merge([
                    "message" => "ok",
                    "user_id" => $uid,
                    "reward_type" => $reward["type"],
                    "reward_value" => $reward["value"]
                ], $extra));
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "puzzle_status": {
            // パズル収集状況
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $puzzle_id = isset($_POST["puzzle_id"]) ? (int)$_POST["puzzle_id"] : 1;

            try {
                $stmt = $pdo->prepare("SELECT piece_index, obtained_at FROM puzzle_pieces WHERE user_id = ? AND puzzle_id = ? ORDER BY piece_index");
                $stmt->execute([$uid, $puzzle_id]);
                $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

                $pieces = [];
                foreach ($rows as $r) {
                    $pieces[] = [
                        "piece_index" => (int)$r["piece_index"],
                        "obtained_at" => $r["obtained_at"]
                    ];
                }

                send_response(200, [
                    "user_id" => $uid,
                    "puzzle_id" => $puzzle_id,
                    "pieces" => $pieces,
                    "collected" => count($pieces),
                    "total" => 9,
                    "is_complete" => count($pieces) >= 9
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "puzzle_complete": {
            // パズル完成報酬
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $puzzle_id = isset($_POST["puzzle_id"]) ? (int)$_POST["puzzle_id"] : 1;

            try {
                // 完成チェック
                $stmt = $pdo->prepare("SELECT COUNT(DISTINCT piece_index) AS cnt FROM puzzle_pieces WHERE user_id = ? AND puzzle_id = ?");
                $stmt->execute([$uid, $puzzle_id]);
                $cnt = (int)$stmt->fetchColumn();

                if ($cnt < 9) {
                    send_error(400, "incomplete", "Puzzle is not complete", ["collected" => $cnt, "required" => 9]);
                }

                // 完成報酬: コイン500
                $reward_coins = 500;

                $pdo->beginTransaction();
                ensure_wallet_exists($pdo, $uid);
                $stmt_w = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? FOR UPDATE");
                $stmt_w->execute([$uid]);
                $w_row = $stmt_w->fetch(PDO::FETCH_ASSOC);
                $balance = $w_row ? (int)$w_row["balance"] : 0;

                $new_balance = $balance + $reward_coins;
                $up = $pdo->prepare("UPDATE user_wallets SET balance = ? WHERE user_id = ?");
                $up->execute([$new_balance, $uid]);

                $meta_json = json_encode(["type" => "puzzle_complete", "puzzle_id" => $puzzle_id], JSON_UNESCAPED_UNICODE);
                $ins_tx = $pdo->prepare("
                    INSERT INTO coin_transactions (user_id, delta, type, reason, meta, balance_after)
                    VALUES (?, ?, 'earn', 'puzzle_complete', ?, ?)
                ");
                $ins_tx->execute([$uid, $reward_coins, $meta_json, $new_balance]);

                // ピースをリセット（次のパズルへ）
                $del = $pdo->prepare("DELETE FROM puzzle_pieces WHERE user_id = ? AND puzzle_id = ?");
                $del->execute([$uid, $puzzle_id]);

                $pdo->commit();

                send_response(200, [
                    "message" => "ok",
                    "user_id" => $uid,
                    "puzzle_id" => $puzzle_id,
                    "reward_coins" => $reward_coins,
                    "coin_balance" => $new_balance
                ]);
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    default:
        send_error(400, "bad_request", "Unknown action", null, null, "error.unknown_action");
}
