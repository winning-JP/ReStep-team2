<?php
header("Content-Type: application/json; charset=utf-8");

/* ============================
    HELPERS
============================ */
function send_response($status, $data)
{
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}

function request_json($url, $payload, &$cookieJar)
{
    $ch = curl_init($url);

    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        "Content-Type: application/json"
    ]);

    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload, JSON_UNESCAPED_UNICODE));

    // cookie保持
    curl_setopt($ch, CURLOPT_COOKIEJAR, $cookieJar);
    curl_setopt($ch, CURLOPT_COOKIEFILE, $cookieJar);

    $body = curl_exec($ch);
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);

    curl_close($ch);

    return [
        "status" => $status,
        "raw" => $body,
        "json" => json_decode($body, true)
    ];
}

function build_base_url($url)
{
    $parts = parse_url($url);
    if (!$parts || empty($parts["scheme"]) || empty($parts["host"])) {
        return null;
    }
    $path = $parts["path"] ?? "/";
    $dir = rtrim(dirname($path), "/");
    $base = $parts["scheme"] . "://" . $parts["host"];
    if (!empty($parts["port"])) {
        $base .= ":" . $parts["port"];
    }
    return $base . $dir;
}

function add_result(&$results, $name, $expected_status, $res, $expect_error_code = null)
{
    $passed = ($res["status"] === $expected_status);

    if ($expect_error_code !== null) {
        $actual_code = $res["json"]["error"]["code"] ?? null;
        if ($actual_code !== $expect_error_code) {
            $passed = false;
        }
    }

    $results[] = [
        "name" => $name,
        "passed" => $passed,
        "expected_status" => $expected_status,
        "actual_status" => $res["status"],
        "expected_error_code" => $expect_error_code,
        "actual_error_code" => $res["json"]["error"]["code"] ?? null,
        "response" => $res["json"] ?? $res["raw"]
    ];
}

function add_check(&$results, $name, $passed, $detail = [])
{
    $results[] = array_merge([
        "name" => $name,
        "passed" => $passed
    ], $detail);
}

/* ============================
    MAIN
============================ */
if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    send_response(405, ["error" => "Only POST allowed"]);
}

// リクエストJSONを読み込み、テスト対象のURLを取得
$raw = file_get_contents("php://input");
$input = json_decode($raw, true) ?: [];

// URL解決（後方互換: target_url を user_api とみなす）
$user_api_url = $input["user_api_url"] ?? ($input["target_url"] ?? null);
$base_url = $input["base_url"] ?? null;

if (!$base_url && $user_api_url) {
    $base_url = build_base_url($user_api_url);
}

$wallet_api_url  = $input["wallet_api_url"] ?? ($base_url ? rtrim($base_url, "/") . "/user_wallet_api.php" : null);
$profile_api_url = $input["profile_api_url"] ?? ($base_url ? rtrim($base_url, "/") . "/user_profile_api.php" : null);
$stats_api_url   = $input["stats_api_url"] ?? ($base_url ? rtrim($base_url, "/") . "/user_stats_api.php" : null);

if (!$user_api_url || !$wallet_api_url || !$profile_api_url || !$stats_api_url) {
    send_response(400, [
        "error" => "API URLs required",
        "required" => ["user_api_url", "wallet_api_url", "profile_api_url", "stats_api_url"],
        "provided" => [
            "user_api_url" => $user_api_url,
            "wallet_api_url" => $wallet_api_url,
            "profile_api_url" => $profile_api_url,
            "stats_api_url" => $stats_api_url
        ]
    ]);
}

// cookieファイル（テスト用）
$cookieJar = sys_get_temp_dir() . "/selftest_cookie_" . uniqid() . ".txt";

$results = [];

// テストユーザー作成
$login_id = "test_" . uniqid();
$email = $login_id . "@example.com";
$password = "TestPass123!";

/* ============================
    TEST START
============================ */

// 1) register success（新規登録が成功するか）
$res = request_json($user_api_url, [
    "action" => "register",
    "login_id" => $login_id,
    "email" => $email,
    "password" => $password
], $cookieJar);
add_result($results, "register success", 201, $res);

// 2) register duplicate（重複登録が弾かれるか）
$res = request_json($user_api_url, [
    "action" => "register",
    "login_id" => $login_id,
    "email" => $email,
    "password" => $password
], $cookieJar);
add_result($results, "register duplicate", 409, $res, "conflict");

// 3) login success（正しいID/パスでログインできるか）
$res = request_json($user_api_url, [
    "action" => "login",
    "identifier" => $login_id,
    "password" => $password
], $cookieJar);
add_result($results, "login success", 200, $res);

// 4) login wrong password（誤パスワードでエラーになるか）
$res = request_json($user_api_url, [
    "action" => "login",
    "identifier" => $login_id,
    "password" => "wrongpassword"
], $cookieJar);
add_result($results, "login wrong password", 401, $res, "auth_failed");

// 5) status logged in（ログイン状態が返るか）
$res = request_json($user_api_url, [
    "action" => "status"
], $cookieJar);
add_result($results, "status logged in", 200, $res);

// 6) devices logged in（端末一覧が取得できるか）
$res = request_json($user_api_url, [
    "action" => "devices"
], $cookieJar);
add_result($results, "devices logged in", 200, $res);

// devicesから token_id を取る（is_current=0 のやつ優先で消す）
$token_id = null;
if (!empty($res["json"]["devices"])) {
    foreach ($res["json"]["devices"] as $d) {
        if (($d["is_current"] ?? 0) == 0) {
            $token_id = $d["id"];
            break;
        }
    }
    if ($token_id === null) {
        $token_id = $res["json"]["devices"][0]["id"] ?? null;
    }
}

// 7) revoke_device missing token_id（必須パラメータ不足チェック）
$res = request_json($user_api_url, [
    "action" => "revoke_device"
], $cookieJar);
add_result($results, "revoke_device missing token_id", 400, $res, "bad_request");

// 8) revoke_device success（対象トークンを無効化）
if ($token_id) {
    $res = request_json($user_api_url, [
        "action" => "revoke_device",
        "token_id" => $token_id
    ], $cookieJar);
    add_result($results, "revoke_device success", 200, $res);
} else {
    $results[] = [
        "name" => "revoke_device success",
        "passed" => false,
        "error" => "token_id not found from devices response"
    ];
}

// 9) admin_users (should be forbidden)（一般ユーザーは拒否される）
$res = request_json($user_api_url, [
    "action" => "admin_users"
], $cookieJar);
add_result($results, "admin_users forbidden", 403, $res, "forbidden");

// 10) unknown action（未知アクションのハンドリング）
$res = request_json($user_api_url, [
    "action" => "unknown_action"
], $cookieJar);
add_result($results, "unknown action", 400, $res, "bad_request");

/* ============================
    WALLET API
============================ */
// ping
$res = request_json($wallet_api_url, [
    "action" => "ping"
], $cookieJar);
add_result($results, "wallet ping", 200, $res);

// coin_get（初期残高）
$res = request_json($wallet_api_url, [
    "action" => "coin_get"
], $cookieJar);
add_result($results, "wallet coin_get", 200, $res);
$balance = $res["json"]["balance"] ?? null;
add_check($results, "wallet coin_get has balance", is_numeric($balance), ["value" => $balance]);

// coin_earn
$res = request_json($wallet_api_url, [
    "action" => "coin_earn",
    "amount" => 10,
    "reason" => "self_test"
], $cookieJar);
add_result($results, "wallet coin_earn", 200, $res);
$balance_after_earn = $res["json"]["balance"] ?? null;
add_check($results, "wallet coin_earn balance updated", is_numeric($balance_after_earn), ["value" => $balance_after_earn]);

// coin_use
$res = request_json($wallet_api_url, [
    "action" => "coin_use",
    "amount" => 5,
    "reason" => "self_test"
], $cookieJar);
add_result($results, "wallet coin_use", 200, $res);
$balance_after_use = $res["json"]["balance"] ?? null;
add_check($results, "wallet coin_use balance updated", is_numeric($balance_after_use), ["value" => $balance_after_use]);

// coin_history
$res = request_json($wallet_api_url, [
    "action" => "coin_history",
    "limit" => 5
], $cookieJar);
add_result($results, "wallet coin_history", 200, $res);

// stamp_get
$res = request_json($wallet_api_url, [
    "action" => "stamp_get"
], $cookieJar);
add_result($results, "wallet stamp_get", 200, $res);

// stamp_add
$res = request_json($wallet_api_url, [
    "action" => "stamp_add",
    "amount" => 5,
    "reason" => "self_test"
], $cookieJar);
add_result($results, "wallet stamp_add", 200, $res);

// stamp_spend
$res = request_json($wallet_api_url, [
    "action" => "stamp_spend",
    "amount" => 3,
    "reason" => "self_test"
], $cookieJar);
add_result($results, "wallet stamp_spend", 200, $res);

// stamp_history
$res = request_json($wallet_api_url, [
    "action" => "stamp_history",
    "limit" => 5
], $cookieJar);
add_result($results, "wallet stamp_history", 200, $res);

// stamp_sync（当日獲得分を同期）
$res = request_json($wallet_api_url, [
    "action" => "stamp_sync",
    "date_key" => date("Y-m-d"),
    "current_earned" => 2
], $cookieJar);
add_result($results, "wallet stamp_sync", 200, $res);

// challenge_list
$res = request_json($wallet_api_url, [
    "action" => "challenge_list"
], $cookieJar);
add_result($results, "wallet challenge_list", 200, $res);

// challenge_status
$res = request_json($wallet_api_url, [
    "action" => "challenge_status"
], $cookieJar);
add_result($results, "wallet challenge_status", 200, $res);

// challenge_claim（月次スタート報酬）
$res = request_json($wallet_api_url, [
    "action" => "challenge_claim",
    "key" => "monthly_start",
    "year" => (int)date("Y"),
    "month" => (int)date("n")
], $cookieJar);
add_result($results, "wallet challenge_claim", 200, $res);

/* ============================
    PROFILE API
============================ */
// get_profile
$res = request_json($profile_api_url, [
    "action" => "get_profile"
], $cookieJar);
add_result($results, "profile get_profile", 200, $res);

// patch_profile
$res = request_json($profile_api_url, [
    "action" => "patch_profile",
    "profile" => [
        "nickname" => "selftest",
        "gender" => "その他"
    ]
], $cookieJar);
add_result($results, "profile patch_profile", 200, $res);

// get_profile after patch
$res = request_json($profile_api_url, [
    "action" => "get_profile"
], $cookieJar);
add_result($results, "profile get_profile after patch", 200, $res);
$nick = $res["json"]["profile"]["nickname"] ?? null;
add_check($results, "profile nickname updated", ($nick === "selftest"), ["value" => $nick]);

// encounter_sync
$btid = "selftest-" . bin2hex(random_bytes(8));
$res = request_json($profile_api_url, [
    "action" => "encounter_sync",
    "bluetooth_user_id" => $btid,
    "share_nickname" => true,
    "nickname" => "selftest"
], $cookieJar);
add_result($results, "profile encounter_sync", 200, $res);

// encounter_lookup
$res = request_json($profile_api_url, [
    "action" => "encounter_lookup",
    "bluetooth_user_id" => $btid
], $cookieJar);
add_result($results, "profile encounter_lookup", 200, $res);
$display = $res["json"]["display_name"] ?? null;
add_check($results, "profile encounter_lookup display_name", ($display === "selftest"), ["value" => $display]);

// clear_profile_fields
$res = request_json($profile_api_url, [
    "action" => "clear_profile_fields",
    "fields" => ["nickname"]
], $cookieJar);
add_result($results, "profile clear_profile_fields", 200, $res);

/* ============================
    STATS API
============================ */
$today = date("Y/m/d");

// seed_continuity
$res = request_json($stats_api_url, [
    "action" => "seed_continuity",
    "current_streak" => 1,
    "longest_streak" => 1,
    "last_active_date" => $today
], $cookieJar);
add_result($results, "stats seed_continuity", 200, $res);

// record_continuity
$res = request_json($stats_api_url, [
    "action" => "record_continuity",
    "date" => $today
], $cookieJar);
add_result($results, "stats record_continuity", 200, $res);

// get_continuity
$res = request_json($stats_api_url, [
    "action" => "get_continuity"
], $cookieJar);
add_result($results, "stats get_continuity", 200, $res);

// save_daily
$res = request_json($stats_api_url, [
    "action" => "save_daily",
    "date" => $today,
    "steps" => 1234,
    "calories" => 321,
    "distance_km" => 1.23
], $cookieJar);
add_result($results, "stats save_daily", 200, $res);

// get_daily
$res = request_json($stats_api_url, [
    "action" => "get_daily",
    "date" => $today
], $cookieJar);
add_result($results, "stats get_daily", 200, $res);

// get_range
$res = request_json($stats_api_url, [
    "action" => "get_range",
    "from" => $today,
    "to" => $today
], $cookieJar);
add_result($results, "stats get_range", 200, $res);

// get_weekly_summary
$res = request_json($stats_api_url, [
    "action" => "get_weekly_summary",
    "date" => $today
], $cookieJar);
add_result($results, "stats get_weekly_summary", 200, $res);

// get_monthly_summary
$res = request_json($stats_api_url, [
    "action" => "get_monthly_summary",
    "year" => (int)date("Y"),
    "month" => (int)date("n")
], $cookieJar);
add_result($results, "stats get_monthly_summary", 200, $res);

// 11) logout（ログアウト処理）
$res = request_json($user_api_url, [
    "action" => "logout"
], $cookieJar);
add_result($results, "logout", 200, $res);

// 12) devices after logout -> unauthenticated（ログアウト後の認証確認）
$res = request_json($user_api_url, [
    "action" => "devices"
], $cookieJar);
add_result($results, "devices after logout", 401, $res, "unauthenticated");

/* ============================
    CLEANUP (DELETE TEST USER)
============================ */

// close_account を実行するために login し直す
$res = request_json($user_api_url, [
    "action" => "login",
    "identifier" => $login_id,
    "password" => $password
], $cookieJar);
add_result($results, "login for close_account", 200, $res);

// close_account (cleanup)
$res = request_json($user_api_url, [
    "action" => "close_account",
    "password" => $password
], $cookieJar);
add_result($results, "close_account cleanup", 200, $res);

// status after close_account
$res = request_json($user_api_url, [
    "action" => "status"
], $cookieJar);

$logged_in = $res["json"]["logged_in"] ?? null;

$results[] = [
    "name" => "status after close_account",
    "passed" => ($res["status"] === 200 && $logged_in === false),
    "expected_status" => 200,
    "actual_status" => $res["status"],
    "expected_logged_in" => false,
    "actual_logged_in" => $logged_in,
    "response" => $res["json"] ?? $res["raw"]
];

/* ============================
    FINISH
============================ */

// cookieファイル削除
@unlink($cookieJar);

// 全体判定
$ok = true;
foreach ($results as $r) {
    if (!($r["passed"] ?? false)) {
        $ok = false;
        break;
    }
}

send_response(200, [
    "ok" => $ok,
    "urls" => [
        "user_api_url" => $user_api_url,
        "wallet_api_url" => $wallet_api_url,
        "profile_api_url" => $profile_api_url,
        "stats_api_url" => $stats_api_url
    ],
    "tested_at" => date("Y-m-d H:i:s"),
    "test_user" => [
        "login_id" => $login_id,
        "email" => $email
    ],
    "results" => $results
]);
