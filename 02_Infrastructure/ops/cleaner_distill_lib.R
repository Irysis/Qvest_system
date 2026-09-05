#==============================================================================
# cleaner_distill_lib.R — 무인 증류 레인의 **기계 절반** (2026-09-05 도훈 지시)
#
# 왜 생겼나:
#   주간 스윕(weekly_cleaner_sweep.R)은 매주 재료만 쌓고 status="awaiting_distill" 로
#   멈췄고, 증류는 다음 대화 세션의 /cleaner 가 하기로 되어 있었다. 그 세션이 3주 안 왔다
#   (마지막 digest 2026-08-15) — pending_5axis 백로그가 49건(07-17) → 104건(09-05)이 됐다.
#   2026-08-30 "모든 작업을 무인화" 지시와 2026-07-04 "증류 자동화 금지" 가 충돌하는 지점이며,
#   도훈이 2026-09-05 무인화 쪽으로 정합을 지시했다(삭제 판단 포함 = 전면 무인).
#
# 역할 분담 (이 파일이 지키는 경계):
#   에이전트(claude -p)  = **무엇을** 증류하고 **무엇을** 지울지 판단한다.
#   이 파일(기계)        = 판단을 받아 **재도출로 검증하고 집행**한다.
#   → "검증은 기계가 재도출한다 — 에이전트 진술은 근거가 아니다"(rf_b1_design 규율 승계).
#     에이전트가 "참조 없음" 이라 적어도 git grep 을 여기서 다시 돌린다.
#
# 서브커맨드:
#   gate                  — 착수 가능 판정. exit 0=go / 10=할 일 없음 / 11=충돌(연기) / 12=꺼짐
#   materials <out.txt>   — 에이전트 프롬프트에 붙일 재료 조립 (pending·DIST백로그·삭제후보·방화벽)
#   apply <result.json>   — 에이전트 산출 검증 + 집행 (DIST 초안·L-code·삭제·매니페스트)
#
# 소비: 02_Infrastructure/ops/cleaner_distill_run.sh
# 규칙 SOT: .claude/skills/cleaner/SKILL.md · 02_Infrastructure/docs/rules/artifact-storage.md §8
#==============================================================================

suppressWarnings(suppressMessages(library(jsonlite)))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L ||
                            (length(a) == 1L && is.na(a))) b else a

# ── 경로 해석 (weekly_cleaner_sweep.R 동일 패턴 — normalizePath 미사용) ───────────
#   ★QVEST_CD_ROOT 가 최우선인 이유: **QM_ROOT 로는 자식 R 프로세스를 격리할 수 없다**
#     (~/.Renviron 이 이긴다 — 2026-09-04 실측. 임시 root 를 쓴다고 믿은 검사가 공유 원장을
#     보고 있었다). 검사가 격리 사본을 쓰려면 전용 변수가 있어야 한다.
.cd_root <- function() {
  v0 <- Sys.getenv("QVEST_CD_ROOT", "")
  if (nzchar(v0) && dir.exists(v0)) return(sub("/+$", "", gsub("\\\\", "/", v0)))
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && dir.exists(v)) return(sub("/+$", "", gsub("\\\\", "/", v)))
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (dir.exists(cand)) return(cand)
  sub("/+$", "", gsub("\\\\", "/", getwd()))
}
ROOT <- .cd_root()

.cd_read_json <- function(path, default = NULL) {
  if (!file.exists(path)) return(default)
  tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) default)
}

# ── 설정 (무인 레인 정본 = reinforce_auto_config.json — 레인마다 설정 파일을 만들면
#    한 곳을 꺼도 나머지가 도는 rf_llm_env.sh 가 고친 그 병이 재발한다) ──────────────
.cd_cfg <- function() {
  p <- Sys.getenv("QVEST_RF_CONFIG", file.path(ROOT, "06_Registry/reinforce_auto_config.json"))
  cfg <- .cd_read_json(p, list())
  cfg$cleaner_distill %||% list()
}

.cd_protected <- function() {
  p <- Sys.getenv("QVEST_CLEANER_PROTECTED",
                  file.path(ROOT, "06_Registry/cleaner_protected_paths.json"))
  pr <- .cd_read_json(p, NULL)
  # ★목록 파일이 없거나 깨졌으면 **삭제를 통째로 끈다**. 보호 목록의 부재를
  #   "보호할 게 없다" 로 읽으면 그 순간이 최대 위험이다(빈 기본값 금지).
  if (is.null(pr) || !length(pr$absolute_preserve %||% list()))
    return(list(broken = TRUE))
  pr$broken <- FALSE
  pr
}

.cd_pending_path <- function() file.path(ROOT, ".cache", "cleaner_pending.json")

# ── jsonl 이벤트 로그 (b1_design 과 같은 싱크 규약 — 검사가 운영 로그를 오염 못 하게 분리) ──
.cd_jlog <- function(event, ...) {
  jl <- Sys.getenv("QVEST_CD_JLOG", file.path(ROOT, ".cache", "cleaner_distill_log.jsonl"))
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                event = event, src = "cleaner_distill"), list(...))
  try({
    dir.create(dirname(jl), showWarnings = FALSE, recursive = TRUE)
    cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = jl, append = TRUE)
  }, silent = TRUE)
  invisible(NULL)
}

#==============================================================================
# gate — 착수 가능 판정
#
#   ★2계층 충돌 회피가 이 함수의 존재 이유다 (도훈 2026-09-05 "2계층 리서치 프로세스와
#     운용상 충돌없게"). Qvest_ReinforceAutoLoop 은 ~20분마다 돌고 그 안에서 강화 칸
#     5개 + LLM 레인 3종을 띄운다. 주간 클리너는 토 09:00 — 정면으로 겹친다.
#   충돌 시 **연기**이지 취소가 아니다: pending 은 그대로 남고 morning_run 의 일간
#     재시도 훅이 다음 날 다시 집는다. 한 주를 통째로 잃지 않는다.
#==============================================================================
cd_gate <- function() {
  cfg <- .cd_cfg()
  out <- function(go, reason, exit, ...) {
    v <- c(list(go = go, reason = reason), list(...))
    cat(toJSON(v, auto_unbox = TRUE, null = "null"), "\n", sep = "")
    quit(save = "no", status = exit)
  }

  if (!isTRUE(cfg$enabled)) out(FALSE, "disabled", 12L,
        note = "reinforce_auto_config.json::cleaner_distill.enabled=false — kill switch")

  pj <- .cd_read_json(.cd_pending_path(), NULL)
  if (is.null(pj)) out(FALSE, "no_pending", 10L,
        note = "cleaner_pending.json 없음 — 스윕이 아직 안 돌았다")

  st <- as.character(pj$status %||% "")
  ds <- as.character(pj$distill_status %||% (if (identical(st, "distilled")) "done" else "pending"))
  if (identical(ds, "done") || identical(st, "distilled"))
    out(FALSE, "already_distilled", 10L, week_of = pj$week_of %||% NA)

  # in_progress 인데 stale 이 아니면 다른 소비자(세션 /cleaner 포함)가 쥐고 있다
  if (identical(ds, "in_progress")) {
    age_h <- suppressWarnings(as.numeric(difftime(Sys.time(),
               as.POSIXct(substr(as.character(pj$distill_claimed_at %||% ""), 1, 19),
                          format = "%Y-%m-%d %H:%M:%S", tz = ""), units = "hours")))
    stale_h <- as.numeric(cfg$claim_stale_hours %||% 6)
    if (is.na(age_h) || age_h < stale_h)
      out(FALSE, "distill_in_progress", 11L,
          owner = pj$distill_owner %||% NA, age_h = if (is.na(age_h)) NA else round(age_h, 2))
  }

  # ── 강화 무인 러너 활성 여부 (claim owner.json 의 pid 가 살아있나) ──
  if (!isTRUE(cfg$ignore_reinforce_claim)) {
    claim <- Sys.getenv("QVEST_RF_CLAIM", file.path(ROOT, ".cache/reinforce_auto.claim"))
    ow <- file.path(claim, "owner.json")
    rel <- file.path(claim, "released.json")
    if (dir.exists(claim) && file.exists(ow) && !file.exists(rel)) {
      rc <- file.path(ROOT, "02_Infrastructure/ops/rf_claim.R")
      alive <- TRUE
      if (file.exists(rc)) {
        e <- new.env(parent = globalenv())
        ok <- tryCatch({ suppressMessages(sys.source(rc, envir = e)); TRUE },
                       error = function(err) FALSE)
        o <- .cd_read_json(ow, NULL)
        if (ok && !is.null(o))
          alive <- tryCatch(isTRUE(e$rf_claim_pid_alive(o$pid)), error = function(err) TRUE)
      }
      if (isTRUE(alive))
        out(FALSE, "reinforce_active", 11L,
            note = "강화 무인 러너가 칸을 돌고 있다 — 원장·stage_artifacts 동시 접근과 claude -p 경합 회피. 연기(다음 일간 훅이 재시도)")
    }
  }

  # ── 스윕 자신이 아직 도는 중인지 (sweep lock, 2h stale) ──
  sl <- file.path(ROOT, ".cache", "cleaner_sweep.lock")
  if (file.exists(sl)) {
    lj <- .cd_read_json(sl, NULL)
    ts <- suppressWarnings(as.numeric(lj$ts %||% NA))
    if (!is.na(ts) && (as.numeric(Sys.time()) - ts) < 7200)
      out(FALSE, "sweep_running", 11L, note = "weekly_cleaner_sweep.R 실행 중 — 재료가 아직 확정 안 됨")
  }

  out(TRUE, "ok", 0L, week_of = pj$week_of %||% NA,
      note = "착수 가능 — claim 은 호출자(cleaner_distill_run.sh)가 cleaner_claim.R 로 잡는다")
}

#==============================================================================
# materials — 에이전트 재료 조립
#==============================================================================

# 삭제 후보 = 일간 위생 감사가 **감지했지만 지우지 않은** 것 (artifact-storage §8 2선).
#   새 스캐너를 짜지 않는 이유: 이미 도는 계기가 있는데 두 벌이면 한쪽만 고쳐졌을 때
#   어느 검사에도 안 보인다. 여기서는 그 목록에 사실(크기·나이·참조수)만 붙인다.
.cd_delete_candidates <- function(pr, limit = 60L) {
  hp <- file.path(ROOT, "06_Registry", "hygiene_report.json")
  hj <- .cd_read_json(hp, NULL)
  if (is.null(hj)) return(list())
  w <- hj$warnings %||% list()
  mk <- function(v, kind) {
    v <- unlist(v %||% list(), use.names = FALSE)
    if (!length(v)) return(list())
    lapply(v, function(p) list(path = as.character(p), kind = kind))
  }
  cand <- c(mk(w$root_unauthorized, "root_unauthorized"),
            mk(w$infra_underscore,  "infra_underscore"),
            mk(w$misplaced_outputs, "misplaced_outputs"))
  if (!length(cand)) return(list())

  ok_paths <- unlist(pr$underscore_ok_paths$paths %||% list(), use.names = FALSE)
  res <- list()
  for (c1 in cand) {
    p <- c1$path
    if (!nzchar(p) || identical(p, "-")) next
    # 이미 예외 등재된 private 모듈은 후보로도 보여주지 않는다(에이전트 판단 낭비 방지)
    if (any(vapply(ok_paths, function(o) endsWith(p, o) || identical(p, o), logical(1)))) next
    full <- file.path(ROOT, p)
    if (!file.exists(full) && !dir.exists(full)) next
    fi <- file.info(full)
    prot <- .cd_is_protected(p, pr)
    rc <- .cd_ref_count(p, pr)   # ★한 번만 — git grep 은 후보마다 전 저장소를 훑는다
    res[[length(res) + 1L]] <- list(
      path      = p,
      kind      = c1$kind,
      is_dir    = isTRUE(fi$isdir),
      size_kb   = round((fi$size %||% 0) / 1024, 1),
      age_days  = round(as.numeric(difftime(Sys.time(), fi$mtime, units = "days")), 1),
      protected = prot$protected,
      protected_by = prot$by,
      n_refs    = rc$n,
      n_refs_raw = rc$n_raw,
      refs      = paste(utils::head(rc$files, 3), collapse = " | ")
    )
    if (length(res) >= limit) break
  }
  res
}

# 절대보존 판정 — prefix / 정확파일 / 이름예외 3축
.cd_is_protected <- function(relpath, pr) {
  p <- sub("^\\./", "", gsub("\\\\", "/", relpath))
  for (e in pr$absolute_preserve %||% list()) {
    pre <- as.character(e$prefix %||% "")
    if (nzchar(pre) && (startsWith(p, pre) || identical(p, sub("/$", "", pre))))
      return(list(protected = TRUE, by = sprintf("prefix:%s (%s)", pre, e$source %||% "")))
  }
  for (e in pr$absolute_preserve_files %||% list()) {
    if (identical(p, as.character(e$path %||% "")))
      return(list(protected = TRUE, by = sprintf("file:%s (%s)", e$path, e$source %||% "")))
  }
  for (e in pr$named_exceptions %||% list()) {
    m <- as.character(e$match %||% "")
    if (nzchar(m) && grepl(m, p, fixed = TRUE))
      return(list(protected = TRUE, by = sprintf("named:%s (%s)", m, e$source %||% "")))
  }
  list(protected = FALSE, by = NA_character_)
}

# 참조 0 검증 — SKILL §4 의무의 기계 재도출. basename 으로 전 저장소(추적+미추적) 조회.
#
#   ★기록과 소비를 가른다 (2026-09-05 양성 대조에서 적발): 삭제 후보는 전부
#     hygiene_report.json 에서 나오는데 그 파일이 후보 경로를 적어 두므로, 문자 그대로 세면
#     **모든 후보가 참조 1건**이 되어 삭제가 원리상 불가능해진다. 위반 주입 방향만 쟀다면
#     "가드 완벽 · 20/20 초록" 으로 나가고 레인은 영영 아무것도 안 지웠을 것이다.
#     제외 목록은 레지스트리(ref_check_ignore)에 사유와 함께 있고, 무엇이 제외됐는지는
#     n_refs_raw / ignored 로 매니페스트에 남는다 — 조용한 완화 금지.
#   ★목록에 없는 것은 전부 참조로 센다. 넓게 잡히는 쪽이 보수적이다.
.cd_ref_ignore_rx <- function(pr) {
  gl <- vapply(pr$ref_check_ignore$globs %||% list(),
               function(e) as.character(e$glob %||% ""), character(1))
  gl <- gl[nzchar(gl)]
  if (!length(gl)) return(character(0))
  # glob → regex: 정규식 특수문자를 죽이고 `*` 만 살린다 (역참조 미사용 — R 8진 함정 회피)
  vapply(gl, function(g) {
    e <- gsub("([.+^$(){}|\\[\\]\\\\])", "\\\\\\1", g, perl = TRUE)
    paste0("^", gsub("*", ".*", e, fixed = TRUE), "$")
  }, character(1), USE.NAMES = FALSE)
}

.cd_ref_count <- function(relpath, pr = NULL) {
  bn <- basename(sub("/+$", "", gsub("\\\\", "/", relpath)))
  if (!nzchar(bn)) return(list(n = -1L, n_raw = -1L, files = character(0), ignored = character(0)))
  out <- tryCatch(suppressWarnings(system2("git",
           c("-C", shQuote(ROOT), "grep", "-l", "--untracked", "-F", "--", shQuote(bn)),
           stdout = TRUE, stderr = FALSE)), error = function(e) NULL)
  if (is.null(out)) return(list(n = -1L, n_raw = -1L, files = character(0), ignored = character(0)))
  files <- setdiff(gsub("\\\\", "/", out), sub("^\\./", "", gsub("\\\\", "/", relpath)))
  n_raw <- length(files)
  rx <- .cd_ref_ignore_rx(pr %||% .cd_protected())
  ignored <- character(0)
  if (length(rx) && n_raw) {
    hit <- vapply(files, function(f) any(vapply(rx, function(r) grepl(r, f), logical(1))), logical(1))
    ignored <- files[hit]; files <- files[!hit]
  }
  list(n = length(files), n_raw = n_raw, files = files, ignored = ignored)
}

cd_materials <- function(out_path) {
  pr <- .cd_protected()
  pj <- .cd_read_json(.cd_pending_path(), list())
  cfg <- .cd_cfg()
  L <- character(0)
  ad <- function(...) L <<- c(L, sprintf(...))

  ad("# 주간 증류 재료 — week_of=%s (생성 %s)",
     pj$week_of %||% "?", format(Sys.time(), "%Y-%m-%d %H:%M"))
  ad("")

  # ── 1. 이번 주 인벤토리 ────────────────────────────────────────────────
  inv <- pj$inventory %||% list()
  ad("## 1. 이번 주 인벤토리 (지난 7일)")
  ad("- 스윕 삭제: %s건 (매니페스트 .cache/hygiene_manifest.log)",
     as.character(pj$sweep_deleted_n %||% "?"))
  ad("- stage_artifacts 신규 엔트리: %s건", as.character(inv$stage_artifacts_new$n %||% "?"))
  ad("- 신규 L-code: %s건", as.character(inv$new_lcodes$n %||% "?"))
  ad("- 커밋: %s건", as.character(inv$git_log_7d$n_commits %||% "?"))
  ad("")
  ad("전문(JSON)은 아래 파일에 있다 — 필요한 절만 읽어라:")
  ad("  .cache/cleaner_pending.json  (inventory / sweep_detail / axiom_candidates / step_status)")
  ad("")

  # ── 2. 공리 사이클 현황 ────────────────────────────────────────────────
  ac <- pj$axiom_candidates %||% list()
  ad("## 2. 공리 사이클 (스윕 [3.5] 산출 — digest 의 의무 절)")
  ad("- pending 후보: %s건 / 스폰 생략: %s건",
     as.character(ac$n_pending %||% "?"), as.character(ac$n_promote_skipped %||% "?"))
  ad("- 이번 주 활성화: %d건 / 정제보류(HELD): %d건",
     length(ac$activated_axioms %||% list()), length(ac$held_axioms %||% list()))
  if (!is.null(ac$activation_hold))
    ad("- ⚠ 활성화 HOLD 발동: %s",
       paste(unlist(ac$activation_hold$reasons %||% list()), collapse = "; "))
  ad("")

  # ── 3. DIST 초안 대상 (백로그 드레인) ──────────────────────────────────
  dk <- .cd_read_json(file.path(ROOT, "06_Registry", "distilled_knowledge.json"), list())
  ents <- dk$entries %||% list()
  pend <- Filter(function(x) identical(x$status, "pending_5axis"), ents)
  nq <- length(Filter(function(x) identical(x$status, "quarantined_evidence"), ents))
  maxd <- as.integer(cfg$max_drafts %||% 8L)
  # 우선순위 = supporting L-code 수 상위 (SKILL §백로그 드레인 ①)
  ns <- vapply(pend, function(x) as.integer(x$n_supporting %||% 0L), integer(1))
  pend <- pend[order(-ns)]
  pick <- utils::head(pend, maxd)

  corpus <- .cd_read_json(file.path(ROOT, ".cache", "lcode_corpus.json"), list())
  lmap <- list()
  for (lc in corpus$lcodes %||% list()) {
    id <- as.character(lc$l_code %||% "")
    if (nzchar(id)) lmap[[id]] <- lc
  }

  ad("## 3. DIST 초안 대상 %d건 (pending_5axis 백로그 %d건 중 supporting 상위 · 격리 %d건은 대상 제외)",
     length(pick), length(pend), nq)
  ad("")
  for (d in pick) {
    ad("### %s  [%s · %s · polarity=%s · type=%s · supporting=%s]",
       d$dist_id, d$research_mode %||% "?", d$family %||% "?",
       d$polarity %||% "?", d$type %||% "?", as.character(d$n_supporting %||% 0))
    ad("- created_at: %s / expiry: %s", d$created_at %||% "?", d$expiry %||% "?")
    ad("- statement_draft: %s", substr(gsub("[\r\n]+", " ", d$statement_draft %||% ""), 1, 400))
    for (lid in unlist(d$supporting_l_codes %||% list(), use.names = FALSE)) {
      lc <- lmap[[as.character(lid)]]
      if (is.null(lc)) { ad("- [%s] (corpus 미발견)", lid); next }
      ad("- [%s] grade=%s metric_type=%s :: %s", lid, lc$grade %||% "?", lc$metric_type %||% "?",
         substr(gsub("[\r\n]+", " ", lc$lesson_text %||% ""), 1, 500))
    }
    ad("")
  }

  # ── 4. 제약 방화벽 컨텍스트 (적대검증 (d) — 의미기반 판정용) ────────────
  ad("## 4. 제약 방화벽 컨텍스트 (적대검증 (d) — 의미로 판정하라)")
  fw <- file.path(ROOT, "02_Infrastructure", "axiom", "constraint_firewall.R")
  fwtxt <- NULL
  if (file.exists(fw)) {
    fwtxt <- tryCatch({
      e <- new.env(parent = globalenv())
      suppressMessages(sys.source(fw, envir = e))
      if (exists("load_firewall_context", envir = e, mode = "function"))
        paste(utils::capture.output(print(e$load_firewall_context())), collapse = "\n")
      else NULL
    }, error = function(err) NULL)
  }
  # ★재료 조립기가 방화벽 컨텍스트를 못 실으면 **조용히 넘기지 않는다** — 적대검증 (d)가
  #   컨텍스트 없이 도는 것은 그 체크가 죽은 것과 같다. 실패를 재료에 적어 에이전트가 안다.
  if (is.null(fwtxt) || !nzchar(fwtxt)) {
    ad("⚠ load_firewall_context() 적재 실패 — (d) 판정은 원리로만 수행하고,")
    ad("   초안에 `firewall_context_missing: true` 를 표시하라(기계 backstop 은 그대로 돈다).")
  } else ad("%s", substr(fwtxt, 1, 6000))
  ad("")

  # ── 5. 삭제 후보 ───────────────────────────────────────────────────────
  ad("## 5. 삭제 후보 (일간 위생 감사가 감지했으나 지우지 않은 것)")
  if (isTRUE(pr$broken)) {
    ad("⚠ 보호 목록(06_Registry/cleaner_protected_paths.json) 적재 실패 — **이번 주 삭제는 전면 금지**.")
    ad("   deletions 는 빈 배열로 내고 사유를 report 에 적어라.")
  } else {
    g <- pr$execution_guards %||% list()
    ad("집행 가드(기계가 재도출): 보호 prefix %d종 · 최근 %s시간 내 수정분 제외 · 참조0 재검(git grep) · 상한 %s건/%sMB",
       length(pr$absolute_preserve %||% list()), as.character(g$mtime_guard_hours %||% 24),
       as.character(g$max_deletions %||% 40), as.character(g$max_delete_mb %||% 2048))
    ad("참조수는 basename 전 저장소 조회다 — 이름이 짧거나 흔하면(`25`·`x.rds` 류) 수백 건으로 뜨는데")
    ad("그건 '쓰인다' 가 아니라 '이름이 겹친다' 이다. 그런 항목은 기계가 어차피 거부하니 `deferred` 로 넘겨라.")
    ad("")
    cands <- .cd_delete_candidates(pr)
    if (!length(cands)) ad("(후보 없음)")
    for (c1 in cands) {
      ad("- `%s` [%s] %s%.1fKB · %s일 · 참조 %s%s",
         c1$path, c1$kind, if (isTRUE(c1$is_dir)) "DIR · " else "",
         c1$size_kb, format(c1$age_days),
         if (identical(c1$n_refs, -1L)) "판정불가" else as.character(c1$n_refs),
         if (isTRUE(c1$protected)) sprintf("  ⛔보호됨(%s) — 고르면 거부된다", c1$protected_by) else "")
      if (nzchar(c1$refs %||% "")) ad("    참조처: %s", c1$refs)
    }
  }
  ad("")

  # ── 6. 직전 digest (형식 참고) ─────────────────────────────────────────
  wd <- file.path(ROOT, "04_Research", "01_reports", "weekly")
  prev <- sort(list.files(wd, pattern = "^weekly_digest_.*\\.md$"), decreasing = TRUE)
  ad("## 6. 직전 digest (형식 참고 — 내용 복사 금지)")
  if (length(prev)) ad("- 04_Research/01_reports/weekly/%s", prev[1]) else ad("- (없음)")
  ad("")

  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  con <- file(out_path, open = "wb")
  writeBin(charToRaw(paste0(paste(L, collapse = "\n"), "\n")), con)
  close(con)
  cat(sprintf("[cleaner_distill] materials → %s (%d줄, DIST후보 %d건)\n",
              out_path, length(L), length(pick)))
  .cd_jlog("materials_built", out = out_path, n_lines = length(L), n_drafts = length(pick))
  invisible(TRUE)
}

#==============================================================================
# apply — 에이전트 산출 검증 + 집행
#==============================================================================
cd_apply <- function(result_path) {
  res <- .cd_read_json(result_path, NULL)
  if (is.null(res)) { cat("[cleaner_distill][FAIL] 결과 JSON 없음/파손: ", result_path, "\n", sep = "")
    .cd_jlog("apply_no_result", path = result_path); quit(save = "no", status = 3L) }

  cfg <- .cd_cfg(); pr <- .cd_protected()
  today <- format(Sys.Date(), "%Y%m%d")
  rep <- list(schema = "cleaner_distill_apply_v1",
              applied_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
              week_of = res$week_of %||% NA, result_path = result_path)

  # ── (1) digest 실재 검증 — 경로 진술이 아니라 파일을 본다 ────────────────
  dg <- as.character(res$digest_path %||% "")
  dg_full <- if (nzchar(dg)) file.path(ROOT, sub("^/", "", dg)) else ""
  dg_ok <- nzchar(dg) && file.exists(dg_full) && (file.info(dg_full)$size %||% 0) >= 500
  rep$digest <- list(path = dg, exists = file.exists(dg_full %||% ""),
                     bytes = if (nzchar(dg_full) && file.exists(dg_full)) file.info(dg_full)$size else 0,
                     ok = dg_ok,
                     note = if (dg_ok) "OK" else "digest 부재/과소(500B 미만) — 증류 미완으로 간주")

  # ── (2) DIST 초안 집행 (draft_proposed 경유 — 방화벽 backstop 이 그 안에 있다) ──
  drafts <- res$dist_drafts %||% list()
  dres <- list()
  if (length(drafts)) {
    de <- new.env(parent = globalenv())
    dsrc <- file.path(ROOT, "02_Infrastructure", "axiom", "distilled.R")
    dok <- tryCatch({ suppressMessages(sys.source(dsrc, envir = de)); TRUE },
                    error = function(e) { cat("[cleaner_distill][WARN] distilled.R 적재 실패: ",
                                              conditionMessage(e), "\n", sep = ""); FALSE })
    for (d in drafts) {
      id <- as.character(d$dist_id %||% "")
      if (!dok) { dres[[length(dres)+1L]] <- list(dist_id = id, ok = FALSE, reason = "distilled.R 적재 실패"); next }
      r <- tryCatch({
        de$draft_proposed(dist_id = id,
                          statement_refined   = as.character(d$statement_refined %||% ""),
                          retry_condition     = d$retry_condition,
                          adversarial_verdict = d$adversarial_verdict,
                          expiry              = d$expiry,
                          frontier            = d$frontier,
                          live_trigger        = d$live_trigger,
                          drafted_by          = "auto_distill")
        list(dist_id = id, ok = TRUE, reason = "proposed")
      }, error = function(e) list(dist_id = id, ok = FALSE, reason = conditionMessage(e)))
      dres[[length(dres)+1L]] <- r
    }
  }
  rep$dist_drafts <- dres
  rep$n_drafts_ok <- sum(vapply(dres, function(x) isTRUE(x$ok), logical(1)))

  # ── (3) L-code 발행 ────────────────────────────────────────────────────
  lcs <- res$lcodes %||% list()
  lres <- list()
  if (length(lcs)) {
    ee <- new.env(parent = globalenv())
    esrc <- file.path(ROOT, "02_Infrastructure", "axiom", "lcode_emit.R")
    eok <- tryCatch({ suppressMessages(sys.source(esrc, envir = ee)); TRUE },
                    error = function(e) FALSE)
    # 중복 발행 방지 — 기존 corpus 의 lesson_text 와 정확 일치는 재발행하지 않는다
    corpus <- .cd_read_json(file.path(ROOT, ".cache", "lcode_corpus.json"), list())
    seen <- vapply(corpus$lcodes %||% list(),
                   function(x) as.character(x$lesson_text %||% ""), character(1))
    for (l in lcs) {
      txt <- as.character(l$lesson_text %||% "")
      if (!eok) { lres[[length(lres)+1L]] <- list(ok = FALSE, reason = "lcode_emit.R 적재 실패"); next }
      if (!nzchar(txt)) { lres[[length(lres)+1L]] <- list(ok = FALSE, reason = "lesson_text 빈값"); next }
      if (txt %in% seen) { lres[[length(lres)+1L]] <- list(ok = FALSE, reason = "중복(corpus 동일 lesson_text)"); next }
      r <- tryCatch({
        o <- ee$emit_lcode(mode = as.character(l$mode %||% "cleaner"),
                           strategy_id = as.character(l$strategy_id %||% "WEEKLY_DISTILL"),
                           grade = as.character(l$grade %||% "NA"),
                           lesson_text = txt,
                           metric_type = as.character(l$metric_type %||% "estimated"),
                           mechanism_hypothesis = l$mechanism_hypothesis,
                           next_probe = l$next_probe,
                           family = l$family,
                           core_reference = as.character(l$core_reference %||% ""),
                           tags = l$tags)
        list(ok = TRUE, l_code = as.character(o$l_code %||% o %||% "발행"), reason = "emitted")
      }, error = function(e) list(ok = FALSE, reason = conditionMessage(e)))
      lres[[length(lres)+1L]] <- r
    }
  }
  rep$lcodes <- lres
  rep$n_lcodes_ok <- sum(vapply(lres, function(x) isTRUE(x$ok), logical(1)))

  # ── (4) 삭제 집행 — 여기가 기계 재도출의 본체 ──────────────────────────
  dels <- res$deletions %||% list()
  executed <- list(); rejected <- list()
  g <- pr$execution_guards %||% list()
  max_n  <- as.integer(g$max_deletions %||% 40L)
  max_mb <- as.numeric(g$max_delete_mb %||% 2048)
  mt_h   <- as.numeric(g$mtime_guard_hours %||% 24)
  acc_mb <- 0

  # ★QVEST_CLEANER_DRY=1 — 스윕과 같은 관례를 삭제 축에도 둔다("관측이지 통보가 아니다").
  #   가드는 그대로 다 돌고 **집행만** 안 한다. 그래야 dry 산출이 실행 예정과 같은 판정을 보여준다
  #   (가드를 건너뛰는 dry 는 실행과 다른 답을 내므로 관측 가치가 없다).
  DRY_DEL <- identical(Sys.getenv("QVEST_CLEANER_DRY", "0"), "1")
  if (DRY_DEL) rep$dry_run_deletions <- TRUE

  if (isTRUE(pr$broken) && length(dels)) {
    for (d in dels) rejected[[length(rejected)+1L]] <-
      list(path = as.character(d$path %||% ""), reason = "protected_list_broken — 보호 목록 부재로 삭제 전면 금지")
  } else for (d in dels) {
    p <- sub("^\\./", "", gsub("\\\\", "/", as.character(d$path %||% "")))
    rj <- function(why) rejected[[length(rejected)+1L]] <<- list(path = p, reason = why,
                                                                agent_reason = d$reason %||% NA)
    if (!nzchar(p)) { rj("빈 경로"); next }
    if (grepl("\\.\\.", p, fixed = TRUE) || grepl("^([A-Za-z]:|/)", p)) { rj("절대경로/상위탈출 — 상대경로만 허용"); next }
    prot <- .cd_is_protected(p, pr)
    if (isTRUE(prot$protected)) { rj(sprintf("보호구역 — %s", prot$by)); next }
    full <- file.path(ROOT, p)
    if (!file.exists(full) && !dir.exists(full)) { rj("대상 부재(이미 없음)"); next }
    fi <- file.info(full)
    age_h <- as.numeric(difftime(Sys.time(), fi$mtime, units = "hours"))
    if (!is.na(age_h) && age_h < mt_h) { rj(sprintf("최근 %.1fh 내 수정 — 진행 중 라운드 보호(<%sh)", age_h, mt_h)); next }
    rc <- .cd_ref_count(p, pr)
    if (identical(rc$n, -1L)) { rj("참조 판정 불가(git grep 실패) — 보수적 보존"); next }
    if (rc$n > 0L) { rj(sprintf("참조 %d건 잔존: %s", rc$n, paste(utils::head(rc$files, 3), collapse = ", "))); next }
    if (length(executed) >= max_n) { rj(sprintf("상한 초과(max_deletions=%d) — 다음 주 재후보", max_n)); next }
    mb <- (fi$size %||% 0) / 1048576
    if (acc_mb + mb > max_mb) { rj(sprintf("용량 상한 초과(max_delete_mb=%s)", max_mb)); next }

    if (DRY_DEL) {
      acc_mb <- acc_mb + mb
      executed[[length(executed)+1L]] <- list(path = p, reason = as.character(d$reason %||% ""),
                                              size_kb = round((fi$size %||% 0)/1024, 1),
                                              ref_check = "0건(git grep 재도출)",
                                              n_refs_raw = rc$n_raw,
                                              refs_ignored_as_record = as.list(rc$ignored),
                                              dry_run = TRUE, note = "DRY — 가드 전부 통과했으나 집행 안 함")
      next
    }
    ok <- tryCatch({ if (isTRUE(fi$isdir)) unlink(full, recursive = TRUE) else unlink(full)
                     !file.exists(full) && !dir.exists(full) }, error = function(e) FALSE)
    if (!isTRUE(ok)) { rj("삭제 실패(OS 거부/사용 중)"); next }
    acc_mb <- acc_mb + mb
    # ★n_refs_raw / ignored 를 같이 남긴다 — 무엇을 '기록' 으로 보고 분모에서 뺐는지가
    #   보이지 않으면 그 완화는 조용한 완화가 된다(ref_check_ignore 의 감사 흔적).
    executed[[length(executed)+1L]] <- list(path = p, reason = as.character(d$reason %||% ""),
                                            size_kb = round((fi$size %||% 0)/1024, 1),
                                            ref_check = "0건(git grep 재도출)",
                                            n_refs_raw = rc$n_raw,
                                            refs_ignored_as_record = as.list(rc$ignored))
    try(cat(sprintf("%s\tweekly_distill_llm\t%s%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), p,
                    if (DRY_DEL) "\t[DRY]" else ""),
            file = file.path(ROOT, ".cache", "hygiene_manifest.log"), append = TRUE), silent = TRUE)
  }
  rep$deletions <- list(executed = executed, rejected = rejected,
                        n_executed = length(executed), n_rejected = length(rejected),
                        mb_freed = round(acc_mb, 2))
  rep$deferred <- res$deferred %||% list()

  # ── (5) distill manifest (SKILL §4 의무 산출) ──────────────────────────
  mpath <- file.path(ROOT, "06_Registry", sprintf("distill_manifest_%s.json", today))
  try(write_json(list(
    schema = "distill_manifest_v2", generated_at = rep$applied_at,
    generator = "02_Infrastructure/ops/cleaner_distill_lib.R (무인 증류 레인)",
    week_of = rep$week_of, digest = rep$digest,
    deleted = executed, rejected = rejected, preserved_deferred = rep$deferred,
    dist_drafts = dres, lcodes = lres),
    mpath, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), silent = TRUE)
  rep$manifest_path <- sprintf("06_Registry/distill_manifest_%s.json", today)

  # ── (6) pending 갱신 (claim 필드 보존 — 읽기·수정·쓰기) ────────────────
  pp <- .cd_pending_path()
  pj <- .cd_read_json(pp, NULL)
  if (!is.null(pj)) {
    pj$digest_path      <- if (dg_ok) dg else NULL
    pj$distilled_at     <- rep$applied_at
    pj$distill_summary  <- list(
      mode = "auto_distill (무인 레인)",
      digest = dg_ok, n_drafts_ok = rep$n_drafts_ok, n_lcodes_ok = rep$n_lcodes_ok,
      n_deleted = length(executed), n_rejected = length(rejected),
      manifest = rep$manifest_path)
    # ★status/distill_status 는 여기서 건드리지 않는다 — 해제는 cleaner_release_distill 이
    #   owner 대조와 함께 한다(두 곳이 같은 필드를 쓰면 어느 쪽이 이겼는지 알 수 없다).
    tmp <- sprintf("%s.tmp.%d", pp, Sys.getpid())
    write_json(pj, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
    if (!isTRUE(suppressWarnings(file.rename(tmp, pp)))) {
      suppressWarnings(file.copy(tmp, pp, overwrite = TRUE)); suppressWarnings(unlink(tmp))
    }
  }

  cat(toJSON(rep[c("week_of","digest","n_drafts_ok","n_lcodes_ok","deletions","manifest_path")],
             auto_unbox = TRUE, null = "null"), "\n", sep = "")
  .cd_jlog("apply_done", digest_ok = dg_ok, n_drafts_ok = rep$n_drafts_ok,
           n_lcodes_ok = rep$n_lcodes_ok, n_deleted = length(executed),
           n_rejected = length(rejected))
  cat(sprintf("[cleaner_distill] apply 완료 — digest=%s DIST초안 %d건 L-code %d건 삭제 %d건(거부 %d)\n",
              if (dg_ok) "OK" else "MISSING", rep$n_drafts_ok, rep$n_lcodes_ok,
              length(executed), length(rejected)))
  # digest 가 없으면 증류가 안 된 것이다 — 호출자가 release 하지 않고 재시도하게 비0 반환
  quit(save = "no", status = if (dg_ok) 0L else 4L)
}

#==============================================================================
# notify — 텔레그램 완료 보고 (tg_agent_brief 단일 진입 — 직접 호출은 훅이 차단한다)
#
#   ★Rscript -e 로 부르지 않고 서브커맨드로 둔 이유: `-e` 에 개행이 들어가면 rc=139 로
#     죽고, 문자열 안의 `|` 는 cmd 파이프로 해석된다(저장소 실측 함정 2종).
#==============================================================================
cd_notify <- function(manifest_path) {
  m <- .cd_read_json(manifest_path, list())
  pj <- .cd_read_json(.cd_pending_path(), list())
  owd <- getwd(); setwd(ROOT)
  ok <- tryCatch({
    suppressWarnings(source("02_Infrastructure/telegram/telegram_notify.R"))
    exists("tg_agent_brief")
  }, error = function(e) FALSE)
  if (!ok) { setwd(owd); cat("[cleaner_distill] telegram 로드 실패 — fail-soft\n"); return(invisible(FALSE)) }
  dl <- m$deleted %||% list(); rj <- m$rejected %||% list()
  dr <- m$dist_drafts %||% list(); lc <- m$lcodes %||% list()
  n_dr <- sum(vapply(dr, function(x) isTRUE(x$ok), logical(1)))
  n_lc <- sum(vapply(lc, function(x) isTRUE(x$ok), logical(1)))
  ac <- pj$axiom_candidates %||% list()
  secs <- list(
    list(type = "summary", heading = "주간 클리너 — 무인 증류 완료",
         body = sprintf("%s 주차 증류를 무인 레인이 완주했다. digest %s · DIST 초안 %d건(proposed — 주입 안 됨) · L-code %d건 · 잔재 삭제 %d건(기계 거부 %d건).",
                        as.character(m$week_of %||% "?"),
                        if (isTRUE((m$digest %||% list())$ok)) "작성" else "미작성",
                        n_dr, n_lc, length(dl), length(rj))),
    list(type = "bullet", heading = "산출", items = c(
      sprintf("digest: %s", as.character((m$digest %||% list())$path %||% "없음")),
      sprintf("매니페스트: %s", basename(manifest_path)),
      sprintf("DIST 초안 %d/%d건 — 활성화는 여전히 도훈 승인(approve_proposed). 초안은 주입 스트림에 안 들어간다",
              n_dr, length(dr)),
      sprintf("L-code %d/%d건 발행", n_lc, length(lc)),
      sprintf("삭제 %d건 / 기계 거부 %d건 (보호구역·참조잔존·24h내 수정)", length(dl), length(rj)),
      sprintf("공리 pending %s건 · 정제보류 %d건",
              as.character(ac$n_pending %||% "?"), length(ac$held_axioms %||% list()))
    ))
  )
  if (length(rj)) {
    items <- vapply(utils::head(rj, 5), function(x)
      sprintf("%s — %s", as.character(x$path %||% "?"), substr(as.character(x$reason %||% ""), 1, 90)),
      character(1))
    secs[[length(secs)+1L]] <- list(type = "bullet", heading = "삭제 거부 (기계 재도출)", items = items)
  }
  tryCatch(tg_agent_brief(agent = "Q-Lead", title = "주간 클리너 — 무인 증류 완료",
                          relaxed = TRUE, force = TRUE,
                          lock_scope = sprintf("weekly_distill_%s", format(Sys.Date(), "%Y%m%d")),
                          sections = secs),
           error = function(e) cat("[cleaner_distill] telegram 발송 실패(fail-soft): ",
                                   conditionMessage(e), "\n", sep = ""))
  setwd(owd)
  invisible(TRUE)
}

#==============================================================================
# CLI
#==============================================================================
.args <- commandArgs(trailingOnly = TRUE)
if (length(.args) && !nzchar(Sys.getenv("CLEANER_DISTILL_SOURCED", ""))) {
  cmd <- .args[1]
  if (identical(cmd, "gate")) cd_gate()
  else if (identical(cmd, "materials")) {
    if (length(.args) < 2) { cat("usage: materials <out.txt>\n"); quit(save = "no", status = 2L) }
    cd_materials(.args[2]); quit(save = "no", status = 0L)
  } else if (identical(cmd, "apply")) {
    if (length(.args) < 2) { cat("usage: apply <result.json>\n"); quit(save = "no", status = 2L) }
    cd_apply(.args[2])
  } else if (identical(cmd, "notify")) {
    if (length(.args) < 2) { cat("usage: notify <manifest.json>\n"); quit(save = "no", status = 2L) }
    cd_notify(.args[2]); quit(save = "no", status = 0L)
  } else { cat("unknown subcommand: ", cmd, "\n", sep = ""); quit(save = "no", status = 2L) }
}
