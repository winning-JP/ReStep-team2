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
   ACTION
============================ */
$action = $_POST["action"] ?? "";

switch ($action) {

    case "post": {
            // 記事投稿（コイン50消費）
            $user = require_login($pdo);
            $uid = (int)$user["id"];
            $cost = 50;

            $title = isset($_POST["title"]) ? trim((string)$_POST["title"]) : "";
            $body = isset($_POST["body"]) ? trim((string)$_POST["body"]) : "";

            if ($title === "" || mb_strlen($title) > 200) {
                send_error(422, "validation_error", "title is required (max 200 chars)", null, ["title" => "Invalid title"]);
            }
            if ($body === "") {
                send_error(422, "validation_error", "body is required", null, ["body" => "Body is required"]);
            }

            $image_url = isset($_POST["image_url"]) ? mb_substr(trim((string)$_POST["image_url"]), 0, 500) : null;

            $pdo->beginTransaction();
            try {
                // コイン残高チェック・消費
                ensure_wallet_exists($pdo, $uid);
                $stmt = $pdo->prepare("SELECT balance FROM user_wallets WHERE user_id = ? FOR UPDATE");
                $stmt->execute([$uid]);
                $row = $stmt->fetch(PDO::FETCH_ASSOC);
                $balance = $row ? (int)$row["balance"] : 0;

                if ($balance < $cost) {
                    $pdo->rollBack();
                    send_error(409, "insufficient_coins", "Not enough coins to post article", [
                        "balance" => $balance,
                        "required" => $cost
                    ], null, "coin.insufficient");
                }

                $new_balance = $balance - $cost;
                $up = $pdo->prepare("UPDATE user_wallets SET balance = ? WHERE user_id = ?");
                $up->execute([$new_balance, $uid]);

                // コイン取引記録
                $meta_json = json_encode(["type" => "article_post", "cost" => $cost], JSON_UNESCAPED_UNICODE);
                $ins_tx = $pdo->prepare("
                    INSERT INTO coin_transactions (user_id, delta, type, reason, meta, balance_after)
                    VALUES (?, ?, 'spend', 'article_post', ?, ?)
                ");
                $ins_tx->execute([$uid, -$cost, $meta_json, $new_balance]);

                // 記事作成
                $ins = $pdo->prepare("INSERT INTO articles (user_id, title, body, image_url) VALUES (?, ?, ?, ?)");
                $ins->execute([$uid, $title, $body, $image_url]);
                $article_id = (int)$pdo->lastInsertId();

                $pdo->commit();

                send_response(200, [
                    "message" => "ok",
                    "article_id" => $article_id,
                    "coin_balance" => $new_balance,
                    "coin_used" => $cost
                ]);
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "list": {
            // 記事一覧（ソート: new/popular/views）
            $user = require_login($pdo);

            $sort = $_POST["sort"] ?? "new";
            if (!in_array($sort, ["new", "popular", "views"])) $sort = "new";

            $limit_raw = $_POST["limit"] ?? 20;
            $limit = max(1, min(100, (int)$limit_raw));

            $offset_raw = $_POST["offset"] ?? 0;
            $offset = max(0, (int)$offset_raw);

            $order_by = match ($sort) {
                "popular" => "a.reaction_count DESC, a.created_at DESC",
                "views" => "a.view_count DESC, a.created_at DESC",
                default => "a.created_at DESC"
            };

            try {
                $stmt = $pdo->prepare("
                    SELECT a.id, a.user_id, a.title, a.body, a.image_url,
                           a.view_count, a.reaction_count, a.created_at,
                           COALESCE(p.nickname, '名無し') AS nickname
                    FROM articles a
                    LEFT JOIN user_profiles p ON p.user_id = a.user_id
                    ORDER BY $order_by
                    LIMIT " . (int)$limit . " OFFSET " . (int)$offset . "
                ");
                $stmt->execute();
                $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

                $items = [];
                foreach ($rows as $r) {
                    $items[] = [
                        "id" => (int)$r["id"],
                        "user_id" => (int)$r["user_id"],
                        "nickname" => $r["nickname"],
                        "title" => $r["title"],
                        "body" => mb_substr($r["body"], 0, 200),
                        "image_url" => $r["image_url"],
                        "view_count" => (int)$r["view_count"],
                        "reaction_count" => (int)$r["reaction_count"],
                        "created_at" => $r["created_at"]
                    ];
                }

                // 総件数
                $count_stmt = $pdo->query("SELECT COUNT(*) FROM articles");
                $total = (int)$count_stmt->fetchColumn();

                send_response(200, [
                    "items" => $items,
                    "total" => $total,
                    "sort" => $sort,
                    "limit" => $limit,
                    "offset" => $offset
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "detail": {
            // 記事詳細（閲覧数カウント）
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $article_id = isset($_POST["article_id"]) ? (int)$_POST["article_id"] : null;
            if (!$article_id) send_error(422, "validation_error", "article_id is required");

            try {
                $stmt = $pdo->prepare("
                    SELECT a.*, COALESCE(p.nickname, '名無し') AS nickname
                    FROM articles a
                    LEFT JOIN user_profiles p ON p.user_id = a.user_id
                    WHERE a.id = ?
                    LIMIT 1
                ");
                $stmt->execute([$article_id]);
                $article = $stmt->fetch(PDO::FETCH_ASSOC);

                if (!$article) send_error(404, "not_found", "Article not found");

                // 閲覧記録（1ユーザー1回）
                $ins_view = $pdo->prepare("INSERT IGNORE INTO article_views (article_id, user_id) VALUES (?, ?)");
                $ins_view->execute([$article_id, $uid]);

                if ($ins_view->rowCount() > 0) {
                    $up_count = $pdo->prepare("UPDATE articles SET view_count = view_count + 1 WHERE id = ?");
                    $up_count->execute([$article_id]);
                    $article["view_count"] = (int)$article["view_count"] + 1;
                }

                // ユーザーのリアクション状態
                $stmt_react = $pdo->prepare("SELECT type FROM article_reactions WHERE article_id = ? AND user_id = ?");
                $stmt_react->execute([$article_id, $uid]);
                $user_reactions = array_column($stmt_react->fetchAll(PDO::FETCH_ASSOC), "type");

                send_response(200, [
                    "id" => (int)$article["id"],
                    "user_id" => (int)$article["user_id"],
                    "nickname" => $article["nickname"],
                    "title" => $article["title"],
                    "body" => $article["body"],
                    "image_url" => $article["image_url"],
                    "view_count" => (int)$article["view_count"],
                    "reaction_count" => (int)$article["reaction_count"],
                    "created_at" => $article["created_at"],
                    "user_reactions" => $user_reactions
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "react": {
            // リアクション（トグル）
            $user = require_login($pdo);
            $uid = (int)$user["id"];

            $article_id = isset($_POST["article_id"]) ? (int)$_POST["article_id"] : null;
            if (!$article_id) send_error(422, "validation_error", "article_id is required");

            $type = isset($_POST["type"]) ? (string)$_POST["type"] : "like";
            if (!in_array($type, ["like", "heart", "clap", "fire"])) $type = "like";

            try {
                // 既存リアクションチェック
                $stmt = $pdo->prepare("SELECT id FROM article_reactions WHERE article_id = ? AND user_id = ? AND type = ?");
                $stmt->execute([$article_id, $uid, $type]);
                $existing = $stmt->fetch(PDO::FETCH_ASSOC);

                if ($existing) {
                    // 取り消し
                    $del = $pdo->prepare("DELETE FROM article_reactions WHERE id = ?");
                    $del->execute([(int)$existing["id"]]);
                    $up = $pdo->prepare("UPDATE articles SET reaction_count = GREATEST(0, reaction_count - 1) WHERE id = ?");
                    $up->execute([$article_id]);
                    $added = false;
                } else {
                    // 追加
                    $ins = $pdo->prepare("INSERT INTO article_reactions (article_id, user_id, type) VALUES (?, ?, ?)");
                    $ins->execute([$article_id, $uid, $type]);
                    $up = $pdo->prepare("UPDATE articles SET reaction_count = reaction_count + 1 WHERE id = ?");
                    $up->execute([$article_id]);
                    $added = true;
                }

                // 最新のカウント取得
                $stmt2 = $pdo->prepare("SELECT reaction_count FROM articles WHERE id = ?");
                $stmt2->execute([$article_id]);
                $count = (int)$stmt2->fetchColumn();

                send_response(200, [
                    "message" => "ok",
                    "article_id" => $article_id,
                    "type" => $type,
                    "added" => $added,
                    "reaction_count" => $count
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    case "ranking": {
            // ランキング（リアクション数 or 閲覧数）
            $user = require_login($pdo);

            $rank_by = $_POST["rank_by"] ?? "reactions";
            if (!in_array($rank_by, ["reactions", "views"])) $rank_by = "reactions";

            $limit_raw = $_POST["limit"] ?? 20;
            $limit = max(1, min(50, (int)$limit_raw));

            $order = $rank_by === "views" ? "a.view_count DESC" : "a.reaction_count DESC";

            try {
                $stmt = $pdo->prepare("
                    SELECT a.id, a.user_id, a.title,
                           a.view_count, a.reaction_count, a.created_at,
                           COALESCE(p.nickname, '名無し') AS nickname
                    FROM articles a
                    LEFT JOIN user_profiles p ON p.user_id = a.user_id
                    ORDER BY $order, a.created_at DESC
                    LIMIT " . (int)$limit . "
                ");
                $stmt->execute();
                $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

                $items = [];
                $rank = 1;
                foreach ($rows as $r) {
                    $items[] = [
                        "rank" => $rank++,
                        "id" => (int)$r["id"],
                        "user_id" => (int)$r["user_id"],
                        "nickname" => $r["nickname"],
                        "title" => $r["title"],
                        "view_count" => (int)$r["view_count"],
                        "reaction_count" => (int)$r["reaction_count"],
                        "created_at" => $r["created_at"]
                    ];
                }

                send_response(200, [
                    "rank_by" => $rank_by,
                    "items" => $items
                ]);
            } catch (Exception $e) {
                send_error(500, "db_error", "Database error", $e->getMessage());
            }
            break;
        }

    default:
        send_error(400, "bad_request", "Unknown action", null, null, "error.unknown_action");
}
