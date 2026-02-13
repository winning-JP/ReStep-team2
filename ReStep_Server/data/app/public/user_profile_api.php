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

// JSONリクエストの本文をPOSTへ反映
if (stripos($_SERVER["CONTENT_TYPE"] ?? "", "application/json") !== false) {
    $raw = file_get_contents("php://input");
    if ($raw) {
        $json = json_decode($raw, true);
        if (is_array($json)) $_POST = array_merge($_POST, $json);
    }
}

/* ============================
   USER AUTH via COOKIE
============================ */
function require_user_cookie($pdo)
{
    // refresh_tokenからユーザーを取得
    $refresh = $_COOKIE["refresh_token"] ?? "";
    if (!$refresh) return null;

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

    return $stmt->fetch(PDO::FETCH_ASSOC);
}

function ensure_encounter_columns($pdo)
{
    static $done = false;
    if ($done) return;
    $done = true;

    $hasBluetoothId = false;
    $hasVisibility = false;
    $hasBluetoothUnique = false;

    $columns = $pdo->query("SHOW COLUMNS FROM user_profiles")->fetchAll(PDO::FETCH_ASSOC);
    foreach ($columns as $col) {
        $name = $col["Field"] ?? "";
        if ($name === "bluetooth_user_id") $hasBluetoothId = true;
        if ($name === "encounter_visibility") $hasVisibility = true;
    }

    if (!$hasBluetoothId) {
        $pdo->exec("ALTER TABLE user_profiles ADD COLUMN bluetooth_user_id varchar(64) DEFAULT NULL");
    }
    if (!$hasVisibility) {
        $pdo->exec("ALTER TABLE user_profiles ADD COLUMN encounter_visibility enum('public','private') NOT NULL DEFAULT 'public'");
    }

    $indexes = $pdo->query("SHOW INDEX FROM user_profiles")->fetchAll(PDO::FETCH_ASSOC);
    foreach ($indexes as $idx) {
        if (($idx["Key_name"] ?? "") === "uniq_bluetooth_user_id") {
            $hasBluetoothUnique = true;
            break;
        }
    }

    if (!$hasBluetoothUnique) {
        $pdo->exec("CREATE UNIQUE INDEX uniq_bluetooth_user_id ON user_profiles (bluetooth_user_id)");
    }
}

/* ============================
   PROFILE FIELD DEFS
============================ */
const PROFILE_FIELDS = [
    "nickname",
    "birthday",
    "gender",
    "height_cm",
    "weight_kg",
    "weekly_steps",
    "body_fat",
    "weekly_exercise",
    "goal_steps",
    "goal_calories",
    "goal_distance_km",
];

/* ============================
   DATE HELPERS
============================ */
function parse_birthday_to_db($birthday_str)
{
    // "YYYY/MM/DD" -> "YYYY-MM-DD"
    if (!is_string($birthday_str)) return [false, null];
    $birthday_str = trim($birthday_str);
    if ($birthday_str === "") return [true, null];

    if (!preg_match('/^\d{4}\/\d{2}\/\d{2}$/', $birthday_str)) return [false, null];

    [$y, $m, $d] = array_map("intval", explode("/", $birthday_str));
    if (!checkdate($m, $d, $y)) return [false, null];

    return [true, sprintf("%04d-%02d-%02d", $y, $m, $d)];
}

function format_birthday_from_db($birthday_db)
{
    // DB日付を "YYYY/MM/DD" に整形
    if ($birthday_db === null) return null;
    if (!is_string($birthday_db) || trim($birthday_db) === "") return null;

    $birthday_db = trim($birthday_db);
    if ($birthday_db === "0000-00-00" || $birthday_db === "0000-00-00 00:00:00") return null;

    $t = strtotime($birthday_db);
    if ($t === false) return null;

    return date("Y/m/d", $t);
}

function normalize_bluetooth_user_id($raw)
{
    if (!is_string($raw)) return null;
    $value = trim($raw);
    if ($value === "") return null;
    if (strlen($value) > 64) return null;
    if (!preg_match('/^[A-Za-z0-9\-]+$/', $value)) return null;
    return $value;
}

function parse_bool_value($raw)
{
    if (is_bool($raw)) return $raw;
    if (is_int($raw)) return $raw !== 0;
    if (is_string($raw)) {
        $v = strtolower(trim($raw));
        if ($v === "1" || $v === "true" || $v === "yes" || $v === "on") return true;
        if ($v === "0" || $v === "false" || $v === "no" || $v === "off") return false;
    }
    return null;
}

/* ============================
   VALIDATION
============================ */
function validate_profile_payload($profile)
{
    // 入力の型・範囲・フィールド名を検証して正規化
    $errors = [];
    $clean  = [];

    if (!is_array($profile)) {
        return [false, null, ["profile" => "invalid"], "error.invalid_profile_object"];
    }

    foreach ($profile as $k => $_v) {
        if (!in_array($k, PROFILE_FIELDS, true)) {
            $errors[$k] = "unknown_field";
        }
    }

    if (array_key_exists("nickname", $profile)) {
        $v = $profile["nickname"];
        if ($v === null || $v === "") {
            $clean["nickname"] = null;
        } elseif (!is_string($v)) {
            $errors["nickname"] = "invalid";
        } else {
            $v = trim($v);
            if (mb_strlen($v) > 20) $errors["nickname"] = "too_long";
            else $clean["nickname"] = $v;
        }
    }

    if (array_key_exists("birthday", $profile)) {
        $v = $profile["birthday"];
        if ($v === null || $v === "") {
            $clean["birthday"] = null;
        } else {
            [$ok, $db] = parse_birthday_to_db($v);
            if (!$ok) $errors["birthday"] = "invalid_date";
            else $clean["birthday"] = $db;
        }
    }

    if (array_key_exists("gender", $profile)) {
        $v = $profile["gender"];
        if ($v === null || $v === "") {
            $clean["gender"] = null;
        } elseif (!is_string($v)) {
            $errors["gender"] = "invalid";
        } else {
            $v = trim($v);
            if (!in_array($v, ["男性", "女性", "その他"], true)) $errors["gender"] = "invalid_choice";
            else $clean["gender"] = $v;
        }
    }

    $num_rules = [
        "height_cm" => ["min" => 120.0, "max" => 220.0, "type" => "float"],
        "weight_kg" => ["min" => 20.0,  "max" => 200.0, "type" => "float"],
        "weekly_steps" => ["min" => 0, "max" => 30000, "type" => "int"],
        "body_fat" => ["min" => 3, "max" => 60, "type" => "int"],
        "weekly_exercise" => ["min" => 0, "max" => 14, "type" => "int"],
        "goal_steps" => ["min" => 1000, "max" => 50000, "type" => "int"],
        "goal_calories" => ["min" => 100, "max" => 2000, "type" => "int"],
        "goal_distance_km" => ["min" => 0.0, "max" => 50.0, "type" => "float"],
    ];

    foreach ($num_rules as $k => $r) {
        if (!array_key_exists($k, $profile)) continue;

        $v = $profile[$k];
        if ($v === null || $v === "") {
            $clean[$k] = null;
            continue;
        }

        if (is_string($v) && trim($v) !== "" && is_numeric($v)) {
            $v = $v + 0;
        }

        if (!is_int($v) && !is_float($v)) {
            $errors[$k] = "invalid";
            continue;
        }

        if ($v < $r["min"] || $v > $r["max"]) {
            $errors[$k] = "out_of_range";
            continue;
        }

        $clean[$k] = ($r["type"] === "int") ? (int)$v : (float)$v;
    }

    if (!empty($errors)) {
        return [false, null, $errors, "error.validation_failed"];
    }

    return [true, $clean, null, null];
}

/* ============================
   DB HELPERS
============================ */
function ensure_profile_row_exists($pdo, $user_id)
{
    // プロフィール行が無ければ作成
    $pdo->prepare("INSERT IGNORE INTO user_profiles (user_id) VALUES (?)")->execute([$user_id]);
}

function fetch_profile($pdo, $user_id)
{
    // 現在のプロフィールを取得（無ければnull埋め）
    $stmt = $pdo->prepare("
        SELECT
            nickname,
            bluetooth_user_id,
            encounter_visibility,
            birthday,
            gender,
            height_cm,
            weight_kg,
            weekly_steps,
            body_fat,
            weekly_exercise,
            goal_steps,
            goal_calories,
            goal_distance_km,
            updated_at
        FROM user_profiles
        WHERE user_id = ?
        LIMIT 1
    ");
    $stmt->execute([$user_id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        return [
            "nickname" => null,
            "bluetooth_user_id" => null,
            "encounter_visibility" => "public",
            "birthday" => null,
            "gender" => null,
            "height_cm" => null,
            "weight_kg" => null,
            "weekly_steps" => null,
            "body_fat" => null,
            "weekly_exercise" => null,
            "goal_steps" => null,
            "goal_calories" => null,
            "goal_distance_km" => null,
            "updated_at" => null,
        ];
    }

    $row["birthday"] = format_birthday_from_db($row["birthday"]);
    if (!isset($row["encounter_visibility"]) || $row["encounter_visibility"] === null || $row["encounter_visibility"] === "") {
        $row["encounter_visibility"] = "public";
    }

    foreach (["height_cm", "weight_kg", "goal_distance_km"] as $k) {
        if ($row[$k] !== null) $row[$k] = (float)$row[$k];
    }
    foreach (["weekly_steps", "body_fat", "weekly_exercise", "goal_steps", "goal_calories"] as $k) {
        if ($row[$k] !== null) $row[$k] = (int)$row[$k];
    }

    return $row;
}

/* ============================
   ACTION
============================ */
$action = $_POST["action"] ?? "";
ensure_encounter_columns($pdo);

switch ($action) {

    /* ---------- GET PROFILE ---------- */
    case "get_profile": {
            // ログインユーザーのプロフィール取得
            $user = require_user_cookie($pdo);
            if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");

            $profile = fetch_profile($pdo, (int)$user["id"]);
            send_response(200, ["profile" => $profile]);
            break;
        }

        /* ---------- UPDATE PROFILE ---------- */
    case "update_profile": {
            // 全項目を一括更新（未指定はnull扱い）
            $user = require_user_cookie($pdo);
            if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");

            $profile_in = $_POST["profile"] ?? null;
            if (!is_array($profile_in)) {
                send_error(400, "bad_request", "profile required", null, ["profile" => "required"], "error.profile_required");
            }

            $full = [];
            foreach (PROFILE_FIELDS as $f) {
                $full[$f] = array_key_exists($f, $profile_in) ? $profile_in[$f] : null;
            }
            foreach ($profile_in as $k => $v) {
                if (!array_key_exists($k, $full)) $full[$k] = $v;
            }

            [$ok, $clean, $field_errors, $i18n_key] = validate_profile_payload($full);
            if (!$ok) {
                send_error(422, "validation_failed", "Validation failed", null, $field_errors, $i18n_key);
            }

            $user_id = (int)$user["id"];
            try {
                $pdo->beginTransaction();

                ensure_profile_row_exists($pdo, $user_id);

                $fields = [];
                $params = [];

                foreach (PROFILE_FIELDS as $k) {
                    if (!array_key_exists($k, $clean)) {
                        $clean[$k] = null;
                    }
                    $fields[] = "{$k} = ?";
                    $params[] = $clean[$k];
                }

                $params[] = $user_id;

                $sql = "UPDATE user_profiles SET " . implode(", ", $fields) . " WHERE user_id = ?";
                $pdo->prepare($sql)->execute($params);

                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }

            send_response(200, ["message" => "updated"]);
            break;
        }

        /* ---------- PATCH PROFILE ---------- */
    case "patch_profile": {
            // 指定項目のみ更新
            $user = require_user_cookie($pdo);
            if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");

            $profile_in = $_POST["profile"] ?? null;
            [$ok, $clean, $field_errors, $i18n_key] = validate_profile_payload($profile_in);
            if (!$ok) {
                send_error(422, "validation_failed", "Validation failed", null, $field_errors, $i18n_key);
            }
            if (empty($clean)) {
                send_error(400, "bad_request", "Nothing to update", null, null, "error.nothing_to_update");
            }

            $user_id = (int)$user["id"];
            try {
                $pdo->beginTransaction();

                ensure_profile_row_exists($pdo, $user_id);

                $fields = [];
                $params = [];

                foreach ($clean as $k => $v) {
                    if (!in_array($k, PROFILE_FIELDS, true)) continue;
                    $fields[] = "{$k} = ?";
                    $params[] = $v;
                }

                if (empty($fields)) {
                    if ($pdo->inTransaction()) $pdo->rollBack();
                    send_error(400, "bad_request", "Nothing to update", null, null, "error.nothing_to_update");
                }

                $params[] = $user_id;
                $sql = "UPDATE user_profiles SET " . implode(", ", $fields) . " WHERE user_id = ?";
                $pdo->prepare($sql)->execute($params);

                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }

            send_response(200, ["message" => "updated"]);
            break;
        }

        /* ---------- CLEAR PROFILE FIELDS ---------- */
    case "clear_profile_fields": {
            // 指定フィールドをNULLにクリア
            $user = require_user_cookie($pdo);
            if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");

            $fields_in = $_POST["fields"] ?? null;
            if (!is_array($fields_in) || empty($fields_in)) {
                send_error(400, "bad_request", "fields required", null, ["fields" => "required"], "error.fields_required");
            }

            $field_errors = [];
            $targets = [];

            foreach ($fields_in as $f) {
                if (!is_string($f)) {
                    $field_errors["fields"] = "invalid";
                    continue;
                }
                $f = trim($f);
                if (!in_array($f, PROFILE_FIELDS, true)) {
                    $field_errors[$f] = "unknown_field";
                    continue;
                }
                $targets[] = $f;
            }

            $targets = array_values(array_unique($targets));

            if (!empty($field_errors)) {
                send_error(422, "validation_failed", "Validation failed", null, $field_errors, "error.validation_failed");
            }
            if (empty($targets)) {
                send_error(400, "bad_request", "Nothing to clear", null, null, "error.nothing_to_update");
            }

            $user_id = (int)$user["id"];
            try {
                $pdo->beginTransaction();

                ensure_profile_row_exists($pdo, $user_id);

                $sets = [];
                foreach ($targets as $f) {
                    $sets[] = "{$f} = NULL";
                }

                $sql = "UPDATE user_profiles SET " . implode(", ", $sets) . " WHERE user_id = ?";
                $pdo->prepare($sql)->execute([$user_id]);

                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }

            send_response(200, ["message" => "cleared"]);
            break;
        }

        /* ---------- ENCOUNTER SYNC ---------- */
    case "encounter_sync": {
            // すれ違い用IDと公開設定を同期
            $user = require_user_cookie($pdo);
            if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");

            $bluetooth_user_id = normalize_bluetooth_user_id($_POST["bluetooth_user_id"] ?? null);
            if ($bluetooth_user_id === null) {
                send_error(400, "bad_request", "bluetooth_user_id required", null, ["bluetooth_user_id" => "invalid"], "error.invalid_bluetooth_user_id");
            }

            $share = parse_bool_value($_POST["share_nickname"] ?? null);
            if ($share === null) {
                send_error(400, "bad_request", "share_nickname required", null, ["share_nickname" => "invalid"], "error.invalid_share_nickname");
            }

            $nickname = null;
            if (array_key_exists("nickname", $_POST)) {
                $n = $_POST["nickname"];
                if ($n === null || $n === "") {
                    $nickname = null;
                } elseif (!is_string($n)) {
                    send_error(422, "validation_failed", "Validation failed", null, ["nickname" => "invalid"], "error.validation_failed");
                } else {
                    $n = trim($n);
                    if (mb_strlen($n) > 20) {
                        send_error(422, "validation_failed", "Validation failed", null, ["nickname" => "too_long"], "error.validation_failed");
                    }
                    $nickname = $n;
                }
            }

            $visibility = $share ? "public" : "private";
            $user_id = (int)$user["id"];

            try {
                $pdo->beginTransaction();
                ensure_profile_row_exists($pdo, $user_id);

                $sql = "UPDATE user_profiles SET bluetooth_user_id = ?, encounter_visibility = ?";
                $params = [$bluetooth_user_id, $visibility];

                if ($nickname !== null) {
                    $sql .= ", nickname = ?";
                    $params[] = $nickname;
                }

                $sql .= " WHERE user_id = ?";
                $params[] = $user_id;
                $pdo->prepare($sql)->execute($params);

                $pdo->commit();

                $profile = fetch_profile($pdo, $user_id);
                send_response(200, [
                    "message" => "synced",
                    "bluetooth_user_id" => $profile["bluetooth_user_id"],
                    "encounter_visibility" => $profile["encounter_visibility"],
                    "share_nickname" => ($profile["encounter_visibility"] === "public"),
                    "nickname" => $profile["nickname"]
                ]);
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                if (($e->errorInfo[1] ?? null) === 1062) {
                    send_error(409, "conflict", "bluetooth_user_id already exists", null, ["bluetooth_user_id" => "duplicate"], "error.bluetooth_user_id_conflict");
                }
                send_error(500, "db_error", "Database error", $e->getMessage());
            } catch (Exception $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                send_error(500, "server_error", "Server error", $e->getMessage());
            }
            break;
        }

        /* ---------- ENCOUNTER LOOKUP ---------- */
    case "encounter_lookup": {
            // すれ違い用IDから表示名を解決（公開設定を尊重）
            $user = require_user_cookie($pdo);
            if (!$user) send_error(401, "unauthenticated", "Not logged in", null, null, "auth.required");

            $bluetooth_user_id = normalize_bluetooth_user_id($_POST["bluetooth_user_id"] ?? null);
            if ($bluetooth_user_id === null) {
                send_error(400, "bad_request", "bluetooth_user_id required", null, ["bluetooth_user_id" => "invalid"], "error.invalid_bluetooth_user_id");
            }

            $stmt = $pdo->prepare("
                SELECT
                    nickname,
                    encounter_visibility
                FROM user_profiles
                WHERE bluetooth_user_id = ?
                LIMIT 1
            ");
            $stmt->execute([$bluetooth_user_id]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!$row) {
                send_response(200, [
                    "found" => false,
                    "bluetooth_user_id" => $bluetooth_user_id,
                    "encounter_visibility" => "private",
                    "share_nickname" => false,
                    "nickname" => null,
                    "display_name" => "名無しの旅人"
                ]);
            }

            $visibility = $row["encounter_visibility"] ?? "public";
            $isPublic = ($visibility === "public");
            $nickname = null;

            if ($isPublic && isset($row["nickname"]) && is_string($row["nickname"]) && trim($row["nickname"]) !== "") {
                $nickname = trim($row["nickname"]);
            }

            send_response(200, [
                "found" => true,
                "bluetooth_user_id" => $bluetooth_user_id,
                "encounter_visibility" => $visibility,
                "share_nickname" => $isPublic,
                "nickname" => $nickname,
                "display_name" => $nickname ?? "名無しの旅人"
            ]);
            break;
        }

    default:
        send_error(400, "bad_request", "Unknown action", null, null, "error.unknown_action");
}