import Foundation
import UIKit

struct APIConfig {
    private static let defaultBaseURLString = "https://restep-api.winning.moe"
    private static let runtimeBaseKey = "restep.api.base_url"
    private static let runtimeUserKey = "restep.api.user_endpoint"
    private static let runtimeProfileKey = "restep.api.profile_endpoint"
    private static let runtimeStatsKey = "restep.api.stats_endpoint"
    private static let runtimeWalletKey = "restep.api.wallet_endpoint"
    private static let runtimeFogMapKey = "restep.api.fogmap_endpoint"
    private static let runtimeArticleKey = "restep.api.article_endpoint"
    private static let runtimeTreasureKey = "restep.api.treasure_endpoint"
    private static let runtimeUploadKey = "restep.api.upload_endpoint"

    /// Runtime override for the base URL.
    /// Example: https://staging.example.com
    static var runtimeBaseURL: URL? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: runtimeBaseKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                return nil
            }
            return URL(string: raw)
        }
        set {
            let defaults = UserDefaults.standard
            if let value = newValue?.absoluteString, !value.isEmpty {
                defaults.set(value, forKey: runtimeBaseKey)
            } else {
                defaults.removeObject(forKey: runtimeBaseKey)
            }
        }
    }

    static var apiURL: URL {
        resolveEndpoint(
            runtimeKey: runtimeUserKey,
            infoKey: "API_ENDPOINT",
            defaultPath: "user_api.php"
        )
    }

    static var profileAPIURL: URL {
        resolveEndpoint(
            runtimeKey: runtimeProfileKey,
            infoKey: "PROFILE_API_ENDPOINT",
            defaultPath: "user_profile_api.php"
        )
    }

    static var statsAPIURL: URL {
        resolveEndpoint(
            runtimeKey: runtimeStatsKey,
            infoKey: "STATS_API_ENDPOINT",
            defaultPath: "user_stats_api.php"
        )
    }

    static var walletAPIURL: URL {
        resolveEndpoint(
            runtimeKey: runtimeWalletKey,
            infoKey: "WALLET_API_ENDPOINT",
            defaultPath: "user_wallet_api.php"
        )
    }

    static var fogMapAPIURL: URL {
        resolveEndpoint(
            runtimeKey: runtimeFogMapKey,
            infoKey: "FOGMAP_API_ENDPOINT",
            defaultPath: "fog_map_api.php"
        )
    }

    static var articleAPIURL: URL {
        resolveEndpoint(
            runtimeKey: runtimeArticleKey,
            infoKey: "ARTICLE_API_ENDPOINT",
            defaultPath: "article_api.php"
        )
    }

    static var treasureAPIURL: URL {
        resolveEndpoint(
            runtimeKey: runtimeTreasureKey,
            infoKey: "TREASURE_API_ENDPOINT",
            defaultPath: "treasure_api.php"
        )
    }

    static var uploadAPIURL: URL {
        resolveEndpoint(
            runtimeKey: runtimeUploadKey,
            infoKey: "UPLOAD_API_ENDPOINT",
            defaultPath: "upload_api.php"
        )
    }

    private static var resolvedBaseURL: URL {
        if let runtime = runtimeBaseURL {
            return normalizedBaseURL(runtime)
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: raw) {
            return normalizedBaseURL(url)
        }
        // Legacy fallback: API_ENDPOINT contains full user_api URL in old builds.
        if let raw = Bundle.main.object(forInfoDictionaryKey: "API_ENDPOINT") as? String,
           let url = URL(string: raw) {
            return normalizedBaseURL(url.deletingLastPathComponent())
        }
        return normalizedBaseURL(URL(string: defaultBaseURLString)!)
    }

    private static func resolveEndpoint(runtimeKey: String, infoKey: String, defaultPath: String) -> URL {
        if let raw = UserDefaults.standard.string(forKey: runtimeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }

        if let raw = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
           let url = URL(string: raw) {
            return url
        }

        return resolvedBaseURL.appendingPathComponent(defaultPath)
    }

    private static func normalizedBaseURL(_ url: URL) -> URL {
        let string = url.absoluteString.hasSuffix("/") ? String(url.absoluteString.dropLast()) : url.absoluteString
        return URL(string: string) ?? url
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case unexpectedStatus(Int)
    case server(code: String?, message: String, detail: String?, fields: [String: String]?, i18nKey: String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "サーバーからの応答が不正です。"
        case .unexpectedStatus(let code):
            return "サーバーエラーが発生しました。(\(code))"
        case .server(_, let message, let detail, _, _):
            if let d = detail { return d }
            return message
        case .decoding:
            return "サーバー応答の解析に失敗しました。"
        }
    }
}

extension APIError {
    /// Returns a user-facing Japanese message for this error when available.
    func userMessage() -> String {
        switch self {
        case .server(_, let message, let detail, _, _):
            if let d = detail { return d }
            return message
        case .invalidResponse:
            return "サーバーからの応答が不正です。"
        case .unexpectedStatus(let code):
            return "サーバーエラーが発生しました。(" + String(code) + ")"
        case .decoding:
            return "サーバー応答の解析に失敗しました。"
        }
    }

    /// Returns localized field errors if available.
    func localizedFieldErrors() -> [String: String]? {
        switch self {
        case .server(_, _, _, let fields, _):
            return fields
        default:
            return nil
        }
    }
}

struct UserProfile: Codable {
    let loginId: String
    let email: String
    let isAdmin: Int?
    let createdAt: String?
}

struct LoginResponse: Codable {
    let message: String
    let user: UserProfile
}

struct RegisterResponse: Codable {
    let message: String
    let user: UserProfile
}

struct StatusResponse: Codable {
    let loggedIn: Bool?
    let user: UserProfile?
}

struct DeviceInfoResponse: Codable {
    let id: Int
    let createdAt: String
    let expiresAt: String
    let revokedAt: String?
}

struct DevicesResponse: Codable {
    let devices: [DeviceInfoResponse]
}

struct CoinBalanceResponse: Codable {
    let userId: Int
    let balance: Int
}

struct CoinUseResponse: Codable {
    let message: String
    let userId: Int
    let used: Int
    let balance: Int
    let transactionId: Int
    let idempotent: Bool
}

struct CoinEarnResponse: Codable {
    let message: String
    let userId: Int
    let added: Int
    let balance: Int
    let transactionId: Int
    let idempotent: Bool
}

struct StampBalanceResponse: Codable {
    let userId: Int
    let balance: Int
    let totalEarned: Int
}

struct StampSyncResponse: Codable {
    let userId: Int
    let balance: Int
    let earnedToday: Int
    let added: Int
}

struct StampSpendResponse: Codable {
    let message: String
    let userId: Int
    let used: Int
    let balance: Int
    let transactionId: Int
    let idempotent: Bool
}

struct StampAddResponse: Codable {
    let message: String
    let userId: Int
    let added: Int
    let balance: Int
    let transactionId: Int
    let idempotent: Bool
}

struct StampHistoryItem: Codable, Identifiable {
    let id: Int
    let delta: Int
    let type: String
    let reason: String?
    let balanceAfter: Int
    let createdAt: String
}

struct StampHistoryResponse: Codable {
    let userId: Int
    let balance: Int
    let items: [StampHistoryItem]
    let nextBeforeId: Int?
}

struct ChallengeUnlocks: Codable {
    let battle: Bool
    let poker: Bool
    let slot: Bool
}

struct ChallengeStatusResponse: Codable {
    let periodKey: String
    let claimedMonthly: [String]
    let claimedCumulative: [String]
    let unlocks: ChallengeUnlocks
}

struct ChallengeListItem: Codable, Identifiable {
    let key: String
    let mode: String
    let requiredSteps: Int
    let title: String
    let subtitle: String
    let rewardType: String
    let rewardValue: String?

    var id: String { key }
}

struct ChallengeListResponse: Codable {
    let monthly: [ChallengeListItem]
    let cumulative: [ChallengeListItem]
}

struct ChallengeClaimResponse: Codable {
    let message: String
    let key: String
    let periodKey: String
    let rewardType: String
    let balance: Int?
    let idempotent: Bool
    let unlocks: ChallengeUnlocks?
}

// MARK: - Coin Daily Usage

struct CoinDailyUsageResponse: Codable {
    let userId: Int
    let dateKey: String
    let used: Int
    let dailyLimit: Int
    let remaining: Int
}

struct CoinUseDailyResponse: Codable {
    let message: String
    let userId: Int
    let used: Int
    let balance: Int
    let dailyUsed: Int
    let dailyLimit: Int
    let dailyRemaining: Int
    let transactionId: Int
    let idempotent: Bool
}

// MARK: - Gold Stamp

struct GoldStampBalanceResponse: Codable {
    let userId: Int
    let balance: Int
    let totalEarned: Int
}

struct GoldStampExchangeResponse: Codable {
    let message: String
    let userId: Int
    let coinBalance: Int
    let coinUsed: Int
    let goldStampBalance: Int
    let goldStampTotalEarned: Int
}

struct GoldStampUseResponse: Codable {
    let message: String
    let userId: Int
    let useType: String
    let goldStampsUsed: Int
    let goldStampBalance: Int
    let coinLimitAdded: Int
    let dailyLimit: Int
    let dailyUsed: Int
}

// MARK: - Fog Map

struct FogVisitSyncResponse: Codable {
    let message: String
    let userId: Int
    let inserted: Int
}

struct FogVisitItem: Codable, Identifiable {
    let id: Int
    let latitude: Double
    let longitude: Double
    let visitedAt: String
}

struct FogVisitListResponse: Codable {
    let userId: Int
    let items: [FogVisitItem]
    let nextAfterId: Int?
}

struct WaypointAddResponse: Codable {
    let message: String
    let waypointId: Int
    let userId: Int
}

struct WaypointItem: Codable, Identifiable {
    let id: Int
    let latitude: Double
    let longitude: Double
    let title: String?
    let note: String?
    let photoUrl: String?
    let createdAt: String
}

struct WaypointListResponse: Codable {
    let userId: Int
    let items: [WaypointItem]
}

struct WaypointUpdateResponse: Codable {
    let message: String
    let waypointId: Int
    let userId: Int
    let title: String?
    let note: String?
    let photoUrl: String?
}

struct WaypointDeleteResponse: Codable {
    let message: String
    let deleted: Bool
    let waypointId: Int
}

struct ImageUploadResponse: Codable {
    let message: String
    let url: String
    let key: String
    let userId: Int
    let size: Int
    let contentType: String
}

// MARK: - Article

struct ArticlePostResponse: Codable {
    let message: String
    let articleId: Int
    let coinBalance: Int
    let coinUsed: Int
}

struct ArticleItem: Codable, Identifiable {
    let id: Int
    let userId: Int
    let nickname: String
    let title: String
    let body: String
    let imageUrl: String?
    let viewCount: Int
    let reactionCount: Int
    let createdAt: String
}

struct ArticleListResponse: Codable {
    let items: [ArticleItem]
    let total: Int
    let sort: String
    let limit: Int
    let offset: Int
}

struct ArticleDetailResponse: Codable {
    let id: Int
    let userId: Int
    let nickname: String
    let title: String
    let body: String
    let imageUrl: String?
    let viewCount: Int
    let reactionCount: Int
    let createdAt: String
    let userReactions: [String]
}

struct ArticleReactResponse: Codable {
    let message: String
    let articleId: Int
    let type: String
    let added: Bool
    let reactionCount: Int
}

struct ArticleRankingItem: Codable, Identifiable {
    let rank: Int
    let id: Int
    let userId: Int
    let nickname: String
    let title: String
    let viewCount: Int
    let reactionCount: Int
    let createdAt: String
}

struct ArticleRankingResponse: Codable {
    let rankBy: String
    let items: [ArticleRankingItem]
}

// MARK: - Treasure / Puzzle

struct TreasureOpenResponse: Codable {
    let message: String
    let userId: Int
    let rewardType: String
    let rewardValue: Int
    let collectedPieces: [Int]?
    let totalPieces: Int?
    let isComplete: Bool?
    let coinBalance: Int?
    let actualPenalty: Int?
    let expGained: Int?
    let note: String?
}

struct PuzzlePieceItem: Codable {
    let pieceIndex: Int
    let obtainedAt: String
}

struct PuzzleStatusResponse: Codable {
    let userId: Int
    let puzzleId: Int
    let pieces: [PuzzlePieceItem]
    let collected: Int
    let total: Int
    let isComplete: Bool
}

struct PuzzleCompleteResponse: Codable {
    let message: String
    let userId: Int
    let puzzleId: Int
    let rewardCoins: Int
    let coinBalance: Int
}

struct CoinRegisterResponse: Codable {
    let userId: Int
    let balance: Int
    let registered: Bool
    let transactionId: Int?
}

struct AdminUser: Codable {
    let id: Int?
    let loginId: String?
    let email: String?
    let isAdmin: Int?
}

struct AdminUsersResponse: Codable {
    let users: [AdminUser]
}

struct MessageResponse: Codable {
    let message: String
}

struct ContinuityResponse: Codable {
    let currentStreak: Int
    let longestStreak: Int
    let lastActiveDate: String?
    let updatedAt: String?
    let idempotent: Bool?
}

struct DailyStatsResponse: Codable {
    let date: String
    let steps: Int
    let calories: Int
    let distanceKm: Double
    let updatedAt: String?
}

struct UserProfileDetails: Codable {
    var nickname: String?
    var birthday: String?
    var gender: String?
    var heightCm: Double?
    var weightKg: Double?
    var weeklySteps: Int?
    var bodyFat: Int?
    var weeklyExercise: Int?
    var goalSteps: Int?
    var goalCalories: Int?
    var goalDistanceKm: Double?
    var updatedAt: String?
}

struct UserProfileResponse: Codable {
    let profile: UserProfileDetails
}

struct EncounterProfileSyncResponse: Codable {
    let message: String
    let bluetoothUserId: String?
    let encounterVisibility: String?
    let shareNickname: Bool?
    let nickname: String?
}

struct EncounterProfileLookupResponse: Codable {
    let found: Bool
    let bluetoothUserId: String?
    let encounterVisibility: String?
    let shareNickname: Bool
    let nickname: String?
    let displayName: String
}

private struct APIErrorBody: Codable {
    let code: String?
    let message: String
    let detail: String?
    let fields: [String: String]?
    let i18nKey: String?

    private enum CodingKeys: String, CodingKey {
        case code, message, detail, fields, i18nKey = "i18n_key"
    }
}

private struct APIErrorResponse: Codable {
    let error: APIErrorBody
}

private enum UserAction: String, Codable {
    case register
    case login
    case status
    case devices
    case logout
    case logoutAll = "logout_all"
    case updateProfile = "update_profile"
    case adminUsers = "admin_users"
    case adminForceLogout = "admin_force_logout"
}

private enum StatsAction: String, Codable {
    case saveDaily = "save_daily"
    case recordContinuity = "record_continuity"
    case getContinuity = "get_continuity"
    case seedContinuity = "seed_continuity"
    case getDaily = "get_daily"
}

private enum ProfileAction: String, Codable {
    case getProfile = "get_profile"
    case updateProfile = "update_profile"
    case patchProfile = "patch_profile"
    case clearProfileFields = "clear_profile_fields"
    case encounterSync = "encounter_sync"
    case encounterLookup = "encounter_lookup"
}

private enum WalletAction: String, Codable {
    case coinGet = "coin_get"
    case coinUse = "coin_use"
    case coinHistory = "coin_history"
    case coinAdd = "coin_add"
    case coinRegister = "coin_register"
    case coinEarn = "coin_earn"
    case coinDailyUsage = "coin_daily_usage"
    case coinUseDaily = "coin_use_daily"
    case goldStampGet = "gold_stamp_get"
    case goldStampExchange = "gold_stamp_exchange"
    case goldStampUse = "gold_stamp_use"
    case challengeList = "challenge_list"
    case challengeStatus = "challenge_status"
    case challengeClaim = "challenge_claim"
    case stampGet = "stamp_get"
    case stampSync = "stamp_sync"
    case stampSpend = "stamp_spend"
    case stampAdd = "stamp_add"
    case stampHistory = "stamp_history"
}

private enum FogMapAction: String, Codable {
    case visitSync = "visit_sync"
    case visitList = "visit_list"
    case waypointAdd = "waypoint_add"
    case waypointList = "waypoint_list"
    case waypointUpdate = "waypoint_update"
    case waypointDelete = "waypoint_delete"
}

private enum ArticleAction: String, Codable {
    case post
    case list
    case detail
    case react
    case ranking
}

private enum TreasureAction: String, Codable {
    case openBox = "open_box"
    case puzzleStatus = "puzzle_status"
    case puzzleComplete = "puzzle_complete"
}

private struct RegisterRequest: Encodable {
    let action: UserAction = .register
    let loginId: String
    let email: String
    let password: String
}

private struct LoginRequest: Encodable {
    let action: UserAction = .login
    let identifier: String
    let password: String
    let deviceName: String?
}

private struct StatusRequest: Encodable {
    let action: UserAction = .status
}

private struct SimpleActionRequest: Encodable {
    let action: UserAction
}

private struct AdminForceLogoutRequest: Encodable {
    let action: UserAction = .adminForceLogout
    let userId: Int
}

private struct UpdateProfileRequest: Encodable {
    let action: UserAction = .updateProfile
    let loginId: String?
    let email: String?
    let password: String?
}

private struct ProfileRequest<T: Encodable>: Encodable {
    let action: ProfileAction
    let profile: T?
    let fields: [String]?

    init(action: ProfileAction, profile: T? = nil, fields: [String]? = nil) {
        self.action = action
        self.profile = profile
        self.fields = fields
    }
}

private struct EncounterSyncRequest: Encodable {
    let action: ProfileAction = .encounterSync
    let bluetoothUserId: String
    let shareNickname: Bool
    let nickname: String?
}

private struct EncounterLookupRequest: Encodable {
    let action: ProfileAction = .encounterLookup
    let bluetoothUserId: String
}

private struct DailyStatsRequest: Encodable {
    let action: StatsAction = .saveDaily
    let date: String
    let steps: Int
    let calories: Int
    let distanceKm: Double
}

private struct DailyStatsGetRequest: Encodable {
    let action: StatsAction = .getDaily
    let date: String
}

private struct ContinuityRecordRequest: Encodable {
    let action: StatsAction = .recordContinuity
    let date: String?
}

private struct ContinuityGetRequest: Encodable {
    let action: StatsAction = .getContinuity
}

private struct ContinuitySeedRequest: Encodable {
    let action: StatsAction = .seedContinuity
    let currentStreak: Int
    let longestStreak: Int
    let lastActiveDate: String?
}

private struct CoinGetRequest: Encodable {
    let action: WalletAction = .coinGet
}

private struct CoinUseRequest: Encodable {
    let action: WalletAction = .coinUse
    let amount: Int
    let reason: String?
    let clientRequestId: String?
}

private struct CoinRegisterRequest: Encodable {
    let action: WalletAction = .coinRegister
    let balance: Int
}

private struct CoinEarnRequest: Encodable {
    let action: WalletAction = .coinEarn
    let amount: Int
    let reason: String?
    let clientRequestId: String?
}

private struct StampGetRequest: Encodable {
    let action: WalletAction = .stampGet
}

private struct StampSyncRequest: Encodable {
    let action: WalletAction = .stampSync
    let dateKey: String
    let currentEarned: Int
    let clientRequestId: String?
}

private struct StampSpendRequest: Encodable {
    let action: WalletAction = .stampSpend
    let amount: Int
    let reason: String?
    let clientRequestId: String?
}

private struct StampAddRequest: Encodable {
    let action: WalletAction = .stampAdd
    let amount: Int
    let reason: String?
    let clientRequestId: String?
}

private struct ChallengeStatusRequest: Encodable {
    let action: WalletAction = .challengeStatus
    let year: Int?
    let month: Int?
}

private struct ChallengeListRequest: Encodable {
    let action: WalletAction = .challengeList
}

private struct ChallengeClaimRequest: Encodable {
    let action: WalletAction = .challengeClaim
    let key: String
    let year: Int?
    let month: Int?
    let clientRequestId: String?
}

// MARK: - Coin Daily Usage Requests

private struct CoinDailyUsageRequest: Encodable {
    let action: WalletAction = .coinDailyUsage
}

private struct CoinUseDailyRequest: Encodable {
    let action: WalletAction = .coinUseDaily
    let amount: Int
    let reason: String?
    let clientRequestId: String?
}

// MARK: - Gold Stamp Requests

private struct GoldStampGetRequest: Encodable {
    let action: WalletAction = .goldStampGet
}

private struct GoldStampExchangeRequest: Encodable {
    let action: WalletAction = .goldStampExchange
    let clientRequestId: String?
}

private struct GoldStampUseRequest: Encodable {
    let action: WalletAction = .goldStampUse
    let amount: Int
    let useType: String
    let clientRequestId: String?
}

// MARK: - Fog Map Requests

private struct FogVisitSyncRequest: Encodable {
    let action: FogMapAction = .visitSync
    let visits: [[String: String]]
}

private struct FogVisitListRequest: Encodable {
    let action: FogMapAction = .visitList
    let limit: Int?
    let afterId: Int?
}

private struct WaypointAddRequest: Encodable {
    let action: FogMapAction = .waypointAdd
    let latitude: Double
    let longitude: Double
    let title: String?
    let note: String?
    let photoUrl: String?
}

private struct WaypointListRequest: Encodable {
    let action: FogMapAction = .waypointList
}

private struct WaypointUpdateRequest: Encodable {
    let action: FogMapAction = .waypointUpdate
    let waypointId: Int
    let title: String?
    let note: String?
    let photoUrl: String?
}

private struct WaypointDeleteRequest: Encodable {
    let action: FogMapAction = .waypointDelete
    let waypointId: Int
}

// MARK: - Article Requests

private struct ArticlePostRequest: Encodable {
    let action: ArticleAction = .post
    let title: String
    let body: String
    let imageUrl: String?
}

private struct ArticleListRequest: Encodable {
    let action: ArticleAction = .list
    let sort: String
    let limit: Int
    let offset: Int
}

private struct ArticleDetailRequest: Encodable {
    let action: ArticleAction = .detail
    let articleId: Int
}

private struct ArticleReactRequest: Encodable {
    let action: ArticleAction = .react
    let articleId: Int
    let type: String
}

private struct ArticleRankingRequest: Encodable {
    let action: ArticleAction = .ranking
    let rankBy: String
    let limit: Int
}

// MARK: - Treasure Requests

private struct TreasureOpenRequest: Encodable {
    let action: TreasureAction = .openBox
    let puzzleId: Int
}

private struct PuzzleStatusRequest: Encodable {
    let action: TreasureAction = .puzzleStatus
    let puzzleId: Int
}

private struct PuzzleCompleteRequest: Encodable {
    let action: TreasureAction = .puzzleComplete
    let puzzleId: Int
}

final class UserAPIClient {
    static let shared = UserAPIClient()

    private let session: URLSession
    private let fixedAPIURL: URL?
    private let fixedProfileAPIURL: URL?
    private let fixedStatsAPIURL: URL?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var apiURL: URL { fixedAPIURL ?? APIConfig.apiURL }
    private var profileAPIURL: URL { fixedProfileAPIURL ?? APIConfig.profileAPIURL }
    private var statsAPIURL: URL { fixedStatsAPIURL ?? APIConfig.statsAPIURL }

    init(
        session: URLSession = .shared,
        apiURL: URL? = nil,
        profileAPIURL: URL? = nil,
        statsAPIURL: URL? = nil
    ) {
        self.session = session
        self.fixedAPIURL = apiURL
        self.fixedProfileAPIURL = profileAPIURL
        self.fixedStatsAPIURL = statsAPIURL
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }


    func register(loginId: String, email: String, password: String) async throws -> RegisterResponse {
        let request = RegisterRequest(loginId: loginId, email: email, password: password)
        return try await post(request)
    }

    func login(identifier: String, password: String) async throws -> LoginResponse {
        let deviceName = UIDevice.current.name
        let request = LoginRequest(identifier: identifier, password: password, deviceName: deviceName)
        return try await post(request)
    }

    func status() async throws -> StatusResponse {
        let request = StatusRequest()
        return try await post(request)
    }

    func devices() async throws -> DevicesResponse {
        let request = SimpleActionRequest(action: .devices)
        return try await post(request)
    }

    func logout() async throws -> MessageResponse {
        let request = SimpleActionRequest(action: .logout)
        return try await post(request)
    }

    func logoutAll() async throws -> MessageResponse {
        let request = SimpleActionRequest(action: .logoutAll)
        return try await post(request)
    }

    func adminUsers() async throws -> AdminUsersResponse {
        let request = SimpleActionRequest(action: .adminUsers)
        return try await post(request)
    }

    func adminForceLogout(userId: Int) async throws -> MessageResponse {
        let request = AdminForceLogoutRequest(userId: userId)
        return try await post(request)
    }

    func updateProfile(loginId: String?, email: String?, password: String?) async throws -> MessageResponse {
        let request = UpdateProfileRequest(loginId: loginId, email: email, password: password)
        return try await post(request)
    }

    func fetchUserProfile() async throws -> UserProfileResponse {
        let request = ProfileRequest<UserProfileDetails>(action: .getProfile)
        return try await postProfile(request)
    }

    func updateUserProfile(_ profile: UserProfileDetails) async throws -> MessageResponse {
        let request = ProfileRequest(action: .patchProfile, profile: profile)
        return try await postProfile(request)
    }

    func clearUserProfileFields(_ fields: [String]) async throws -> MessageResponse {
        let request = ProfileRequest<UserProfileDetails>(action: .clearProfileFields, fields: fields)
        return try await postProfile(request)
    }

    func syncEncounterProfile(bluetoothUserId: String, shareNickname: Bool, nickname: String?) async throws -> EncounterProfileSyncResponse {
        let request = EncounterSyncRequest(
            bluetoothUserId: bluetoothUserId,
            shareNickname: shareNickname,
            nickname: nickname
        )
        return try await postProfile(request)
    }

    func lookupEncounterProfile(bluetoothUserId: String) async throws -> EncounterProfileLookupResponse {
        let request = EncounterLookupRequest(bluetoothUserId: bluetoothUserId)
        return try await postProfile(request)
    }

    func saveDailyStats(date: String, steps: Int, calories: Int, distanceKm: Double) async throws -> MessageResponse {
        let request = DailyStatsRequest(date: date, steps: steps, calories: calories, distanceKm: distanceKm)
        return try await postStats(request)
    }

    func fetchDailyStats(date: String) async throws -> DailyStatsResponse {
        let request = DailyStatsGetRequest(date: date)
        return try await postStats(request)
    }

    func recordContinuity(date: String? = nil) async throws -> ContinuityResponse {
        let request = ContinuityRecordRequest(date: date)
        return try await postStats(request)
    }

    func seedContinuity(currentStreak: Int, longestStreak: Int, lastActiveDate: String?) async throws -> ContinuityResponse {
        let request = ContinuitySeedRequest(currentStreak: currentStreak, longestStreak: longestStreak, lastActiveDate: lastActiveDate)
        return try await postStats(request)
    }

    func fetchContinuity() async throws -> ContinuityResponse {
        let request = ContinuityGetRequest()
        return try await postStats(request)
    }

    private func post<Request: Encodable, Response: Decodable>(_ body: Request) async throws -> Response {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)


        if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
            let e = apiError.error
            throw APIError.server(code: e.code, message: e.message, detail: e.detail, fields: e.fields, i18nKey: e.i18nKey)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.unexpectedStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func postProfile<Request: Encodable, Response: Decodable>(_ body: Request) async throws -> Response {
        var request = URLRequest(url: profileAPIURL)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
            let e = apiError.error
            throw APIError.server(code: e.code, message: e.message, detail: e.detail, fields: e.fields, i18nKey: e.i18nKey)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.unexpectedStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func postStats<Request: Encodable, Response: Decodable>(_ body: Request) async throws -> Response {
        var request = URLRequest(url: statsAPIURL)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
            let e = apiError.error
            throw APIError.server(code: e.code, message: e.message, detail: e.detail, fields: e.fields, i18nKey: e.i18nKey)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.unexpectedStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}

final class WalletAPIClient {
    static let shared = WalletAPIClient()

    private let session: URLSession
    private let fixedWalletAPIURL: URL?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var walletAPIURL: URL { fixedWalletAPIURL ?? APIConfig.walletAPIURL }

    init(session: URLSession = .shared, apiURL: URL? = nil) {
        self.session = session
        self.fixedWalletAPIURL = apiURL
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func fetchBalance() async throws -> CoinBalanceResponse {
        DebugLog.log("wallet.coin_get -> request")
        let request = CoinGetRequest()
        let response: CoinBalanceResponse = try await postWallet(request)
        DebugLog.log("wallet.coin_get -> balance=\(response.balance)")
        return response
    }

    func useCoins(amount: Int, reason: String?, clientRequestId: String?) async throws -> CoinUseResponse {
        DebugLog.log("wallet.coin_use -> amount=\(amount) reason=\(reason ?? "-")")
        let request = CoinUseRequest(amount: amount, reason: reason, clientRequestId: clientRequestId)
        let response: CoinUseResponse = try await postWallet(request)
        DebugLog.log("wallet.coin_use -> balance=\(response.balance) idempotent=\(response.idempotent)")
        return response
    }

    func registerWallet(initialBalance: Int) async throws -> CoinRegisterResponse {
        DebugLog.log("wallet.coin_register -> initialBalance=\(initialBalance)")
        let request = CoinRegisterRequest(balance: max(0, initialBalance))
        let response: CoinRegisterResponse = try await postWallet(request)
        DebugLog.log("wallet.coin_register -> balance=\(response.balance) registered=\(response.registered)")
        return response
    }

    func earnCoins(amount: Int, reason: String?, clientRequestId: String?) async throws -> CoinEarnResponse {
        DebugLog.log("wallet.coin_earn -> amount=\(amount) reason=\(reason ?? "-")")
        let request = CoinEarnRequest(amount: amount, reason: reason, clientRequestId: clientRequestId)
        let response: CoinEarnResponse = try await postWallet(request)
        DebugLog.log("wallet.coin_earn -> balance=\(response.balance) idempotent=\(response.idempotent)")
        return response
    }

    func fetchStampBalance() async throws -> StampBalanceResponse {
        DebugLog.log("wallet.stamp_get -> request")
        let request = StampGetRequest()
        let response: StampBalanceResponse = try await postWallet(request)
        DebugLog.log("wallet.stamp_get -> balance=\(response.balance) total=\(response.totalEarned)")
        return response
    }

    func syncStamps(dateKey: String, currentEarned: Int, clientRequestId: String?) async throws -> StampSyncResponse {
        DebugLog.log("wallet.stamp_sync -> date=\(dateKey) earned=\(currentEarned)")
        let request = StampSyncRequest(dateKey: dateKey, currentEarned: currentEarned, clientRequestId: clientRequestId)
        let response: StampSyncResponse = try await postWallet(request)
        DebugLog.log("wallet.stamp_sync -> balance=\(response.balance) added=\(response.added)")
        return response
    }

    func spendStamps(amount: Int, reason: String?, clientRequestId: String?) async throws -> StampSpendResponse {
        DebugLog.log("wallet.stamp_spend -> amount=\(amount) reason=\(reason ?? "-")")
        let request = StampSpendRequest(amount: amount, reason: reason, clientRequestId: clientRequestId)
        let response: StampSpendResponse = try await postWallet(request)
        DebugLog.log("wallet.stamp_spend -> balance=\(response.balance) idempotent=\(response.idempotent)")
        return response
    }

    func addStamps(amount: Int, reason: String?, clientRequestId: String?) async throws -> StampAddResponse {
        DebugLog.log("wallet.stamp_add -> amount=\(amount) reason=\(reason ?? "-")")
        let request = StampAddRequest(amount: amount, reason: reason, clientRequestId: clientRequestId)
        let response: StampAddResponse = try await postWallet(request)
        DebugLog.log("wallet.stamp_add -> balance=\(response.balance) idempotent=\(response.idempotent)")
        return response
    }

    func fetchChallengeStatus(year: Int? = nil, month: Int? = nil) async throws -> ChallengeStatusResponse {
        DebugLog.log("wallet.challenge_status -> year=\(year?.description ?? "-") month=\(month?.description ?? "-")")
        let request = ChallengeStatusRequest(year: year, month: month)
        let response: ChallengeStatusResponse = try await postWallet(request)
        DebugLog.log("wallet.challenge_status -> claimedMonthly=\(response.claimedMonthly.count) claimedCumulative=\(response.claimedCumulative.count)")
        return response
    }

    func fetchChallengeList() async throws -> ChallengeListResponse {
        DebugLog.log("wallet.challenge_list -> request")
        let request = ChallengeListRequest()
        let response: ChallengeListResponse = try await postWallet(request)
        DebugLog.log("wallet.challenge_list -> monthly=\(response.monthly.count) cumulative=\(response.cumulative.count)")
        return response
    }

    func claimChallengeReward(key: String, year: Int? = nil, month: Int? = nil, clientRequestId: String?) async throws -> ChallengeClaimResponse {
        DebugLog.log("wallet.challenge_claim -> key=\(key) year=\(year?.description ?? "-") month=\(month?.description ?? "-")")
        let request = ChallengeClaimRequest(key: key, year: year, month: month, clientRequestId: clientRequestId)
        let response: ChallengeClaimResponse = try await postWallet(request)
        DebugLog.log("wallet.challenge_claim -> idempotent=\(response.idempotent)")
        return response
    }

    // MARK: - Coin Daily Usage

    func fetchCoinDailyUsage() async throws -> CoinDailyUsageResponse {
        DebugLog.log("wallet.coin_daily_usage -> request")
        let request = CoinDailyUsageRequest()
        let response: CoinDailyUsageResponse = try await postWallet(request)
        DebugLog.log("wallet.coin_daily_usage -> used=\(response.used) limit=\(response.dailyLimit) remaining=\(response.remaining)")
        return response
    }

    func useCoinsDaily(amount: Int, reason: String?, clientRequestId: String?) async throws -> CoinUseDailyResponse {
        DebugLog.log("wallet.coin_use_daily -> amount=\(amount) reason=\(reason ?? "-")")
        let request = CoinUseDailyRequest(amount: amount, reason: reason, clientRequestId: clientRequestId)
        let response: CoinUseDailyResponse = try await postWallet(request)
        DebugLog.log("wallet.coin_use_daily -> balance=\(response.balance) dailyRemaining=\(response.dailyRemaining)")
        return response
    }

    // MARK: - Gold Stamp

    func fetchGoldStampBalance() async throws -> GoldStampBalanceResponse {
        DebugLog.log("wallet.gold_stamp_get -> request")
        let request = GoldStampGetRequest()
        let response: GoldStampBalanceResponse = try await postWallet(request)
        DebugLog.log("wallet.gold_stamp_get -> balance=\(response.balance) total=\(response.totalEarned)")
        return response
    }

    func exchangeGoldStamp(clientRequestId: String?) async throws -> GoldStampExchangeResponse {
        DebugLog.log("wallet.gold_stamp_exchange -> request")
        let request = GoldStampExchangeRequest(clientRequestId: clientRequestId)
        let response: GoldStampExchangeResponse = try await postWallet(request)
        DebugLog.log("wallet.gold_stamp_exchange -> coinBalance=\(response.coinBalance) gsBalance=\(response.goldStampBalance)")
        return response
    }

    func useGoldStamp(amount: Int, useType: String, clientRequestId: String?) async throws -> GoldStampUseResponse {
        DebugLog.log("wallet.gold_stamp_use -> amount=\(amount) type=\(useType)")
        let request = GoldStampUseRequest(amount: amount, useType: useType, clientRequestId: clientRequestId)
        let response: GoldStampUseResponse = try await postWallet(request)
        DebugLog.log("wallet.gold_stamp_use -> gsBalance=\(response.goldStampBalance) limitAdded=\(response.coinLimitAdded)")
        return response
    }

    func fetchStampHistory(limit: Int = 50, beforeId: Int? = nil) async throws -> StampHistoryResponse {
        DebugLog.log("wallet.stamp_history -> limit=\(limit) beforeId=\(beforeId?.description ?? "-")")
        let request = StampHistoryRequest(limit: limit, beforeId: beforeId)
        let response: StampHistoryResponse = try await postWallet(request)
        DebugLog.log("wallet.stamp_history -> items=\(response.items.count) next=\(response.nextBeforeId?.description ?? "nil")")
        return response
    }

    private func postWallet<Request: Encodable, Response: Decodable>(_ body: Request) async throws -> Response {
        var request = URLRequest(url: walletAPIURL)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        DebugLog.log("wallet.request -> url=\(walletAPIURL.absoluteString)")

        let (data, response) = try await session.data(for: request)

        if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
            let e = apiError.error
            if let body = String(data: data, encoding: .utf8) {
                DebugLog.log("wallet.error.body -> \(body)")
            }
            DebugLog.log("wallet.error -> code=\(e.code ?? "-") message=\(e.message)")
            throw APIError.server(code: e.code, message: e.message, detail: e.detail, fields: e.fields, i18nKey: e.i18nKey)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLog.log("wallet.error -> invalidResponse")
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let body = String(data: data, encoding: .utf8) {
                DebugLog.log("wallet.error.body -> \(body)")
            }
            DebugLog.log("wallet.error -> status=\(httpResponse.statusCode)")
            throw APIError.unexpectedStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            DebugLog.log("wallet.error -> decoding")
            throw APIError.decoding
        }
    }
}
private struct StampHistoryRequest: Encodable {
    let action: WalletAction = .stampHistory
    let limit: Int
    let beforeId: Int?
}

// MARK: - Fog Map API Client

final class FogMapAPIClient {
    static let shared = FogMapAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var apiURL: URL { APIConfig.fogMapAPIURL }

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func syncVisits(_ visits: [(latitude: Double, longitude: Double, visitedAt: String)]) async throws -> FogVisitSyncResponse {
        let visitsData = visits.map { [
            "latitude": String($0.latitude),
            "longitude": String($0.longitude),
            "visited_at": $0.visitedAt
        ] }
        let request = FogVisitSyncRequest(visits: visitsData)
        return try await postAPI(request)
    }

    func fetchVisits(limit: Int = 1000, afterId: Int? = nil) async throws -> FogVisitListResponse {
        let request = FogVisitListRequest(limit: limit, afterId: afterId)
        return try await postAPI(request)
    }

    func addWaypoint(latitude: Double, longitude: Double, title: String?, note: String?, photoUrl: String?) async throws -> WaypointAddResponse {
        let request = WaypointAddRequest(latitude: latitude, longitude: longitude, title: title, note: note, photoUrl: photoUrl)
        return try await postAPI(request)
    }

    func fetchWaypoints() async throws -> WaypointListResponse {
        let request = WaypointListRequest()
        return try await postAPI(request)
    }

    func updateWaypoint(waypointId: Int, title: String?, note: String?, photoUrl: String?) async throws -> WaypointUpdateResponse {
        let request = WaypointUpdateRequest(waypointId: waypointId, title: title, note: note, photoUrl: photoUrl)
        return try await postAPI(request)
    }

    func deleteWaypoint(waypointId: Int) async throws -> WaypointDeleteResponse {
        let request = WaypointDeleteRequest(waypointId: waypointId)
        return try await postAPI(request)
    }

    func uploadImage(imageData: Data, category: String = "waypoint") async throws -> ImageUploadResponse {
        let uploadURL = APIConfig.uploadAPIURL
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // category field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"category\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(category)\r\n".data(using: .utf8)!)

        // image file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
            let e = apiError.error
            throw APIError.server(code: e.code, message: e.message, detail: e.detail, fields: e.fields, i18nKey: e.i18nKey)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return try decoder.decode(ImageUploadResponse.self, from: data)
    }

    private func postAPI<Request: Encodable, Response: Decodable>(_ body: Request) async throws -> Response {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
            let e = apiError.error
            throw APIError.server(code: e.code, message: e.message, detail: e.detail, fields: e.fields, i18nKey: e.i18nKey)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}

// MARK: - Article API Client

final class ArticleAPIClient {
    static let shared = ArticleAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var apiURL: URL { APIConfig.articleAPIURL }

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func postArticle(title: String, body: String, imageUrl: String?) async throws -> ArticlePostResponse {
        let request = ArticlePostRequest(title: title, body: body, imageUrl: imageUrl)
        return try await postAPI(request)
    }

    func fetchArticles(sort: String = "new", limit: Int = 20, offset: Int = 0) async throws -> ArticleListResponse {
        let request = ArticleListRequest(sort: sort, limit: limit, offset: offset)
        return try await postAPI(request)
    }

    func fetchArticleDetail(articleId: Int) async throws -> ArticleDetailResponse {
        let request = ArticleDetailRequest(articleId: articleId)
        return try await postAPI(request)
    }

    func react(articleId: Int, type: String = "like") async throws -> ArticleReactResponse {
        let request = ArticleReactRequest(articleId: articleId, type: type)
        return try await postAPI(request)
    }

    func fetchRanking(rankBy: String = "reactions", limit: Int = 20) async throws -> ArticleRankingResponse {
        let request = ArticleRankingRequest(rankBy: rankBy, limit: limit)
        return try await postAPI(request)
    }

    private func postAPI<Request: Encodable, Response: Decodable>(_ body: Request) async throws -> Response {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
            let e = apiError.error
            throw APIError.server(code: e.code, message: e.message, detail: e.detail, fields: e.fields, i18nKey: e.i18nKey)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}

// MARK: - Treasure API Client

final class TreasureAPIClient {
    static let shared = TreasureAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var apiURL: URL { APIConfig.treasureAPIURL }

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func openBox(puzzleId: Int = 1) async throws -> TreasureOpenResponse {
        let request = TreasureOpenRequest(puzzleId: puzzleId)
        return try await postAPI(request)
    }

    func fetchPuzzleStatus(puzzleId: Int = 1) async throws -> PuzzleStatusResponse {
        let request = PuzzleStatusRequest(puzzleId: puzzleId)
        return try await postAPI(request)
    }

    func completePuzzle(puzzleId: Int = 1) async throws -> PuzzleCompleteResponse {
        let request = PuzzleCompleteRequest(puzzleId: puzzleId)
        return try await postAPI(request)
    }

    private func postAPI<Request: Encodable, Response: Decodable>(_ body: Request) async throws -> Response {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
            let e = apiError.error
            throw APIError.server(code: e.code, message: e.message, detail: e.detail, fields: e.fields, i18nKey: e.i18nKey)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}
