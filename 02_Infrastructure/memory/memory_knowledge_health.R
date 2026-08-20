# memory_knowledge_health.R — v7.2.1 Sprint 5
#
# Memory Knowledge Health Gate
# Hard fail (6) + Warning (6 — external INFO 격하).
#
# Hard fail:
#   1) active axiom JSON parse 실패
#   2) active axiom 중 memory_id/axiom_class/authority/review_policy/enforcement_mode 누락
#   3) .claude/rules/axioms.md active vs JSON active 불일치 (sot_map 기준 — cache_core는 WARN)
#   4) deprecated와 active에 같은 memory_id + version 중복
#   5) review.R --all apply 없이 active JSON 변경
#   6) promote.R helper compatibility selftest 실패
#
# Warning:
#   1) L-code corpus 무결성 — 중복 ID · 미수확 아티팩트
#      (2026-07-25 교체: 구 gap>50 outlier 는 마크다운 인용 희소성을 재던 지표라 폐기)
#   2) stale candidate 90+ days
#   3) review_log 반복 스키마 과다 (싱글턴 일회성 문서 제외 계상)
#   4) external memory not indexed → INFO (audit v3 권고 B 격하)
#   5) enforcement claim ↔ hook 실제 강제력 불일치 (AX-003~005)
#   6) regime_validation parse fail (soft_mrs.json) + .cache/axiom_core.json STALE
#   7) Stop hook script ↔ settings.json 등록 정합 (2026-07-13 task#54-3ⓒ:
#      기대목록 현행 4건 — auto_commit·auto_push·performance_realmeasure_gate·
#      research_continuity_guard)
#   8) layer_bottleneck_map.md 신선도 — 최신 L-code 대비 24h+ 뒤처짐 (task#54-3ⓐ)
#   9) 최근 7일 negative(C/F) L-code next_probe 부재 (task#54-3ⓑ — AX-000 탐색 연속성)
#
# Usage: Rscript 02_Infrastructure/memory/memory_knowledge_health.R

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = "")
if (PROJ_ROOT == "" || !dir.exists(PROJ_ROOT)) {
  PROJ_ROOT <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

safe_str <- function(x, default = "?") {
  if (is.null(x) || length(x) == 0) return(default)
  v <- x
  if (is.list(v)) {
    # collapse list/object to digest string
    return(paste(deparse(v), collapse = "")[1] |> substr(1, 50))
  }
  if (length(v) > 1) v <- v[[1]]
  if (is.null(v)) return(default)
  as.character(v)[1]
}

hard_fails <- list()
warnings_list <- list()
infos <- list()

add_hard <- function(id, msg) {
  hard_fails[[length(hard_fails) + 1]] <<- list(check_id = id, message = msg)
  cat(sprintf("  [HARD FAIL] %s — %s\n", id, msg))
}
add_warn <- function(id, msg) {
  warnings_list[[length(warnings_list) + 1]] <<- list(check_id = id,
                                                      message = msg)
  cat(sprintf("  [WARN]      %s — %s\n", id, msg))
}
add_info <- function(id, msg) {
  infos[[length(infos) + 1]] <<- list(check_id = id, message = msg)
  cat(sprintf("  [INFO]      %s — %s\n", id, msg))
}

cat("=== memory_knowledge_health.R v7.2.1 Sprint 5 ===\n\n")

# ─── HARD 1: active axiom JSON parse ─────────────────────────────
cat("[1/6 HARD] active axiom JSON parse\n")
active_dir <- file.path(PROJ_ROOT, "qepm/memory/axioms/active")
# v8.0: mode-local(active/modes/<mode>/) 포함 recursive
active_files <- list.files(active_dir, pattern = "\\.json$", full.names = TRUE, recursive = TRUE)
active_data <- list()
for (f in active_files) {
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                error = function(e) {
                  add_hard("HARD_1_active_parse",
                           sprintf("%s parse fail: %s",
                                   basename(f), conditionMessage(e)))
                  NULL
                })
  if (!is.null(d)) active_data[[basename(f)]] <- d
}
cat(sprintf("  %d active JSON parsed\n\n", length(active_data)))

# ─── HARD 2: required metadata fields ────────────────────────────
cat("[2/6 HARD] active axiom required metadata\n")
required <- c("memory_id", "axiom_class", "authority",
              "review_policy", "enforcement_mode", "canonical_statement")
for (fn in names(active_data)) {
  d <- active_data[[fn]]
  missing <- required[!required %in% names(d)]
  if (length(missing) > 0) {
    add_hard("HARD_2_metadata_missing",
             sprintf("%s missing fields: %s",
                     fn, paste(missing, collapse = ",")))
  }
}
cat("  metadata check complete\n\n")

# ─── HARD 3: sot_map active ↔ documented ─────────────────────────
cat("[3/6 HARD] sot_map active ↔ documented\n")
sot_path <- file.path(PROJ_ROOT, "qepm/memory/axioms/axiom_sot_map.json")
if (!file.exists(sot_path)) {
  add_hard("HARD_3_sot_map_missing", "axiom_sot_map.json 부재")
} else {
  sot <- fromJSON(sot_path, simplifyVector = FALSE)
  documented_active_ids <- c()
  all_sot_ids <- c()
  for (ax in sot$axioms) {
    all_sot_ids <- c(all_sot_ids, ax$axiom_id)
    if (isTRUE(ax$documented_active)) {
      documented_active_ids <- c(documented_active_ids, ax$axiom_id)
    }
  }
  json_active_ids <- vapply(active_data, function(d) {
    safe_str(d$memory_id %||% d$axiom_id)
  }, character(1))
  missing_in_json <- setdiff(documented_active_ids, json_active_ids)
  # v8.0: mode-local(documented_active=FALSE이나 sot에 등록)은 통과 — sot 전체 레코드와 대조
  extra_in_json <- setdiff(json_active_ids, all_sot_ids)
  if (length(missing_in_json) > 0) {
    add_hard("HARD_3_sot_documented_missing_json",
             sprintf("documented active 중 JSON 부재: %s",
                     paste(missing_in_json, collapse = ",")))
  }
  if (length(extra_in_json) > 0) {
    add_hard("HARD_3_sot_json_not_documented",
             sprintf("JSON active 중 documented 부재: %s",
                     paste(extra_in_json, collapse = ",")))
  }
  cat(sprintf("  documented=%d, json=%d\n",
              length(documented_active_ids), length(json_active_ids)))
}
cat("\n")

# ─── HARD 4: deprecated/active duplicate memory_id+version ──────
cat("[4/6 HARD] deprecated/active duplicate memory_id+version\n")
dep_dir <- file.path(PROJ_ROOT, "qepm/memory/axioms/deprecated")
dep_files <- list.files(dep_dir, pattern = "\\.json$", full.names = TRUE)
dep_data <- list()
for (f in dep_files) {
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                error = function(e) NULL)
  if (!is.null(d)) dep_data[[basename(f)]] <- d
}
active_keys <- vapply(active_data, function(d) {
  sprintf("%s|%s",
          safe_str(d$memory_id %||% d$axiom_id),
          safe_str(d$version, "1"))
}, character(1))
for (fn in names(dep_data)) {
  d <- dep_data[[fn]]
  # Skip when deprecated explicitly notes superseded_by or scope_too_broad
  superseded <- safe_str(d$superseded_by, "")
  fname <- basename(fn)
  if (nzchar(superseded) || grepl("scope_too_broad|superseded|withdraw|rejection",
                                  fname, ignore.case = TRUE)) {
    next  # intentional in-place version replacement
  }
  k <- sprintf("%s|%s",
               safe_str(d$memory_id %||% d$axiom_id),
               safe_str(d$version, "1"))
  mid <- safe_str(d$memory_id %||% d$axiom_id, "")
  if (k %in% active_keys && nzchar(mid)) {
    add_hard("HARD_4_dep_active_dup",
             sprintf("%s memory_id+version duplicate in active: %s",
                     fn, k))
  }
}
cat("  duplicate check complete\n\n")

# ─── HARD 5: review.R --all without --apply 변경 감지 ───────────
cat("[5/6 HARD] review --all dry-run safety\n")
# git status check (simple)
old_wd <- getwd()
git_status <- tryCatch({
  setwd(PROJ_ROOT)
  system2("git", c("status", "--porcelain",
                   "qepm/memory/axioms/active"),
          stdout = TRUE)
}, error = function(e) structure(character(), class = "mkh_git_fail"),
   finally = setwd(old_wd))
# (2026-07-26 MKH-07 수리) git 실행 실패(git 부재·repo 손상)를 character() 로 흡수하면
#   modified_active 가 빈 벡터가 되어 **침묵 통과**했다 — 이 체크의 전제(작업트리 상태를
#   봤다)가 성립하지 않은 것이지 "깨끗하다"가 아니다. 실패를 이름으로 남긴다.
if (inherits(git_status, "mkh_git_fail")) {
  add_warn("HARD_5_git_unavailable",
           "git status 실행 실패 — active dir 변경 여부 미관측(깨끗함이 아님)")
  git_status <- character()
}
modified_active <- git_status[grepl("^.M", git_status)]
if (length(modified_active) > 0) {
  add_warn("HARD_5_active_uncommitted",
           sprintf("active dir uncommitted changes (%d files) — verify intent",
                   length(modified_active)))
}
cat("  review safety check complete\n\n")

# ─── HARD 6: promote helper compatibility selftest ──────────────
cat("[6/6 HARD] promote.R helper selftest\n")
helper_path <- file.path(PROJ_ROOT,
                         "02_Infrastructure/memory/memory_metadata_normalize.R")
if (!file.exists(helper_path)) {
  add_hard("HARD_6_helper_missing", "memory_metadata_normalize.R 부재")
} else {
  st_result <- tryCatch({
    source(helper_path, local = TRUE)
    test1 <- normalize_axiom_metadata(
      axiom = list(id = "AX-TEST", text = "test"),
      write = FALSE
    )
    required_fields <- c("memory_id", "memory_kind", "axiom_class",
                          "authority", "review_policy",
                          "enforcement_mode", "canonical_statement")
    if (!all(required_fields %in% names(test1))) {
      "missing required fields"
    } else if (test1$memory_id != "AX-TEST") {
      "fallback chain failed"
    } else if (test1$canonical_statement != "test") {
      "canonical fallback failed"
    } else {
      "PASS"
    }
  }, error = function(e) conditionMessage(e))

  if (st_result != "PASS") {
    add_hard("HARD_6_helper_selftest", st_result)
  } else {
    cat("  helper selftest PASS\n")
  }
}
cat("\n")

# ─── HARD 7: 세션(하네스) 메모리 존재 (2026-06-10 신설) ─────────────
# 배경: 메모리 전손(autoload 0/5) 상태에서 본 게이트가 PASS를 보고한 맹점 —
# axiom JSON 정합만 검사하고 정작 '세션 메모리'는 검사 대상이 아니었음.
cat("[7/7 HARD] 하네스 세션 메모리 존재\n")
harness_mem <- file.path(Sys.getenv("USERPROFILE", unset = "C:/Users/99922"),
                         ".claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory")
if (!dir.exists(harness_mem)) {
  add_hard("HARD_7_harness_memory_dir", sprintf("하네스 메모리 디렉토리 부재: %s — 세션 메모리 전손 의심 (2026-06-10 사건 재발)", harness_mem))
} else {
  mem_idx <- file.path(harness_mem, "MEMORY.md")
  if (!file.exists(mem_idx) || file.size(mem_idx) < 50) {
    add_hard("HARD_7_memory_index", "MEMORY.md 부재 또는 공백 — autoload 인덱스 단절")
  } else {
    cat(sprintf("  하네스 메모리 OK (%d files, MEMORY.md %dB)\n",
                length(list.files(harness_mem)), file.size(mem_idx)))
  }
}
cat("\n")

# ─── WARN 1: L-code corpus 무결성 ────────────────────────────────
# 2026-07-25 교체 (도훈 승인). 구 지표 = `lcode_corpus_methodology.json` 의 gap>50 outlier.
# 폐기 사유: 그 코퍼스는 정본(414건)이 아니라 **Lawbook 마크다운에 인용된 L-code 27건**을
# 긁어모은 부분 추출물이라, 그 안의 번호 간격(L-25→L-123, L-192→L-244)은 번호체계 무결성이
# 아니라 **문서 인용 희소성**을 잰다. 게다가 현 ID 체계는 L-AS-*/L-RAMP-* 등 modern 형식이
# 섞여 "간격" 자체가 정의되지 않는다 → 어떤 코퍼스로 바꿔도 의미가 서지 않음.
# 교체 지표 = 코퍼스가 아티팩트를 충실히 반영하는가의 두 축(둘 다 이번 세션 실측 결함):
#   ① 중복 ID — 서로 다른 기록이 같은 번호(2026-07-25 실측 5건). 인용 오링크 유발
#      (knowledge_recheck_queue 의 DIST-QPM-001 "L-160 ID 재발급 오링크"가 그 사례).
#      생산자 측 가드(lcode_emit.R 교차전략 stop())와 짝을 이루는 사후 검출기.
#   ② 미수확 아티팩트 — 디스크에 lesson 은 있으나 ID 부재 등으로 코퍼스에 못 들어간 기록
#      (2026-07-25 실측 87건 → 적립 후 0). 침묵 유실의 직접 지표.
# 판정 불차단(WARN) — AX-000/INV-7 정합.
cat("[W1/6] L-code corpus 무결성 (중복 ID · 미수확 아티팩트)\n")
corpus_path <- file.path(PROJ_ROOT, ".cache/lcode_corpus.json")
if (!file.exists(corpus_path)) {
  add_warn("WARN_1_lcode_corpus_missing", "lcode_corpus.json 부재")
} else {
  corpus <- fromJSON(corpus_path, simplifyVector = FALSE)
  entries <- corpus$lcodes
  if (is.null(entries)) entries <- list()
  ids <- vapply(entries, function(e) as.character(e$l_code %||% ""), character(1))
  ids <- ids[nzchar(ids)]
  dup_tab <- table(ids)
  dup_ids <- names(dup_tab)[dup_tab >= 2L]

  # 미수확: 디스크 아티팩트 중 코퍼스 source_file 집합에 없는 것 (superseded 제외)
  src <- vapply(entries, function(e) gsub("\\\\", "/", as.character(e$source_file %||% "")),
                character(1))
  art <- c(Sys.glob(file.path(PROJ_ROOT, "stage_artifacts/l_code_*.json")),
           Sys.glob(file.path(PROJ_ROOT, "stage_artifacts/l_code/*/l_code_*.json")),
           Sys.glob(file.path(PROJ_ROOT,
                              "04_Research/strategies/*/stage_artifacts/[Ll]_code*.json")))
  # 경로 접두 제거는 고정문자열로 (PROJ_ROOT 를 정규식화하면 드라이브/괄호에서 깨진다)
  root_fwd <- paste0(gsub("\\\\", "/", PROJ_ROOT), "/")
  art_rel <- sub(root_fwd, "", gsub("\\\\", "/", art), fixed = TRUE)
  art_rel <- art_rel[!grepl("/superseded/", art_rel, fixed = TRUE)]
  unharvested <- setdiff(art_rel, src)

  msgs <- character(0)
  if (length(dup_ids) > 0)
    msgs <- c(msgs, sprintf("중복 ID %d건(%s)", length(dup_ids),
                            paste(head(dup_ids, 6), collapse = ",")))
  if (length(unharvested) > 0)
    msgs <- c(msgs, sprintf("미수확 아티팩트 %d건(%s)", length(unharvested),
                            paste(basename(head(unharvested, 4)), collapse = ",")))
  if (length(msgs) > 0) {
    add_warn("WARN_1_lcode_corpus_integrity",
             sprintf("%s — 코퍼스가 아티팩트를 충실히 반영하지 못함", paste(msgs, collapse = " · ")))
  } else {
    cat(sprintf("  무결 (코퍼스 %d건 · 고유 ID %d · 미수확 0)\n",
                length(entries), length(unique(ids))))
  }
}

# ─── WARN 2: stale candidate 90+ days ────────────────────────────
cat("[W2/6] stale candidate 90+ days\n")
cand_dir <- file.path(PROJ_ROOT, "qepm/memory/axioms/candidates")
cand_files <- list.files(cand_dir, pattern = "\\.json$", full.names = TRUE)
threshold <- Sys.time() - as.difftime(90, units = "days")
stale_count <- 0
undated_count <- 0   # (2026-07-26 MKH-06) created_at 결측/파손 → mtime 폴백으로 산정한 건수
for (f in cand_files) {
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d)) next
  # (2026-07-26 MKH-06 수리) 구현은 parse 실패 시 Sys.time() 을 대입해 **무조건 신선**으로
  #   판정했고(측정 불가 = 신선), created_at 필드가 아예 없는 후보는 nchar()>0 게이트에
  #   걸려 **영구 미검사**였다(실물: CAND_20260714_alpha_research_distress_smallcap_wall_*
  #   — 90일이 지나도 절대 stale 로 안 잡힘). '측정 불가 = mtime 정직 폴백' 으로 교체
  #   (W8/W9 의 .lc_research_time 과 동일 원칙).
  created <- d$created_at %||% ""
  ct <- NA
  if (nchar(created) > 0) ct <- tryCatch(as.POSIXct(created), error = function(e) NA)
  if (is.na(ct)) {
    ct <- tryCatch(file.info(f)$mtime, error = function(e) NA)
    if (!is.na(ct)) undated_count <- undated_count + 1
  }
  if (!is.na(ct) && ct < threshold) stale_count <- stale_count + 1
}
if (stale_count > 0) {
  add_warn("WARN_2_stale_candidate",
           sprintf("%d candidates older than 90 days%s", stale_count,
                   if (undated_count > 0)
                     sprintf(" (그중 %d건은 created_at 결측 → mtime 기준)", undated_count) else ""))
} else {
  cat(sprintf("  no stale candidates%s\n",
              if (undated_count > 0)
                sprintf(" (created_at 결측 %d건은 mtime 으로 산정 — 구판은 영구 미검사)",
                        undated_count) else ""))
}

# ─── WARN 3: review_log schema variant ───────────────────────────
cat("[W3/6] review_log schema variant\n")
rl_dir <- file.path(PROJ_ROOT, "qepm/memory/axioms/review_log")
rl_files <- list.files(rl_dir, pattern = "\\.json$", full.names = TRUE,
                       recursive = FALSE)
schemas <- character(0)
for (f in rl_files) {
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d)) next
  schemas <- c(schemas, paste(sort(names(d)), collapse = ","))
}
# 2026-07-25: "키셋 종류 수"는 스키마 드리프트의 대리지표로 부적합 — 실측 23종 중
# 20종이 **1건짜리 일회성 문서**(AX-005/006/007 리뷰 도시에·CAND 제안·calibration 초안)로,
# 고정 스키마를 기대할 대상이 아니다. 반복 발생 스키마(≥2건)만이 드리프트 신호다.
#   실측: 반복 3종(게이트로그 274 · 그 선행형 10 · 파이프라인 스냅샷 5) + 싱글턴 20.
# ★이 검사가 놓치고 있던 진짜 손상은 키셋 수가 아니라 **소비자-생산자 필드명 불일치**였다
#   (search/build_index.R 이 created_at 조회 → 309건 중 299건 timestamp 유실, 2026-07-25 수리).
#   그 부류는 소비자 측 자기진단으로 잡는다(build_index 의 timestamp 커버리지 경고).
tab <- table(schemas)
recurring <- sum(tab >= 2L)
singletons <- sum(tab == 1L)
if (recurring > 10) {
  add_warn("WARN_3_review_log_variants",
           sprintf("review_log 반복 스키마 %d종 (권고 < 10) — 싱글턴 %d건은 제외 계상",
                   recurring, singletons))
} else {
  cat(sprintf("  반복 스키마 %d종 (권고 <10) · 싱글턴 일회성 문서 %d건 · 총 파일 %d\n",
              recurring, singletons, length(schemas)))
}

# ─── INFO 4: external memory not indexed (격하) ──────────────────
cat("[I4/6] external memory indexed\n")
# (2026-07-26 MKH-08 수리) Linux 절대경로 하드코딩 — Windows R 에서 dir.exists 항상 FALSE
#   → 매 실행 "skip" 상수 출력으로 **영구 무기능**이었고 r-portability 금칙 ③(선행 / 경로
#   하드코딩) 위반이다. 환경변수 경유로 전환하고, 미설정을 '없음' 이 아니라 '미설정' 으로 표기.
external_base <- Sys.getenv("QVEST_EXTERNAL_MEMORY_DIR", "")
if (!nzchar(external_base)) {
  cat("  external memory: 미설정 (QVEST_EXTERNAL_MEMORY_DIR 미지정 — 검사 대상 없음)\n")
} else if (dir.exists(external_base)) {
  ext_count <- length(list.files(external_base, pattern = "\\.md$"))
  add_info("INFO_4_external_memory_excluded",
           sprintf("external memory %d files — opt-in via --include-claude-memory",
                   ext_count))
} else {
  cat("  external base not found (skip)\n")
}

# ─── WARN 5: enforcement claim ↔ hook 실제 강제력 ────────────────
cat("[W5/6] enforcement claim vs hook strength\n")
hook_path <- file.path(PROJ_ROOT,
                       "02_Infrastructure/hooks/axiom_enforcement_hook.sh")
unverified <- c()
# (2026-07-26 MKH-03 수리) 루프 안 file.exists(hook_path) 에 else 가 없어, 강제 훅이
#   삭제/이동되면 unverified 가 빈 채로 남고 "enforcement claims aligned" 가 출력됐다 —
#   **검사 대상 소멸 = 검사 통과**(최악 상태가 warn=0 으로 위장). 선행 판정으로 분리.
if (!file.exists(hook_path)) {
  add_warn("WARN_5_hook_missing",
           "axiom_enforcement_hook.sh 부재 — enforcement 정렬 검증 불가(정렬됨이 아님)")
}
for (fn in names(active_data)) {
  d <- active_data[[fn]]
  mode <- safe_str(d$enforcement_mode, "")
  ax_id <- safe_str(d$memory_id %||% d$axiom_id, "")
  if (mode %in% c("block", "advisory")) {
    if (file.exists(hook_path)) {
      hook_content <- readLines(hook_path, warn = FALSE)
      if (!any(grepl(ax_id, hook_content, fixed = TRUE))) {
        unverified <- c(unverified, ax_id)
      }
    }
  }
}
if (length(unverified) > 0) {
  add_warn("WARN_5_enforcement_unverified",
           sprintf("enforcement_mode block/advisory but not in hook: %s",
                   paste(unverified, collapse = ",")))
} else {
  cat("  enforcement claims aligned\n")
}

# ─── WARN 6: regime_validation parse + cache STALE ───────────────
cat("[W6/6] regime_validation + cache_core sync\n")
rv_path <- file.path(PROJ_ROOT, "qepm/memory/regime_validation/soft_mrs.json")
if (file.exists(rv_path)) {
  if (file.info(rv_path)$size == 0) {
    # [v8.0 fix 2026-05-29 B5] 0-byte orphan (writer 부재 2026-04-08~, regime_signal.R 미참조 → fallback 작동).
    # parse-fail WARN 오탐 제거. disposition(삭제/feature 복구)는 별도. 구 run_all.R 참조 위해 파일 retain.
    cat("  soft_mrs.json 0-byte orphan (writer 부재, regime fallback 작동) — N/A skip\n")
  } else {
    d <- tryCatch(fromJSON(rv_path, simplifyVector = FALSE),
                  error = function(e) conditionMessage(e))
    if (is.character(d)) {
      add_warn("WARN_6_regime_validation_parse",
               sprintf("soft_mrs.json parse fail: %s", d))
    } else {
      cat("  soft_mrs.json parse OK\n")
    }
  }
}
cache_path <- file.path(PROJ_ROOT, ".cache/axiom_core.json")
if (file.exists(cache_path)) {
  # (2026-07-26 MKH-04 수리) parse 실패 시 NULL → if 블록 통째 skip → 경고 0.
  #   손상 캐시는 STALE 보다 나쁜 상태(agent prefix 주입 소스 전손)인데 가장 심한 케이스가
  #   비관측이었다. 손상을 명시 경고로 승격.
  cache <- tryCatch(fromJSON(cache_path, simplifyVector = FALSE),
                    error = function(e) structure(list(), class = "mkh_cache_corrupt"))
  if (inherits(cache, "mkh_cache_corrupt")) {
    add_warn("WARN_6_cache_core_corrupt",
             ".cache/axiom_core.json parse 실패(손상) — STALE 보다 심각, bootstrap 재생성 필요")
  }
  if (!inherits(cache, "mkh_cache_corrupt") && !is.null(cache)) {
    cache_ids <- vapply(cache$axioms, function(x) safe_str(x$id),
                        character(1))
    json_ids <- vapply(active_data, function(d) {
      safe_str(d$memory_id %||% d$axiom_id)
    }, character(1))
    cache_diff <- setdiff(json_ids, cache_ids)
    if (length(cache_diff) > 0) {
      add_warn("WARN_6_cache_core_stale",
               sprintf(".cache/axiom_core.json STALE — missing: %s (regenerate via bootstrap)",
                       paste(cache_diff, collapse = ",")))
    }
  }
}

# WARN_7: Stop hook script ↔ settings.json 등록 정합 (L-314 follow-up — L-275 silent fail 재발 방지)
# (2026-07-13 task#54-3ⓒ) 기대목록을 현행 Stop hook 4건으로 갱신 — 구 패턴
# ^auto_(commit|push)_on_stop\.sh$ 은 performance_realmeasure_gate(2026-06-17)·
# research_continuity_guard(2026-07-13) 등록누락을 감지하지 못했음. 양방향 검사:
# (a) FS 존재 + settings 미등록 → WARN (L-275 silent fail) / (b) 기대 스크립트 FS 부재 → WARN
# (settings에 등록돼 있어도 파일이 없으면 || true 로 조용히 무력화되는 동형 패턴).
cat("[W7] Stop hook script ↔ settings.json registration consistency\n")
stop_hook_dir <- file.path(PROJ_ROOT, "02_Infrastructure/hooks")
expected_stop_hooks <- c("auto_commit_on_stop.sh",
                         "auto_push_on_stop.sh",
                         "performance_realmeasure_gate.sh",
                         "research_continuity_guard.sh")
settings_path <- file.path(PROJ_ROOT, ".claude/settings.json")
if (file.exists(settings_path)) {
  settings_content <- paste(readLines(settings_path, warn = FALSE),
                            collapse = "\n")
  unregistered <- character()
  fs_missing <- character()
  for (script in expected_stop_hooks) {
    on_fs <- file.exists(file.path(stop_hook_dir, script))
    in_settings <- grepl(script, settings_content, fixed = TRUE)
    if (on_fs && !in_settings) unregistered <- c(unregistered, script)
    if (!on_fs) fs_missing <- c(fs_missing, script)
  }
  if (length(unregistered) > 0) {
    add_warn("WARN_7_stop_hook_unregistered",
             sprintf("Stop hook script(s) exist but not registered in settings.json: %s — L-275 silent fail pattern",
                     paste(unregistered, collapse = ", ")))
  }
  if (length(fs_missing) > 0) {
    add_warn("WARN_7_stop_hook_script_missing",
             sprintf("expected Stop hook script(s) missing on FS: %s — settings 등록만 남은 무력화 상태",
                     paste(fs_missing, collapse = ", ")))
  }
  if (length(unregistered) == 0 && length(fs_missing) == 0) {
    cat(sprintf("  %d expected Stop hook(s) present + registered in settings.json: OK\n",
                length(expected_stop_hooks)))
  }
} else {
  add_warn("WARN_7_settings_missing", ".claude/settings.json 부재 — Stop hook 등록 검증 불가")
}

# WARN_8 (2026-07-13 task#54-3ⓐ): layer_bottleneck_map.md 신선도 — 최신 L-code 대비 24h+ 뒤처짐.
# 배경: 신선도 사슬 구조 감사 — 병목지도가 L-code 적립을 따라가지 못하면 프론티어 판단이
# stale 지도 위에서 이뤄짐 (corpus 정체와 동형의 지식환류 단절).
# ── 공유 헬퍼 (2026-07-25): L-code 의 "연구 시각" = created_at, 파일 mtime 아님 ────────
# 구 구현(W8·W9 공통)은 연구 최신성을 파일 타임스탬프로 대리했다. 그 결과
#   ① 기존 기록을 구조적으로 손대기만 해도(next_probe 소급 구조화·ID 병합·재발급)
#      W8은 지도 stale 오탐, W9는 "최근 7일 negative"로 오탐 — 후자는 없던 next_probe를
#      **소급 창작하도록 압박**하므로 지식 날조 위험까지 있다.
#   ② 반대로 mtime 이 오래된 신규 L-code 는 양쪽 다 놓친다.
# created_at 부재 기록만 mtime 폴백(정직 원장 — 판정 자체는 불차단, AX-000/INV-7 정합).
.lc_research_time <- function(f) {
  ca <- tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE)$created_at,
                 error = function(e) NULL)
  ts <- suppressWarnings(as.POSIXct(sub("T", " ", sub("Z$", "", ca %||% NA_character_)),
                                    tz = "", optional = TRUE))
  if (is.null(ca) || is.na(ts)) file.info(f)$mtime else ts
}

# ── map_freshness_v1 (2026-08-20): 대리지표(mtime) → 표 본문 내용 대조 ────────────────
# 왜: 구 W8/W3 은 layer_bottleneck_map.md 의 **mtime** 을 최신 L-code 시각과 비교했다.
#   mtime 은 append 만으로 갱신되므로, 지도를 touch 하거나 헤더 `**갱신**:` 줄을 한 줄
#   덧붙이기만 해도 두 감시기가 모두 초록이 됐다. 실측(git 이력에서 표 본문 sha 추적):
#     · 표 본문 sha 660f1ce393  2026-08-09 12:49 → 08-17 16:48  = 8일 동안 바이트 동일,
#       그 사이 이 파일을 건드린 커밋 20건 (mtime 은 계속 최신)
#     · 직전 정체 174f763b12   2026-07-19 13:44 → 08-02 20:32  = 14일 / 16커밋
#   ⇒ 신선도의 정의를 "파일이 만져졌는가" 에서 "판정이 담긴 표 본문이 바뀌었는가" 로 교체.
#
# 규약(두 구현이 반드시 동일해야 하는 4요소):
#   ① 해시 대상 = 지도 파일에서 `|` 로 시작하는 줄 중 구분선(`|---|---|`)을 제외한 전부.
#      → 계층 표 9행 + 계층 표 헤더 + 재료 표 3행 + 재료 표 헤더 = 실측 14행.
#      → **제외**: 제목/목적 문단, `**갱신**: vNN` 버전 체인, `> ` 인용 갱신 이력 블록,
#        부기 문단, "갱신 규약"/"갭 귀속 결론" 절. 전부 append 로 증식하는 표면이라
#        포함하면 대리지표 성질이 그대로 재발한다.
#   ② 해시 = sha256(paste(rows, collapse="\n") 의 UTF-8 바이트). R digest 와 python
#      hashlib 이 동일 값을 내는 것을 실측 확인(dcc8992e7f… , 16130 bytes).
#   ③ 스냅샷 = .cache/layer_bottleneck_map_content.json {schema, table_sha, n_rows, observed_at}.
#      observed_at = 그 table_sha 를 **처음 관측한 시각**(= 내용이 바뀐 시각의 상한).
#      스냅샷 부재 시 최초 1회는 생성만 하고 경보하지 않는다(초기화 오탐 방지 — 이때
#      observed_at=now 이므로 lag_h<=0 이 되어 자연히 무경보).
#   ④ 임계 = 24h (구 W8 과 동일). W3 은 여기에 자기 발화 범위(최근 6h 내 L-code 적립)만 곱한다.
# 폴백(회귀 없음): 표 추출 0행 / 스냅샷 read·write 불가 → basis="mtime" 으로 **구 판정 그대로**
#   수행하고 폴백 사실을 경고로 남긴다. 조용히 죽거나 무조건 통과시키지 않는다.
.MF_SCHEMA   <- "map_freshness_v1"
.MF_THRESH_H <- 24

.mf_table_rows <- function(map_path) {
  ln <- tryCatch(readLines(map_path, warn = FALSE, encoding = "UTF-8"),
                 error = function(e) character(0))
  ln <- sub("[\r\n]+$", "", ln)
  rows <- ln  # MUT-M3: 표 본문이 아니라 파일 전체를 해시
  rows[!grepl("^\\|[[:space:]:|-]+\\|[[:space:]]*$", rows)]
}

# sha256 은 digest → openssl 순으로 시도. 둘 다 없으면 NULL (→ 호출자가 mtime 폴백).
.mf_table_sha <- function(rows) {
  blob <- charToRaw(paste(rows, collapse = "\n"))
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(blob, algo = "sha256", serialize = FALSE))
  }
  if (requireNamespace("openssl", quietly = TRUE)) {
    return(as.character(openssl::sha256(blob)))
  }
  NULL
}

.mf_snapshot_path <- function(proj_root) {
  file.path(proj_root, ".cache", "layer_bottleneck_map_content.json")
}

# 스냅샷을 현재 표 해시와 대조/갱신하고 observed_at(초, epoch)을 돌려준다.
# 실패 시 NULL (→ 호출자가 mtime 폴백).
.mf_observed_at <- function(proj_root, table_sha, n_rows, now_s = as.numeric(Sys.time())) {
  snap_p <- .mf_snapshot_path(proj_root)
  prev <- tryCatch(jsonlite::fromJSON(snap_p, simplifyVector = TRUE),
                   error = function(e) NULL, warning = function(w) NULL)
  ok_prev <- !is.null(prev) && identical(as.character(prev$schema %||% ""), .MF_SCHEMA) &&
             is.character(prev$table_sha %||% NULL) && is.finite(suppressWarnings(as.numeric(prev$observed_at %||% NA)))
  if (ok_prev && identical(as.character(prev$table_sha), table_sha)) {
    return(as.numeric(prev$observed_at))
  }
  # 최초 생성 또는 내용 변경 → 지금을 관측 시각으로 기록(원자적 쓰기).
  written <- tryCatch({
    dir.create(dirname(snap_p), showWarnings = FALSE, recursive = TRUE)
    tmp <- paste0(snap_p, ".tmp", Sys.getpid())
    jsonlite::write_json(list(schema = .MF_SCHEMA, table_sha = table_sha,
                              n_rows = as.integer(n_rows), observed_at = now_s,
                              observed_at_iso = format(as.POSIXct(now_s, origin = "1970-01-01"),
                                                       "%Y-%m-%dT%H:%M:%S")),
                         tmp, auto_unbox = TRUE)
    file.rename(tmp, snap_p)
  }, error = function(e) FALSE)
  if (!isTRUE(written)) return(NULL)
  now_s
}

# 정본 판정. 반환: list(basis, stale, lag_h, table_sha, n_rows, reason)
.mf_judge <- function(proj_root, map_path, newest_lc_time) {
  newest_s <- as.numeric(newest_lc_time)
  mtime_lag <- function() as.numeric(difftime(as.POSIXct(newest_s, origin = "1970-01-01"),
                                              file.info(map_path)$mtime, units = "hours"))
  rows <- .mf_table_rows(map_path)
  if (length(rows) == 0) {
    lag_h <- mtime_lag()
    return(list(basis = "mtime", stale = isTRUE(is.finite(lag_h) && lag_h > .MF_THRESH_H),
                lag_h = lag_h, table_sha = NA_character_, n_rows = 0L,
                reason = "표 본문 추출 0행 (지도 형식 변경 의심)"))
  }
  sha <- .mf_table_sha(rows)
  if (is.null(sha)) {
    lag_h <- mtime_lag()
    return(list(basis = "mtime", stale = isTRUE(is.finite(lag_h) && lag_h > .MF_THRESH_H),
                lag_h = lag_h, table_sha = NA_character_, n_rows = length(rows),
                reason = "sha256 해시 구현 부재 (digest/openssl 미설치)"))
  }
  obs <- .mf_observed_at(proj_root, sha, length(rows))
  if (is.null(obs)) {
    lag_h <- mtime_lag()
    return(list(basis = "mtime", stale = isTRUE(is.finite(lag_h) && lag_h > .MF_THRESH_H),
                lag_h = lag_h, table_sha = sha, n_rows = length(rows),
                reason = "스냅샷 read/write 불가 (.cache/layer_bottleneck_map_content.json)"))
  }
  lag_h <- (newest_s - obs) / 3600
  list(basis = "content", stale = isTRUE(is.finite(lag_h) && lag_h > .MF_THRESH_H),
       lag_h = lag_h, table_sha = sha, n_rows = length(rows), reason = NA_character_)
}

cat("[W8] layer_bottleneck_map freshness vs newest L-code\n")
lbm_path <- file.path(PROJ_ROOT, "06_Registry/layer_bottleneck_map.md")
# (2026-07-26 MKH-05 수리) W8/W9 는 루트 stage_artifacts 만 glob 했으나 W1(:280-283)과
#   harvester 정본 스캔범위(CLAUDE.md)는 04_Research/strategies/*/stage_artifacts/ 도 포함.
#   QEPM 모드가 전략 디렉토리에 emit 한 negative L-code 는 next_probe 검사·최신성 기준에서
#   **영구 비가시**였다(구조적 블라인드 = warn 0). W1 과 같은 3-glob 으로 통일.
raw_lc_files <- c(Sys.glob(file.path(PROJ_ROOT, "stage_artifacts/l_code/*/l_code_*.json")),
                  Sys.glob(file.path(PROJ_ROOT, "stage_artifacts/l_code_*.json")),
                  Sys.glob(file.path(PROJ_ROOT,
                             "04_Research/strategies/*/stage_artifacts/[Ll]_code*.json")))
raw_lc_files <- raw_lc_files[!grepl("/superseded/", raw_lc_files, fixed = TRUE)]
if (length(raw_lc_files) == 0) {
  cat("  L-code 원본 파일 없음 — skip\n")
} else {
  newest_lc_mt <- suppressWarnings(max(do.call(c, lapply(raw_lc_files, .lc_research_time)),
                                       na.rm = TRUE))
  if (!file.exists(lbm_path)) {
    add_warn("WARN_8_bottleneck_map_missing",
             "06_Registry/layer_bottleneck_map.md 부재 — 병목지도 현행화 필요")
  } else {
    lbm_fresh <- .mf_judge(PROJ_ROOT, lbm_path, newest_lc_mt)
    if (identical(lbm_fresh$basis, "content")) {
      if (isTRUE(lbm_fresh$stale)) {
        add_warn("WARN_8_bottleneck_map_stale",
                 sprintf(paste0("layer_bottleneck_map.md **표 본문**이 최신 L-code보다 %.1fh 뒤처짐 ",
                                "(임계 24h · basis=content · table_sha=%s · %d행) — ",
                                "mtime 갱신·헤더 부기로는 해소되지 않습니다. 계층 행·갭 귀속을 갱신하세요."),
                         lbm_fresh$lag_h, substr(lbm_fresh$table_sha, 1, 10), lbm_fresh$n_rows))
      } else {
        cat(sprintf("  bottleneck map fresh (표 본문 기준 lag %.1fh <= 24h, sha=%s, %d행)\n",
                    max(lbm_fresh$lag_h, 0), substr(lbm_fresh$table_sha, 1, 10), lbm_fresh$n_rows))
      }
    } else {
      # 폴백: 내용 대조 불가 → 구 mtime 판정 그대로 + 폴백 사실 자체를 경고로 남김.
      add_warn("WARN_8_bottleneck_map_basis_fallback",
               sprintf("layer_bottleneck_map 신선도가 내용 대조 불가로 mtime 폴백 (사유: %s) — 검사 약화 상태",
                       lbm_fresh$reason))
      if (isTRUE(lbm_fresh$stale)) {
        add_warn("WARN_8_bottleneck_map_stale",
                 sprintf("layer_bottleneck_map.md가 최신 L-code보다 %.1fh 뒤처짐 (임계 24h · basis=mtime 폴백) — 병목지도 현행화 필요",
                         lbm_fresh$lag_h))
      } else {
        cat(sprintf("  bottleneck map fresh (mtime 폴백 lag %.1fh <= 24h)\n", max(lbm_fresh$lag_h, 0)))
      }
    }
  }
}

# WARN_9 (2026-07-13 task#54-3ⓑ): 최근 7일 negative performance L-code(C/F) next_probe 부재.
# AX-000 탐색 연속성 — 실패지식이 "다음 탐침" 없이 적립되면 dead-end 라벨과 기능적으로
# 동일해짐 (research_continuity_guard의 L-code 레벨 등가물).
cat("[W9] recent negative L-code next_probe presence\n")
np_cutoff <- Sys.time() - as.difftime(7, units = "days")
missing_np <- character(0)
n_recent_neg <- 0L
for (f in raw_lc_files) {
  # 2026-07-25: mtime → created_at (W8과 동일 교정, 공유 헬퍼).
  # 구 기준은 04월 기록을 병합·재발급으로 손대기만 해도 "최근 7일"로 잡아
  # next_probe 소급 창작을 압박했다 (L-160/L-166/L-1682 실사례).
  mt <- .lc_research_time(f)
  if (is.na(mt) || mt < np_cutoff) next
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d)) next
  g <- toupper(trimws(safe_str(d$grade, "")))
  if (!nzchar(g) || g == "?" || !(g %in% c("C", "F", "REJECT"))) next
  n_recent_neg <- n_recent_neg + 1L
  np_txt <- trimws(paste(unlist(d$next_probe), collapse = " "))
  if (!nzchar(np_txt)) {
    missing_np <- c(missing_np, safe_str(d$l_code, basename(f)))
  }
}
if (length(missing_np) > 0) {
  shown <- head(missing_np, 8)
  add_warn("WARN_9_negative_lcode_no_next_probe",
           sprintf("최근 7일 negative(C/F) L-code %d/%d건 next_probe 부재: %s%s — 실패 기록에 다음 탐침 명시 필요 (AX-000 탐색 연속성)",
                   length(missing_np), n_recent_neg, paste(shown, collapse = ","),
                   if (length(missing_np) > 8) sprintf(" 외 %d건", length(missing_np) - 8) else ""))
} else {
  cat(sprintf("  최근 7일 negative L-code %d건 전부 next_probe 보유 (또는 해당 없음)\n",
              n_recent_neg))
}

# ─── Summary ─────────────────────────────────────────────────────
cat("\n=== SUMMARY ===\n")
cat(sprintf("Hard fails: %d\n", length(hard_fails)))
cat(sprintf("Warnings:   %d\n", length(warnings_list)))
cat(sprintf("Infos:      %d\n", length(infos)))

# Write report
out_dir <- file.path(PROJ_ROOT, "qepm/observability")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
report <- list(
  schema_version = "v7.2.1_memory_health",
  ran_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hard_fails = hard_fails,
  warnings = warnings_list,
  infos = infos,
  summary = list(
    hard_fail_count = length(hard_fails),
    warning_count = length(warnings_list),
    info_count = length(infos),
    overall = if (length(hard_fails) == 0) "PASS" else "FAIL"
  )
)
out_path <- file.path(out_dir, "memory_health_latest.json")
write_json(report, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\nReport: %s\n", out_path))

quit(status = if (length(hard_fails) == 0) 0 else 1)
