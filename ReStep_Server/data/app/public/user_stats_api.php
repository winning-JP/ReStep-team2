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

// JSONリクエストをPOSTへ反映
if (stripos($_SERVER["CONTENT_TYPE"] ?? "", "application/json") !== false) {
    $raw = file_get_contents("php://input");
    if ($raw) {
        $json = json_decode($raw, true);
        if (is_array($json)) $_POST = array_merge($_POST, $json);
    }
}

/* ============================
   AUTH via COOKIE (same style)
============================ */
function require_user_cookie($pdo)
{
    // refresh_tokenからユーザーを取得
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

/* ============================
   DATE / VALIDATION HELPERS
============================ */
function parse_ymd_slash_to_db($date_str)
{
    // "YYYY/MM/DD" -> "YYYY-MM-DD"
    if (!is_string($date_str)) return [false, null];
    $date_str = trim($date_str);
    if (!preg_match('/^\d{4}\/\d{2}\/\d{2}$/', $date_str)) return [false, null];

    [$y, $m, $d] = array_map("intval", explode("/", $date_str));
    if (!checkdate($m, $d, $y)) return [false, null];

    return [true, sprintf("%04d-%02d-%02d", $y, $m, $d)];
}

function format_db_to_ymd_slash($date_db)
{
    // DB日付を "YYYY/MM/DD" に整形
    if ($date_db === null) return null;
    $t = strtotime($date_db);
    if ($t === false) return null;
    return date("Y/m/d", $t);
}

function get_int_param($key, $min, $max, &$field_errors, $required = false)
{
    if (!array_key_exists($key, $_POST)) {
        if ($required) $field_errors[$key] = "required";
        return null;
    }
    $v = $_POST[$key];

    if ($v === null || $v === "") {
        if ($required) $field_errors[$key] = "required";
        return null;
    }

    if (is_string($v) && is_numeric($v)) $v = $v + 0;

    if (!is_int($v) && !is_float($v)) {
        $field_errors[$key] = "invalid";
        return null;
    }

    $v = (int)$v;

    if ($v < $min || $v > $max) {
        $field_errors[$key] = "out_of_range";
        return null;
    }

    return $v;
}

function get_float_param($key, $min, $max, &$field_errors, $required = false)
{
    if (!array_key_exists($key, $_POST)) {
        if ($required) $field_errors[$key] = "required";
        return null;
    }
    $v = $_POST[$key];

    if ($v === null || $v === "") {
        if ($required) $field_errors[$key] = "required";
        return null;
    }

    if (is_string($v) && is_numeric($v)) $v = $v + 0;

    if (!is_int($v) && !is_float($v)) {
        $field_errors[$key] = "invalid";
        return null;
    }

    $v = (float)$v;

    if ($v < $min || $v > $max) {
        $field_errors[$key] = "out_of_range";
        return null;
    }

    return $v;
}

/* ============================
   CONTINUITY HELPERS
============================ */
function get_continuity_row($pdo, $user_id)
{
    // 連続記録の現状を取得
    $stmt = $pdo->prepare("
        SELECT user_id, current_streak, longest_streak, last_active_date, updated_at
        FROM user_continuity
        WHERE user_id = ?
        LIMIT 1
    ");
    $stmt->execute([$user_id]);
    return $stmt->fetch(PDO::FETCH_ASSOC);
}

function upsert_continuity_for_date($pdo, $user_id, $date_db)
{
    // 指定日の連続記録を更新（同日や過去日は冪等）
    $row = get_continuity_row($pdo, $user_id);
    $idempotent = false;

    if (!$row) {
        $current = 1;
        $longest = 1;
        $last_active = $date_db;
        $stmt = $pdo->prepare("
            INSERT INTO user_continuity (user_id, current_streak, longest_streak, last_active_date)
            VALUES (?, ?, ?, ?)
        ");
        $stmt->execute([$user_id, $current, $longest, $last_active]);
        return [
            "current_streak" => $current,
            "longest_streak" => $longest,
            "last_active_date" => $last_active,
            "idempotent" => false
        ];
    }

    $current = (int)$row["current_streak"];
    $longest = (int)$row["longest_streak"];
    $last_active = $row["last_active_date"];

    if ($last_active === $date_db) {
        $idempotent = true;
    } else {
        $last_ts = $last_active ? strtotime($last_active) : null;
        $date_ts = strtotime($date_db);

        if ($last_ts !== null && $date_ts < $last_ts) {
            $idempotent = true;
        } else {
            if ($last_ts !== null && ($date_ts - $last_ts) === 86400) {
                $current = $current + 1;
            } else {
                $current = 1;
            }
            $longest = max($longest, $current);
            $last_active = $date_db;

            $stmt = $pdo->prepare("
                UPDATE user_continuity
                SET current_streak = ?, longest_streak = ?, last_active_date = ?, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = ?
            ");
            $stmt->execute([$current, $longest, $last_active, $user_id]);
        }
    }

    return [
        "current_streak" => $current,
        "longest_streak" => $longest,
        "last_active_date" => $last_active,
        "idempotent" => $idempotent
    ];
}

/* ============================
   ACTION
============================ */
$action = $_POST["action"] ?? "";

switch ($action) {

    /* ---------- SEED CONTINUITY ---------- */
    case "seed_continuity": {
            // 初期値を入れる（クライアントの移行向け）
            $user = require_login($pdo);
            $user_id = (int)$user["id"];

            $field_errors = [];
            $current = get_int_param("current_streak", 1, 36500, $field_errors, true);
            $longest = get_int_param("longest_streak", 1, 36500, $field_errors, true);

            $last_active_in = $_POST["last_active_date"] ?? null;
            $last_active_db = null;
            if ($last_active_in !== null && $last_active_in !== "") {
                [$ok, $last_active_db] = parse_ymd_slash_to_db($last_active_in);
                if (!$ok) {
                    $field_errors["last_active_date"] = "invalid_date";
                }
            }

            if (!empty($field_errors)) {
                send_error(422, "validation_failed", "Validation failed", null, $field_errors, "error.validation_failed");
            }

            if ($longest < $current) {
                send_error(422, "validation_failed", "Validation failed", null, ["longest_streak" => "must_be_greater_or_equal"], "error.validation_failed");
            }

            try {
                $pdo->beginTransaction();

                $existing = get_continuity_row($pdo, $user_id);
                if ($existing) {
                    $existing_current = (int)$existing["current_streak"];
                    $existing_longest = (int)$existing["longest_streak"];
                    $existing_last = $existing["last_active_date"];

                    $next_current = max($existing_current, $current);
                    $next_longest = max($existing_longest, $longest, $next_current);
                    $next_last = $existing_last;
                    if ($last_active_db !== null) {
                        if ($existing_last === null || strtotime($last_active_db) > strtotime($existing_last)) {
                            $next_last = $last_active_db;
                        }
                    }

                    if ($next_current === $existing_current && $next_longest === $existing_longest && $next_last === $existing_last) {
                        $pdo->commit();
                        send_response(200, [
                            "current_streak" => (int)$existing_current,
                            "longest_streak" => (int)$existing_longest,
                            "last_active_date" => format_db_to_ymd_slash($existing_last),
                            "updated_at" => $existing["updated_at"],
                            "seeded" => false,
                            "idempotent" => true
                        ]);
                    }

                    $stmt = $pdo->prepare("
                        UPDATE user_continuity
                        SET current_streak = ?, longest_streak = ?, last_active_date = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE user_id = ?
                    ");
                    $stmt->execute([$next_current, $next_longest, $next_last, $user_id]);

                    $pdo->commit();
                    send_response(200, [
                        "current_streak" => (int)$next_current,
                        "longest_streak" => (int)$next_longest,
                        "last_active_date" => format_db_to_ymd_slash($next_last),
                        "seeded" => true,
                        "idempotent" => false
                    ]);
                }

                if ($last_active_db === null) {
                    $last_active_db = date("Y-m-d");
                }

                $stmt = $pdo->prepare("
                    INSERT INTO user_continuity (user_id, current_streak, longest_streak, last_active_date)
                    VALUES (?, ?, ?, ?)
                ");
                $stmt->execute([$user_id, $current, $longest, $last_active_db]);

                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }

            send_response(200, [
                "current_streak" => (int)$current,
                "longest_streak" => (int)$longest,
                "last_active_date" => format_db_to_ymd_slash($last_active_db),
                "seeded" => true,
                "idempotent" => false
            ]);
            break;
        }

    /* ---------- RECORD CONTINUITY ---------- */
    case "record_continuity": {
            // 指定日を活動日として記録
            $user = require_login($pdo);
            $user_id = (int)$user["id"];

            $date_in = $_POST["date"] ?? null;
            if ($date_in === null || $date_in === "") {
                $date_db = date("Y-m-d");
            } else {
                [$ok, $date_db] = parse_ymd_slash_to_db($date_in);
                if (!$ok) {
                    send_error(422, "validation_failed", "Validation failed", null, ["date" => "invalid_date"], "error.validation_failed");
                }
            }

            try {
                $pdo->beginTransaction();

                $result = upsert_continuity_for_date($pdo, $user_id, $date_db);

                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }

            send_response(200, [
                "current_streak" => (int)$result["current_streak"],
                "longest_streak" => (int)$result["longest_streak"],
                "last_active_date" => format_db_to_ymd_slash($result["last_active_date"]),
                "idempotent" => $result["idempotent"] ? true : false
            ]);
            break;
        }

        /* ---------- GET CONTINUITY ---------- */
    case "get_continuity": {
            // 連続記録の取得
            $user = require_login($pdo);
            $user_id = (int)$user["id"];

            $row = get_continuity_row($pdo, $user_id);
            if (!$row) {
                send_response(200, [
                    "current_streak" => 0,
                    "longest_streak" => 0,
                    "last_active_date" => null,
                    "updated_at" => null
                ]);
            }

            send_response(200, [
                "current_streak" => (int)$row["current_streak"],
                "longest_streak" => (int)$row["longest_streak"],
                "last_active_date" => format_db_to_ymd_slash($row["last_active_date"]),
                "updated_at" => $row["updated_at"]
            ]);
            break;
        }

    /* ---------- SAVE DAILY (UPSERT) ---------- */
    case "save_daily": {
            // 日次の歩数・消費・距離を保存（UPSERT）
            $user = require_login($pdo);
            $user_id = (int)$user["id"];

            $field_errors = [];

            $date_in = $_POST["date"] ?? null;
            if ($date_in === null || $date_in === "") {
                $field_errors["date"] = "required";
            }

            $steps    = get_int_param("steps", 0, 100000, $field_errors, true);
            $calories = get_int_param("calories", 0, 10000, $field_errors, true);
            $distance = get_float_param("distance_km", 0.0, 200.0, $field_errors, true);

            if (!empty($field_errors)) {
                send_error(422, "validation_failed", "Validation failed", null, $field_errors, "error.validation_failed");
            }

            [$ok, $date_db] = parse_ymd_slash_to_db($date_in);
            if (!$ok) {
                send_error(422, "validation_failed", "Validation failed", null, ["date" => "invalid_date"], "error.validation_failed");
            }

            try {
                $pdo->beginTransaction();

                $stmt = $pdo->prepare("
                INSERT INTO user_daily_stats (user_id, date, steps, calories, distance_km)
                VALUES (?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                    steps = VALUES(steps),
                    calories = VALUES(calories),
                    distance_km = VALUES(distance_km),
                    updated_at = CURRENT_TIMESTAMP
            ");
                $stmt->execute([$user_id, $date_db, $steps, $calories, $distance]);

                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }

            send_response(200, ["message" => "saved"]);
            break;
        }

        /* ---------- GET DAILY (ONE DAY) ---------- */
    case "get_daily": {
            // 指定日の記録を取得
            $user = require_login($pdo);
            $user_id = (int)$user["id"];

            $date_in = $_POST["date"] ?? "";
            if (!$date_in) {
                send_error(400, "bad_request", "date required", null, ["date" => "required"], "error.date_required");
            }

            [$ok, $date_db] = parse_ymd_slash_to_db($date_in);
            if (!$ok) {
                send_error(422, "validation_failed", "Validation failed", null, ["date" => "invalid_date"], "error.validation_failed");
            }

            $stmt = $pdo->prepare("
            SELECT date, steps, calories, distance_km, updated_at
            FROM user_daily_stats
            WHERE user_id = ? AND date = ?
            LIMIT 1
        ");
            $stmt->execute([$user_id, $date_db]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!$row) {
                send_response(200, [
                    "date" => format_db_to_ymd_slash($date_db),
                    "steps" => 0,
                    "calories" => 0,
                    "distance_km" => 0.0,
                    "updated_at" => null
                ]);
            }

            send_response(200, [
                "date" => format_db_to_ymd_slash($row["date"]),
                "steps" => (int)$row["steps"],
                "calories" => (int)$row["calories"],
                "distance_km" => (float)$row["distance_km"],
                "updated_at" => $row["updated_at"]
            ]);
            break;
        }

        /* ---------- GET RANGE ---------- */
    case "get_range": {
            // 期間範囲の記録を取得
            $user = require_login($pdo);
            $user_id = (int)$user["id"];

            $from_in = $_POST["from"] ?? "";
            $to_in   = $_POST["to"] ?? "";

            $field_errors = [];
            if (!$from_in) $field_errors["from"] = "required";
            if (!$to_in) $field_errors["to"] = "required";
            if (!empty($field_errors)) {
                send_error(400, "bad_request", "from/to required", null, $field_errors, "error.missing_fields");
            }

            [$ok1, $from_db] = parse_ymd_slash_to_db($from_in);
            [$ok2, $to_db]   = parse_ymd_slash_to_db($to_in);

            $fe = [];
            if (!$ok1) $fe["from"] = "invalid_date";
            if (!$ok2) $fe["to"] = "invalid_date";
            if (!empty($fe)) {
                send_error(422, "validation_failed", "Validation failed", null, $fe, "error.validation_failed");
            }

            if (strtotime($from_db) > strtotime($to_db)) {
                send_error(422, "validation_failed", "Validation failed", null, ["range" => "from_must_be_before_or_equal_to"], "error.validation_failed");
            }

            $days = (strtotime($to_db) - strtotime($from_db)) / 86400;
            if ($days > 366) {
                send_error(422, "validation_failed", "Validation failed", null, ["range" => "too_large"], "error.validation_failed");
            }

            $stmt = $pdo->prepare("
            SELECT date, steps, calories, distance_km
            FROM user_daily_stats
            WHERE user_id = ?
              AND date BETWEEN ? AND ?
            ORDER BY date ASC
        ");
            $stmt->execute([$user_id, $from_db, $to_db]);
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

            $items = [];
            foreach ($rows as $r) {
                $items[] = [
                    "date" => format_db_to_ymd_slash($r["date"]),
                    "steps" => (int)$r["steps"],
                    "calories" => (int)$r["calories"],
                    "distance_km" => (float)$r["distance_km"]
                ];
            }

            send_response(200, ["items" => $items]);
            break;
        }

        /* ---------- GET WEEKLY SUMMARY ---------- */
    case "get_weekly_summary": {
            // 週次サマリーを取得
            $user = require_login($pdo);
            $user_id = (int)$user["id"];

            $date_in = $_POST["date"] ?? date("Y/m/d");

            [$ok, $date_db] = parse_ymd_slash_to_db($date_in);
            if (!$ok) {
                send_error(422, "validation_failed", "Validation failed", null, ["date" => "invalid_date"], "error.validation_failed");
            }

            $dayOfWeek = (int)date('N', strtotime($date_db));
            $monday = date('Y-m-d', strtotime($date_db . ' -' . ($dayOfWeek - 1) . ' days'));
            $sunday = date('Y-m-d', strtotime($monday . ' +6 days'));

            $stmt = $pdo->prepare("
                SELECT
                    COALESCE(SUM(steps), 0) AS total_steps,
                    COALESCE(SUM(calories), 0) AS total_calories,
                    COALESCE(SUM(distance_km), 0) AS total_distance_km,
                    COUNT(*) AS days_recorded
                FROM user_daily_stats
                WHERE user_id = ?
                  AND date BETWEEN ? AND ?
            ");
            $stmt->execute([$user_id, $monday, $sunday]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);

            $total_steps = (int)$row["total_steps"];
            $total_calories = (int)$row["total_calories"];
            $total_distance = (float)$row["total_distance_km"];
            $days_recorded = (int)$row["days_recorded"];

            send_response(200, [
                "week_start" => format_db_to_ymd_slash($monday),
                "week_end" => format_db_to_ymd_slash($sunday),
                "total_steps" => $total_steps,
                "total_calories" => $total_calories,
                "total_distance_km" => round($total_distance, 2),
                "days_recorded" => $days_recorded,
                "avg_steps" => $days_recorded > 0 ? (int)round($total_steps / $days_recorded) : 0,
                "avg_calories" => $days_recorded > 0 ? (int)round($total_calories / $days_recorded) : 0,
                "avg_distance_km" => $days_recorded > 0 ? round($total_distance / $days_recorded, 2) : 0.0
            ]);
            break;
        }

        /* ---------- GET MONTHLY SUMMARY ---------- */
    case "get_monthly_summary": {
            $user = require_login($pdo);
            $user_id = (int)$user["id"];

            $field_errors = [];

            $year = (int)date("Y");
            if (isset($_POST["year"]) && $_POST["year"] !== "" && $_POST["year"] !== null) {
                $year = get_int_param("year", 2000, 2100, $field_errors, false);
                if ($year === null) $year = (int)date("Y");
            }

            $month = (int)date("n");
            if (isset($_POST["month"]) && $_POST["month"] !== "" && $_POST["month"] !== null) {
                $month = get_int_param("month", 1, 12, $field_errors, false);
                if ($month === null) $month = (int)date("n");
            }

            if (!empty($field_errors)) {
                send_error(422, "validation_failed", "Validation failed", null, $field_errors, "error.validation_failed");
            }

            $start_of_month = sprintf('%04d-%02d-01', $year, $month);
            $end_of_month = date('Y-m-t', strtotime($start_of_month));
            $days_in_month = (int)date('t', strtotime($start_of_month));

            $stmt = $pdo->prepare("
                SELECT
                    COALESCE(SUM(steps), 0) AS total_steps,
                    COALESCE(SUM(calories), 0) AS total_calories,
                    COALESCE(SUM(distance_km), 0) AS total_distance_km,
                    COUNT(*) AS days_recorded
                FROM user_daily_stats
                WHERE user_id = ?
                  AND date BETWEEN ? AND ?
            ");
            $stmt->execute([$user_id, $start_of_month, $end_of_month]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);

            $total_steps = (int)$row["total_steps"];
            $total_calories = (int)$row["total_calories"];
            $total_distance = (float)$row["total_distance_km"];
            $days_recorded = (int)$row["days_recorded"];

            send_response(200, [
                "year" => $year,
                "month" => $month,
                "days_in_month" => $days_in_month,
                "total_steps" => $total_steps,
                "total_calories" => $total_calories,
                "total_distance_km" => round($total_distance, 2),
                "days_recorded" => $days_recorded,
                "avg_steps" => $days_recorded > 0 ? (int)round($total_steps / $days_recorded) : 0,
                "avg_calories" => $days_recorded > 0 ? (int)round($total_calories / $days_recorded) : 0,
                "avg_distance_km" => $days_recorded > 0 ? round($total_distance / $days_recorded, 2) : 0.0
            ]);
            break;
        }

    default:
        send_error(400, "bad_request", "Unknown action", null, null, "error.unknown_action");
}