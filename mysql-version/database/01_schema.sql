-- ══════════════════════════════════════════════════════════════════════════
-- SözLab — MySQL / MariaDB sxemi
-- cPanel → phpMyAdmin → (bazanı seç) → Import → bu fayl → Go
--
-- MySQL 8.0+ və MariaDB 10.5+ ilə uyğundur. Saxlanan funksiya, trigger, view
-- YOXDUR — paylaşımlı hostinqdə bunlar SUPER hüququ tələb edir və import
-- yarıda dayanır. Bütün məntiq (təhlükəsizlik qaydaları daxil) Node serverindədir.
-- Kolasiya utf8mb4_bin: müqayisə PostgreSQL kimi dəqiqdir (böyük/kiçik hərf və
-- "ı/i" fərqlənir) — istifadəçi adı və lüğət sözü üçün vacibdir.
-- Avtomatik yaradılıb (gen_schema.py) — əl ilə dəyişməyin.
-- ══════════════════════════════════════════════════════════════════════════
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
SET time_zone = '+00:00';

-- ── Giriş sistemi (Supabase Auth-un əvəzi) ──
CREATE TABLE IF NOT EXISTS `auth_users` (
  `id` CHAR(36) NOT NULL,
  `email` VARCHAR(191) NOT NULL,
  `password_hash` VARCHAR(191) NOT NULL,
  `email_confirmed_at` DATETIME(3) NULL,
  `raw_user_meta_data` JSON NULL,
  `otp_hash` VARCHAR(191) NULL,
  `otp_expires_at` DATETIME(3) NULL,
  `otp_attempts` INT NOT NULL DEFAULT 0,
  `otp_sent_at` DATETIME(3) NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_auth_users_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `auth_sessions` (
  `token_hash` CHAR(64) NOT NULL,
  `user_id` CHAR(36) NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `expires_at` DATETIME(3) NOT NULL,
  PRIMARY KEY (`token_hash`),
  KEY `idx_auth_sessions_user` (`user_id`),
  CONSTRAINT `fk_auth_sessions_user` FOREIGN KEY (`user_id`) REFERENCES `auth_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `storage_objects` (
  `id` CHAR(36) NOT NULL,
  `bucket_id` VARCHAR(64) NOT NULL,
  `name` VARCHAR(191) NOT NULL,
  `owner` CHAR(36) NULL,
  `mime` VARCHAR(100) NOT NULL,
  `size` INT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_storage_objects_path` (`bucket_id`, `name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `announcements` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `title` TEXT NOT NULL,
  `content` TEXT NOT NULL,
  `type` TEXT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_announcements_created` (`created_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `class_boss_sessions` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `code` VARCHAR(191) NOT NULL,
  `teacher_username` TEXT NOT NULL,
  `class_grade` VARCHAR(191) NOT NULL,
  `boss_name` TEXT NOT NULL,
  `boss_max_hp` INT NOT NULL DEFAULT 200,
  `boss_hp` INT NOT NULL DEFAULT 200,
  `damage_per_correct` INT NOT NULL DEFAULT 5,
  `questions` JSON NOT NULL,
  `status` VARCHAR(191) NOT NULL DEFAULT 'waiting',
  `defeated` TINYINT(1) NOT NULL DEFAULT 0,
  `current_index` INT NOT NULL DEFAULT -1,
  `question_started_at` DATETIME(3),
  `xp_awarded` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_class_boss_sessions_1` (`code`),
  KEY `idx_boss_sessions_code` (`code`),
  KEY `idx_boss_sessions_class` (`class_grade`, `created_at` DESC),
  CONSTRAINT `ck_class_boss_sessions_1` CHECK (`status` IN ('waiting', 'question', 'reveal', 'finished'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `class_boss_participants` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `session_id` BIGINT NOT NULL,
  `username` VARCHAR(191) NOT NULL,
  `display_name` TEXT NOT NULL,
  `damage_dealt` INT NOT NULL DEFAULT 0,
  `hits` INT NOT NULL DEFAULT 0,
  `last_answered_index` INT NOT NULL DEFAULT -1,
  `joined_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_class_boss_participants_1` (`session_id`, `username`),
  KEY `idx_boss_participants_session` (`session_id`),
  CONSTRAINT `fk_class_boss_participants_1` FOREIGN KEY (`session_id`) REFERENCES `class_boss_sessions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `class_tasks` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `teacher_username` TEXT NOT NULL,
  `class_grade` VARCHAR(191) NOT NULL,
  `title` TEXT NOT NULL,
  `target_xp` INT NOT NULL DEFAULT 0,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_class_tasks_class` (`class_grade`, `created_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `class_task_completions` (
  `task_id` BIGINT NOT NULL,
  `username` VARCHAR(191) NOT NULL,
  `completed_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`task_id`, `username`),
  CONSTRAINT `fk_class_task_completions_1` FOREIGN KEY (`task_id`) REFERENCES `class_tasks` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `word_submissions` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `username` VARCHAR(191) NOT NULL,
  `display_name` TEXT NOT NULL,
  `word` TEXT NOT NULL,
  `definition` TEXT NOT NULL,
  `example` TEXT NOT NULL,
  `status` VARCHAR(191) NOT NULL DEFAULT 'pending',
  `xp_awarded` TINYINT(1) NOT NULL DEFAULT 0,
  `submitted_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `reviewed_at` DATETIME(3),
  `reviewed_by` TEXT,
  PRIMARY KEY (`id`),
  KEY `idx_word_sub_username` (`username`, `submitted_at` DESC),
  KEY `idx_word_sub_status` (`status`, `submitted_at` DESC),
  CONSTRAINT `ck_word_submissions_1` CHECK (`status` IN ('pending', 'flagged', 'approved', 'rejected'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `community_words` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `en` TEXT NOT NULL,
  `az` TEXT NOT NULL,
  `ex` TEXT NOT NULL,
  `ex_az` TEXT NOT NULL,
  `tags` JSON NOT NULL,
  `difficulty` INT NOT NULL DEFAULT 2,
  `added_by` TEXT NOT NULL,
  `added_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `source_submission_id` BIGINT,
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_community_words_1` FOREIGN KEY (`source_submission_id`) REFERENCES `word_submissions` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `cosmetics_catalog` (
  `id` VARCHAR(191) NOT NULL,
  `type` VARCHAR(191) NOT NULL,
  `name` TEXT NOT NULL,
  `icon` TEXT NOT NULL,
  `min_xp` INT NOT NULL DEFAULT 0,
  `sort_order` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  CONSTRAINT `ck_cosmetics_catalog_1` CHECK (`type` IN ('frame', 'theme'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `duels` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `p1_username` VARCHAR(191) NOT NULL,
  `p2_username` VARCHAR(191) NOT NULL,
  `status` VARCHAR(191) NOT NULL DEFAULT 'pending',
  `questions` JSON NOT NULL,
  `p1_score` INT NOT NULL DEFAULT 0,
  `p1_progress` INT NOT NULL DEFAULT 0,
  `p1_finished_at` DATETIME(3),
  `p2_score` INT NOT NULL DEFAULT 0,
  `p2_progress` INT NOT NULL DEFAULT 0,
  `p2_finished_at` DATETIME(3),
  `winner_username` TEXT,
  `xp_awarded` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `mode` VARCHAR(191) NOT NULL DEFAULT 'normal',
  PRIMARY KEY (`id`),
  KEY `idx_duels_p1` (`p1_username`, `created_at` DESC),
  KEY `idx_duels_p2` (`p2_username`, `created_at` DESC),
  CONSTRAINT `ck_duels_1` CHECK (`mode` IN ('normal', 'sureli')),
  CONSTRAINT `ck_duels_2` CHECK (`status` IN ('pending', 'active', 'declined', 'finished', 'cancelled'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `live_quiz_sessions` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `code` VARCHAR(191) NOT NULL,
  `teacher_username` TEXT NOT NULL,
  `class_grade` VARCHAR(191) NOT NULL,
  `status` VARCHAR(191) NOT NULL DEFAULT 'waiting',
  `questions` JSON NOT NULL,
  `current_index` INT NOT NULL DEFAULT -1,
  `question_started_at` DATETIME(3),
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `xp_awarded` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_live_quiz_sessions_1` (`code`),
  KEY `idx_lq_sessions_code` (`code`),
  KEY `idx_lq_sessions_class` (`class_grade`, `created_at` DESC),
  CONSTRAINT `ck_live_quiz_sessions_1` CHECK (`status` IN ('waiting', 'question', 'reveal', 'finished'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `live_quiz_participants` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `session_id` BIGINT NOT NULL,
  `username` VARCHAR(191) NOT NULL,
  `display_name` TEXT NOT NULL,
  `score` INT NOT NULL DEFAULT 0,
  `last_answered_index` INT NOT NULL DEFAULT -1,
  `last_correct` TINYINT(1),
  `last_points` INT NOT NULL DEFAULT 0,
  `joined_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_live_quiz_participants_1` (`session_id`, `username`),
  KEY `idx_lq_participants_session` (`session_id`),
  CONSTRAINT `fk_live_quiz_participants_1` FOREIGN KEY (`session_id`) REFERENCES `live_quiz_sessions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `newsletter_signups` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `email` VARCHAR(191) NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_newsletter_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `profiles` (
  `id` CHAR(36) NOT NULL,
  `username` VARCHAR(191) NOT NULL,
  `display_name` TEXT NOT NULL,
  `xp` INT NOT NULL DEFAULT 0,
  `level` INT NOT NULL DEFAULT 1,
  `streak` INT NOT NULL DEFAULT 0,
  `last_visit` TEXT,
  `learned` JSON NOT NULL,
  `badges` JSON NOT NULL,
  `role` VARCHAR(191) NOT NULL DEFAULT 'user',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `first_name` TEXT NOT NULL,
  `last_name` TEXT NOT NULL,
  `class_grade` VARCHAR(191) NOT NULL DEFAULT '',
  `teacher_class` VARCHAR(191) NOT NULL DEFAULT '',
  `days_active` INT NOT NULL DEFAULT 0,
  `equipped_frame` TEXT NOT NULL,
  `equipped_theme` TEXT NOT NULL,
  `weak_words` JSON NOT NULL,
  `games_played` JSON NOT NULL,
  `longest_streak` INT NOT NULL DEFAULT 0,
  `referred_by` TEXT NOT NULL,
  `phone` TEXT NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_profiles_1` (`username`),
  KEY `idx_profiles_xp` (`xp` DESC),
  KEY `idx_profiles_username` (`username`),
  KEY `idx_profiles_role` (`role`),
  KEY `idx_profiles_class_grade` (`class_grade`),
  KEY `idx_profiles_teacher_class` (`teacher_class`),
  CONSTRAINT `fk_profiles_1` FOREIGN KEY (`id`) REFERENCES `auth_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_profiles_2` CHECK (`role` IN ('user', 'admin', 'teacher', 'director', 'mentor'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `school_achievements` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `title` TEXT NOT NULL,
  `description` TEXT NOT NULL,
  `achieved_on` DATE,
  `image_url` TEXT NOT NULL,
  `created_by` CHAR(36),
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `category` TEXT NOT NULL,
  `section` TEXT NOT NULL,
  `author` TEXT NOT NULL,
  `keywords` JSON NOT NULL,
  `student_name` TEXT NOT NULL,
  `class_name` TEXT NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_school_achievements_date` (`achieved_on` DESC),
  CONSTRAINT `fk_school_achievements_1` FOREIGN KEY (`created_by`) REFERENCES `auth_users` (`id`) ON DELETE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `school_events` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `title` TEXT NOT NULL,
  `description` TEXT NOT NULL,
  `event_date` DATE,
  `location` TEXT NOT NULL,
  `image_url` TEXT NOT NULL,
  `created_by` CHAR(36),
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `category` TEXT NOT NULL,
  `section` TEXT NOT NULL,
  `author` TEXT NOT NULL,
  `keywords` JSON NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_school_events_date` (`event_date` DESC),
  CONSTRAINT `fk_school_events_1` FOREIGN KEY (`created_by`) REFERENCES `auth_users` (`id`) ON DELETE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `school_info` (
  `id` SMALLINT NOT NULL DEFAULT 1,
  `school_name` TEXT NOT NULL,
  `about_text` TEXT NOT NULL,
  `address` TEXT NOT NULL,
  `phone` TEXT NOT NULL,
  `email` TEXT NOT NULL,
  `cover_image_url` TEXT NOT NULL,
  `updated_by` CHAR(36),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_school_info_1` FOREIGN KEY (`updated_by`) REFERENCES `auth_users` (`id`) ON DELETE NO ACTION,
  CONSTRAINT `ck_school_info_1` CHECK (`id` = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `school_news` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `title` TEXT NOT NULL,
  `body` TEXT NOT NULL,
  `image_url` TEXT NOT NULL,
  `published` TINYINT(1) NOT NULL DEFAULT 1,
  `created_by` CHAR(36),
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `category` VARCHAR(191) NOT NULL DEFAULT 'Məktəb həyatı',
  `section` TEXT NOT NULL,
  `author` TEXT NOT NULL,
  `keywords` JSON NOT NULL,
  `published_at` DATE NOT NULL,
  `gallery` JSON NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_school_news_created` (`published`, `created_at` DESC),
  KEY `idx_school_news_category` (`category`, `published_at` DESC),
  CONSTRAINT `fk_school_news_1` FOREIGN KEY (`created_by`) REFERENCES `auth_users` (`id`) ON DELETE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `school_submissions` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `student_id` CHAR(36) NOT NULL,
  `type` VARCHAR(191) NOT NULL,
  `title` TEXT NOT NULL,
  `description` TEXT NOT NULL,
  `file_url` TEXT NOT NULL,
  `image_url` TEXT NOT NULL,
  `status` VARCHAR(191) NOT NULL DEFAULT 'pending',
  `admin_note` TEXT NOT NULL,
  `reviewed_by` CHAR(36),
  `reviewed_at` DATETIME(3),
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_school_submissions_student` (`student_id`, `created_at` DESC),
  KEY `idx_school_submissions_status` (`type`, `status`, `created_at` DESC),
  CONSTRAINT `fk_school_submissions_1` FOREIGN KEY (`reviewed_by`) REFERENCES `auth_users` (`id`) ON DELETE NO ACTION,
  CONSTRAINT `fk_school_submissions_2` FOREIGN KEY (`student_id`) REFERENCES `auth_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_school_submissions_1` CHECK (`status` IN ('pending', 'approved', 'rejected')),
  CONSTRAINT `ck_school_submissions_3` CHECK (`type` IN ('project', 'idea', 'startup'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `school_teachers` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `full_name` VARCHAR(191) NOT NULL,
  `subject` TEXT NOT NULL,
  `photo_url` TEXT NOT NULL,
  `bio` TEXT NOT NULL,
  `sort_order` INT NOT NULL DEFAULT 0,
  `created_by` CHAR(36),
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_school_teachers_sort` (`sort_order`, `full_name`),
  CONSTRAINT `fk_school_teachers_1` FOREIGN KEY (`created_by`) REFERENCES `auth_users` (`id`) ON DELETE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_achievements` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `username` VARCHAR(191) NOT NULL,
  `code` TEXT NOT NULL,
  `title` TEXT NOT NULL,
  `detail` TEXT NOT NULL,
  `icon` TEXT NOT NULL,
  `module` VARCHAR(191) NOT NULL DEFAULT 'world',
  `ref_id` BIGINT,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `ss_achievements_user_idx` (`username`, `created_at` DESC),
  CONSTRAINT `ck_ss_achievements_1` CHECK (`module` IN ('world', 'bank', 'startup', 'problem', 'humanity', 'olympics'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_challenges` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `scope` VARCHAR(191) NOT NULL DEFAULT 'world',
  `title` TEXT NOT NULL,
  `slug` VARCHAR(191),
  `category` TEXT NOT NULL,
  `icon` TEXT NOT NULL,
  `summary` TEXT NOT NULL,
  `problem` TEXT NOT NULL,
  `why` TEXT NOT NULL,
  `research` TEXT NOT NULL,
  `approaches` TEXT NOT NULL,
  `difficulty` VARCHAR(191) NOT NULL DEFAULT 'orta',
  `points` INT NOT NULL DEFAULT 50,
  `deadline` DATE,
  `status` VARCHAR(191) NOT NULL DEFAULT 'open',
  `created_by` TEXT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ss_challenges_1` (`slug`),
  CONSTRAINT `ck_ss_challenges_1` CHECK (`difficulty` IN ('asan', 'orta', 'çətin')),
  CONSTRAINT `ck_ss_challenges_2` CHECK (`scope` IN ('world', 'humanity')),
  CONSTRAINT `ck_ss_challenges_3` CHECK (`status` IN ('open', 'judging', 'closed'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_hall_of_fame` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `season` TEXT NOT NULL,
  `category` TEXT NOT NULL,
  `username` TEXT NOT NULL,
  `display_name` TEXT NOT NULL,
  `class_grade` TEXT NOT NULL,
  `medal` VARCHAR(191) NOT NULL,
  `score` INT NOT NULL DEFAULT 0,
  `note` TEXT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `ck_ss_hall_of_fame_1` CHECK (`medal` IN ('gold', 'silver', 'bronze'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_teams` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `name` TEXT NOT NULL,
  `purpose` VARCHAR(191) NOT NULL DEFAULT 'challenge',
  `ref_id` BIGINT,
  `owner` TEXT NOT NULL,
  `members` JSON NOT NULL,
  `school_ids` JSON NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `ck_ss_teams_1` CHECK (`purpose` IN ('challenge', 'startup', 'problem', 'humanity', 'olympics'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_humanity_projects` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `challenge_id` BIGINT,
  `title` TEXT NOT NULL,
  `category` TEXT NOT NULL,
  `author` TEXT NOT NULL,
  `team_id` BIGINT,
  `research` TEXT NOT NULL,
  `idea` TEXT NOT NULL,
  `solution` TEXT NOT NULL,
  `prototype` TEXT NOT NULL,
  `link` TEXT NOT NULL,
  `stage` VARCHAR(191) NOT NULL DEFAULT 'research',
  `status` VARCHAR(191) NOT NULL DEFAULT 'active',
  `impact_points` INT NOT NULL DEFAULT 0,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_ss_humanity_projects_1` FOREIGN KEY (`challenge_id`) REFERENCES `ss_challenges` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_ss_humanity_projects_2` FOREIGN KEY (`team_id`) REFERENCES `ss_teams` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_ss_humanity_projects_1` CHECK (`stage` IN ('research', 'idea', 'team', 'solution', 'prototype', 'presentation')),
  CONSTRAINT `ck_ss_humanity_projects_2` CHECK (`status` IN ('active', 'completed', 'featured', 'archived'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_startups` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `name` TEXT NOT NULL,
  `tagline` TEXT NOT NULL,
  `problem` TEXT NOT NULL,
  `solution` TEXT NOT NULL,
  `target_users` TEXT NOT NULL,
  `category` TEXT NOT NULL,
  `description` TEXT NOT NULL,
  `logo_url` TEXT NOT NULL,
  `deck_url` TEXT NOT NULL,
  `demo_url` TEXT NOT NULL,
  `founder` TEXT NOT NULL,
  `team_id` BIGINT,
  `stage` VARCHAR(191) NOT NULL DEFAULT 'idea',
  `status` VARCHAR(191) NOT NULL DEFAULT 'active',
  `votes` INT NOT NULL DEFAULT 0,
  `demo_day` TEXT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_ss_startups_1` FOREIGN KEY (`team_id`) REFERENCES `ss_teams` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_ss_startups_1` CHECK (`stage` IN ('idea', 'validation', 'team', 'prototype', 'mvp', 'mentor', 'pitch', 'demoday')),
  CONSTRAINT `ck_ss_startups_2` CHECK (`status` IN ('active', 'paused', 'graduated', 'archived'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_mentor_feedback` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `startup_id` BIGINT NOT NULL,
  `mentor` TEXT NOT NULL,
  `stage` TEXT NOT NULL,
  `verdict` VARCHAR(191) NOT NULL DEFAULT 'comment',
  `body` TEXT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_ss_mentor_feedback_1` FOREIGN KEY (`startup_id`) REFERENCES `ss_startups` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_ss_mentor_feedback_1` CHECK (`verdict` IN ('comment', 'approved', 'changes', 'rejected'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_olympics_events` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `season` TEXT NOT NULL,
  `category` TEXT NOT NULL,
  `icon` TEXT NOT NULL,
  `stage` VARCHAR(191) NOT NULL DEFAULT 'qualification',
  `status` VARCHAR(191) NOT NULL DEFAULT 'upcoming',
  `starts_at` DATETIME(3),
  `duration_min` INT NOT NULL DEFAULT 15,
  `question_count` INT NOT NULL DEFAULT 12,
  `description` TEXT NOT NULL,
  `created_by` TEXT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `ck_ss_olympics_events_1` CHECK (`stage` IN ('qualification', 'class', 'grade', 'final', 'championship')),
  CONSTRAINT `ck_ss_olympics_events_2` CHECK (`status` IN ('upcoming', 'live', 'finished'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_olympics_results` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `event_id` BIGINT NOT NULL,
  `username` VARCHAR(191) NOT NULL,
  `class_grade` TEXT NOT NULL,
  `score` INT NOT NULL DEFAULT 0,
  `accuracy` INT NOT NULL DEFAULT 0,
  `best_combo` INT NOT NULL DEFAULT 0,
  `duration_s` INT NOT NULL DEFAULT 0,
  `medal` VARCHAR(191),
  `rank` INT,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ss_olympics_results_1` (`event_id`, `username`),
  KEY `ss_olympics_results_event_idx` (`event_id`, `score` DESC),
  CONSTRAINT `fk_ss_olympics_results_1` FOREIGN KEY (`event_id`) REFERENCES `ss_olympics_events` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_ss_olympics_results_1` CHECK (`medal` IN ('gold', 'silver', 'bronze'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_points_ledger` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `username` VARCHAR(191) NOT NULL,
  `amount` INT NOT NULL,
  `reason` TEXT NOT NULL,
  `source` VARCHAR(191) NOT NULL DEFAULT 'system',
  `ref_id` BIGINT,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `ss_points_user_idx` (`username`, `created_at` DESC),
  CONSTRAINT `ck_ss_points_ledger_1` CHECK (`source` IN ('system', 'quiz', 'challenge', 'project', 'startup', 'olympics', 'problem', 'help', 'teacher', 'reward', 'admin'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_problems` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `title` TEXT NOT NULL,
  `body` TEXT NOT NULL,
  `category` TEXT NOT NULL,
  `difficulty` VARCHAR(191) NOT NULL DEFAULT 'orta',
  `status` VARCHAR(191) NOT NULL DEFAULT 'open',
  `points` INT NOT NULL DEFAULT 75,
  `created_by` TEXT NOT NULL,
  `deadline` DATE,
  `solved_by` JSON NOT NULL,
  `solved_at` DATETIME(3),
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `ck_ss_problems_1` CHECK (`difficulty` IN ('asan', 'orta', 'çətin')),
  CONSTRAINT `ck_ss_problems_2` CHECK (`status` IN ('open', 'progress', 'solved', 'implemented'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_rewards` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `code` VARCHAR(191) NOT NULL,
  `name` TEXT NOT NULL,
  `description` TEXT NOT NULL,
  `icon` TEXT NOT NULL,
  `cost` INT NOT NULL,
  `kind` VARCHAR(191) NOT NULL DEFAULT 'badge',
  `stock` INT,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `sort_order` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ss_rewards_1` (`code`),
  CONSTRAINT `ck_ss_rewards_1` CHECK (`cost` >= 0),
  CONSTRAINT `ck_ss_rewards_2` CHECK (`kind` IN ('badge', 'theme', 'booster', 'rank', 'pass', 'frame'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_reward_claims` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `username` VARCHAR(191) NOT NULL,
  `reward_id` BIGINT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ss_reward_claims_1` (`username`, `reward_id`),
  CONSTRAINT `fk_ss_reward_claims_1` FOREIGN KEY (`reward_id`) REFERENCES `ss_rewards` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_schools` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `name` TEXT NOT NULL,
  `country` TEXT NOT NULL,
  `country_code` TEXT NOT NULL,
  `city` TEXT NOT NULL,
  `lat` DECIMAL(6,3),
  `lng` DECIMAL(6,3),
  `student_count` INT NOT NULL DEFAULT 0,
  `status` VARCHAR(191) NOT NULL DEFAULT 'pending',
  `website` TEXT NOT NULL,
  `note` TEXT NOT NULL,
  `is_home` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `ck_ss_schools_1` CHECK (`status` IN ('connected', 'pending', 'invited'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_solutions` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `problem_id` BIGINT NOT NULL,
  `author` TEXT NOT NULL,
  `team_id` BIGINT,
  `title` TEXT NOT NULL,
  `idea` TEXT NOT NULL,
  `solution` TEXT NOT NULL,
  `prototype` TEXT NOT NULL,
  `stage` VARCHAR(191) NOT NULL DEFAULT 'idea',
  `status` VARCHAR(191) NOT NULL DEFAULT 'submitted',
  `feedback` TEXT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_ss_solutions_1` FOREIGN KEY (`problem_id`) REFERENCES `ss_problems` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ss_solutions_2` FOREIGN KEY (`team_id`) REFERENCES `ss_teams` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_ss_solutions_1` CHECK (`stage` IN ('idea', 'team', 'solution', 'prototype', 'review', 'implemented')),
  CONSTRAINT `ck_ss_solutions_2` CHECK (`status` IN ('submitted', 'accepted', 'implemented', 'rejected'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_startup_votes` (
  `startup_id` BIGINT NOT NULL,
  `username` VARCHAR(191) NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`startup_id`, `username`),
  CONSTRAINT `fk_ss_startup_votes_1` FOREIGN KEY (`startup_id`) REFERENCES `ss_startups` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `ss_submissions` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `challenge_id` BIGINT NOT NULL,
  `team_id` BIGINT,
  `author` TEXT NOT NULL,
  `title` TEXT NOT NULL,
  `description` TEXT NOT NULL,
  `link` TEXT NOT NULL,
  `image_url` TEXT NOT NULL,
  `status` VARCHAR(191) NOT NULL DEFAULT 'submitted',
  `score` INT,
  `feedback` TEXT NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_ss_submissions_1` FOREIGN KEY (`challenge_id`) REFERENCES `ss_challenges` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ss_submissions_2` FOREIGN KEY (`team_id`) REFERENCES `ss_teams` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_ss_submissions_1` CHECK (`status` IN ('submitted', 'reviewed', 'winner', 'rejected'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `stories` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `user_id` CHAR(36) NOT NULL,
  `username` TEXT NOT NULL,
  `display_name` TEXT NOT NULL,
  `text` TEXT NOT NULL,
  `likes` INT NOT NULL DEFAULT 0,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_stories_user` (`user_id`),
  KEY `idx_stories_created` (`created_at` DESC),
  CONSTRAINT `fk_stories_1` FOREIGN KEY (`user_id`) REFERENCES `auth_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `support_messages` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `username` VARCHAR(191) NOT NULL,
  `sender_role` VARCHAR(191) NOT NULL,
  `sender_name` TEXT NOT NULL,
  `body` TEXT NOT NULL,
  `read` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_support_messages_username` (`username`, `created_at`),
  CONSTRAINT `ck_support_messages_2` CHECK (`sender_role` IN ('user', 'admin', 'director', 'teacher'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `teacher_lessons` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `teacher_username` VARCHAR(191) NOT NULL,
  `title` TEXT NOT NULL,
  `slides` JSON NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_teacher_lessons_owner` (`teacher_username`, `created_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `xp_log` (
  `username` VARCHAR(191) NOT NULL,
  `log_date` DATE NOT NULL,
  `xp_gained` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`username`, `log_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

SET FOREIGN_KEY_CHECKS = 1;
