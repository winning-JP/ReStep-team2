-- ReStep Database Schema

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- users table
CREATE TABLE IF NOT EXISTS `users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `login_id` varchar(50) NOT NULL,
  `email` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `is_admin` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `login_id` (`login_id`),
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- user_profiles table
CREATE TABLE IF NOT EXISTS `user_profiles` (
  `user_id` int(11) NOT NULL,
  `nickname` varchar(20) DEFAULT NULL,
  `bluetooth_user_id` varchar(64) DEFAULT NULL,
  `encounter_visibility` enum('public','private') NOT NULL DEFAULT 'public',
  `birthday` date DEFAULT NULL,
  `gender` enum('男性','女性','その他') DEFAULT NULL,
  `height_cm` decimal(4,1) DEFAULT NULL,
  `weight_kg` decimal(4,1) DEFAULT NULL,
  `weekly_steps` int(11) DEFAULT NULL,
  `body_fat` int(11) DEFAULT NULL,
  `weekly_exercise` int(11) DEFAULT NULL,
  `goal_steps` int(11) DEFAULT NULL,
  `goal_calories` int(11) DEFAULT NULL,
  `goal_distance_km` decimal(4,1) DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `uniq_bluetooth_user_id` (`bluetooth_user_id`),
  CONSTRAINT `user_profiles_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- user_daily_stats table
CREATE TABLE IF NOT EXISTS `user_daily_stats` (
  `user_id` int(11) NOT NULL,
  `date` date NOT NULL,
  `steps` int(11) DEFAULT 0,
  `calories` int(11) DEFAULT 0,
  `distance_km` decimal(5,2) DEFAULT 0.00,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`,`date`),
  CONSTRAINT `user_daily_stats_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- user_refresh_tokens table
CREATE TABLE IF NOT EXISTS `user_refresh_tokens` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `token_hash` char(64) NOT NULL,
  `expires_at` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `last_used_at` datetime DEFAULT NULL,
  `revoked_at` datetime DEFAULT NULL,
  `device_name` varchar(100) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `replaced_by_hash` char(64) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_token_hash` (`token_hash`),
  KEY `idx_user_id` (`user_id`),
  CONSTRAINT `user_refresh_tokens_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- user_wallets table
CREATE TABLE IF NOT EXISTS `user_wallets` (
  `user_id` int(11) NOT NULL,
  `balance` bigint(20) NOT NULL DEFAULT 0,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_wallet_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- coin_transactions table
CREATE TABLE IF NOT EXISTS `coin_transactions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `delta` bigint(20) NOT NULL,
  `type` varchar(32) NOT NULL,
  `reason` varchar(255) DEFAULT NULL,
  `meta` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `balance_after` bigint(20) NOT NULL,
  `client_request_id` varchar(64) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_user_client_req` (`user_id`,`client_request_id`),
  KEY `idx_user_created` (`user_id`,`created_at`),
  KEY `idx_user_id_id` (`user_id`,`id`),
  CONSTRAINT `fk_tx_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- user_stamps table
CREATE TABLE IF NOT EXISTS `user_stamps` (
  `user_id` int(11) NOT NULL,
  `balance` int(11) NOT NULL DEFAULT 0,
  `total_earned` int(11) NOT NULL DEFAULT 0,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_user_stamps_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- stamp_transactions table
CREATE TABLE IF NOT EXISTS `stamp_transactions` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `delta` int(11) NOT NULL,
  `type` varchar(32) NOT NULL,
  `reason` varchar(255) DEFAULT NULL,
  `meta` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `balance_after` int(11) NOT NULL,
  `client_request_id` varchar(64) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_user_client` (`user_id`,`client_request_id`),
  KEY `idx_user_created` (`user_id`,`created_at`),
  CONSTRAINT `fk_stamp_tx_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- stamp_daily_earned table
CREATE TABLE IF NOT EXISTS `stamp_daily_earned` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `date_key` varchar(10) NOT NULL,
  `earned` int(11) NOT NULL DEFAULT 0,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_user_date` (`user_id`,`date_key`),
  KEY `idx_user_date` (`user_id`,`date_key`),
  CONSTRAINT `fk_stamp_daily_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- challenge_claims table
CREATE TABLE IF NOT EXISTS `challenge_claims` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `reward_key` varchar(64) NOT NULL,
  `period_key` varchar(7) NOT NULL DEFAULT '',
  `client_request_id` varchar(64) DEFAULT NULL,
  `claimed_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_user_reward_period` (`user_id`,`reward_key`,`period_key`),
  KEY `idx_user_period` (`user_id`,`period_key`),
  KEY `idx_user_reward` (`user_id`,`reward_key`),
  CONSTRAINT `fk_challenge_claims_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- user_continuity table
CREATE TABLE IF NOT EXISTS `user_continuity` (
  `user_id` int(11) NOT NULL,
  `current_streak` int(11) NOT NULL DEFAULT 0,
  `longest_streak` int(11) NOT NULL DEFAULT 0,
  `last_active_date` date DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_user_continuity_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- coin_daily_usage table (コイン日次使用量追跡)
CREATE TABLE IF NOT EXISTS `coin_daily_usage` (
  `user_id` int(11) NOT NULL,
  `date_key` varchar(10) NOT NULL,
  `used` int(11) NOT NULL DEFAULT 0,
  `daily_limit` int(11) NOT NULL DEFAULT 500,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`, `date_key`),
  CONSTRAINT `fk_coin_daily_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- gold_stamps table (ゴールドスタンプ残高)
CREATE TABLE IF NOT EXISTS `gold_stamps` (
  `user_id` int(11) NOT NULL,
  `balance` int(11) NOT NULL DEFAULT 0,
  `total_earned` int(11) NOT NULL DEFAULT 0,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_gold_stamps_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- gold_stamp_transactions table (ゴールドスタンプ取引履歴)
CREATE TABLE IF NOT EXISTS `gold_stamp_transactions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `delta` int(11) NOT NULL,
  `type` varchar(32) NOT NULL,
  `reason` varchar(255) DEFAULT NULL,
  `balance_after` int(11) NOT NULL,
  `client_request_id` varchar(64) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_gs_user_client_req` (`user_id`, `client_request_id`),
  KEY `idx_gs_user_created` (`user_id`, `created_at`),
  CONSTRAINT `fk_gs_tx_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- fog_visits table (地図埋め訪問地点)
CREATE TABLE IF NOT EXISTS `fog_visits` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `latitude` double NOT NULL,
  `longitude` double NOT NULL,
  `visited_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_fog_user` (`user_id`),
  CONSTRAINT `fk_fog_visits_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- waypoints table (ウェイポイント)
CREATE TABLE IF NOT EXISTS `waypoints` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `latitude` double NOT NULL,
  `longitude` double NOT NULL,
  `title` varchar(100) DEFAULT NULL,
  `note` text DEFAULT NULL,
  `photo_url` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_waypoint_user` (`user_id`),
  CONSTRAINT `fk_waypoints_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- articles table (記事)
CREATE TABLE IF NOT EXISTS `articles` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `title` varchar(200) NOT NULL,
  `body` text NOT NULL,
  `image_url` varchar(500) DEFAULT NULL,
  `view_count` int(11) NOT NULL DEFAULT 0,
  `reaction_count` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_article_user` (`user_id`),
  KEY `idx_article_created` (`created_at`),
  KEY `idx_article_reactions` (`reaction_count`),
  KEY `idx_article_views` (`view_count`),
  CONSTRAINT `fk_articles_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- article_reactions table (記事リアクション)
CREATE TABLE IF NOT EXISTS `article_reactions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `article_id` bigint(20) unsigned NOT NULL,
  `user_id` int(11) NOT NULL,
  `type` varchar(20) NOT NULL DEFAULT 'like',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_article_user_type` (`article_id`, `user_id`, `type`),
  CONSTRAINT `fk_reaction_article` FOREIGN KEY (`article_id`) REFERENCES `articles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_reaction_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- article_views table (記事閲覧)
CREATE TABLE IF NOT EXISTS `article_views` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `article_id` bigint(20) unsigned NOT NULL,
  `user_id` int(11) NOT NULL,
  `viewed_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_view_article_user` (`article_id`, `user_id`),
  CONSTRAINT `fk_view_article` FOREIGN KEY (`article_id`) REFERENCES `articles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_view_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- puzzle_pieces table (パズルピース)
CREATE TABLE IF NOT EXISTS `puzzle_pieces` (
  `user_id` int(11) NOT NULL,
  `puzzle_id` int(11) NOT NULL,
  `piece_index` int(11) NOT NULL,
  `obtained_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`user_id`, `puzzle_id`, `piece_index`),
  CONSTRAINT `fk_puzzle_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- treasure_box_history table (宝箱履歴)
CREATE TABLE IF NOT EXISTS `treasure_box_history` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `reward_type` varchar(30) NOT NULL,
  `reward_value` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_treasure_user` (`user_id`),
  CONSTRAINT `fk_treasure_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

SET FOREIGN_KEY_CHECKS = 1;
