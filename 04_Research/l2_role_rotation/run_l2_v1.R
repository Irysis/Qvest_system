#==============================================================================
# run_l2_v1.R — 2계층 역할 슬리브 로테이션 v1 측정 드라이버 (PR-L2-ROLESLEEVE-V1 · 단계 3 — MC2_v1 PASS 일 때만)
#
# v0 드라이버(run_l2_v0.R · 동결)와 같은 절차. 두 모드(이 디렉터리에서 Rscript --no-save -e 'source("run_l2_v1.R")'):
#   · L2V1_ARM 미설정 = 오케스트레이터 — 설계 arm order(T_var·K·S·EW_all) **순차**. 전제: verdict_v1/mc2_v1.json pass ∧
#     sanity_v1/sanity_v1.json all_pass ∧ 초안 pins(엔진·드라이버·설계) 일치. arm 마다 ①여유 RAM ≥ L2V1_MIN_FREE_GB(기본 8 · PowerShell
#     Get-CimInstance Win32_OperatingSystem · 미달이면 60초 간격 대기) ②리프레시 배리어(refresh_barrier.R::rb_status) ③자식 Rscript 1개.
#   · L2V1_ARM=<arm> = arm 1개를 run_paper_replication(engine_direct) 으로 측정.
# 고정(v0 와 같음): data_cutoff 2026-09-30 · start_date 2015-09-01 · send_telegram FALSE · QVEST_RP_REGISTER=0 · QVEST_RP_NO_LCODE=1 ·
#   QVEST_NO_LEDGER_OPEN=1 · out_root = runs_v1/<arm> · 등급 = 러너 essence 그대로 · selection chain(n_trials 2 = v0 T_var → v1 T_var · DSR 진단만).
# A 가 나오면 judge_request*.json → *.EXPERIMENT_HOLD.json (이 단위 A 자격 없음 · mechanism_only).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[run_l2_v1] 프로젝트 루트 미발견")
}
ROOT  <- .find_root()
L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
DESIGN <- fromJSON(file.path(L2DIR, "l2v1_design.json"), simplifyVector = FALSE)
PREREG_ID <- "PR-L2-ROLESLEEVE-V1"
ARMS <- names(DESIGN$arms)[order(vapply(DESIGN$arms, function(a) as.numeric(a$order), numeric(1)))]
RUNS <- file.path(L2DIR, "runs_v1")
MAN_P <- file.path(L2DIR, "work/l2v1_inputs_manifest.json")
sha <- function(p) digest::digest(file = p, algo = "sha256")
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jw <- function(x, p) writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), p, useBytes = TRUE)
Sys.unsetenv(c("L2V1_MANIFEST_PATH", "L2V1_TEST", "L2V1_DRYRUN", "L2V1_SANITY_OUT", "L2V1_OUT_DIR"))   # 검사 전용 경로가 운영에 새지 않게

# ── 전제(양 모드 공통) — 단계 2 관문 · 측정 전 점검 · 초안 pins ─────────────────────
.gate <- function() {
  mc2 <- file.path(L2DIR, "verdict_v1/mc2_v1.json")
  if (!file.exists(mc2) || !isTRUE(fromJSON(mc2, simplifyVector = FALSE)$pass)) stop("[run_l2_v1] MC2_v1 PASS 아님/미측정 — 사전등록상 단계 3 없음")
  san <- file.path(L2DIR, "sanity_v1/sanity_v1.json")
  if (!file.exists(san)) stop("[run_l2_v1] sanity_v1 미실행")
  sv <- fromJSON(san, simplifyVector = FALSE)
  if (!isTRUE(sv$all_pass) || !identical(sv$mode, "production")) stop("[run_l2_v1] sanity_v1 all_pass 아님")
  source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"), local = TRUE)
  pr <- rf_prereg_load(PREREG_ID, "draft", root = ROOT)
  need <- list(engine = file.path(L2DIR, "allocator_engine_v1.R"), driver = file.path(L2DIR, "run_l2_v1.R"), design = file.path(L2DIR, "l2v1_design.json"),
               sanity = file.path(L2DIR, "sanity_l2v1.R"))
  for (k in names(need)) if (!identical(pr$pins[[k]]$sha256, sha(need[[k]]))) stop(sprintf("[run_l2_v1] %s sha256 ≠ 초안 pins.%s", basename(need[[k]]), k))
  if (!identical(sv$engine_sha256, sha(need$engine))) stop("[run_l2_v1] sanity 가 본 엔진 ≠ 현재 엔진")
  if (!identical(sv$sanity_script_sha256, sha(need$sanity))) stop("[run_l2_v1] sanity 산출물을 만든 스크립트 ≠ 초안 pins.sanity")
  if (!identical(sv$inputs_manifest$sha256, sha(MAN_P))) stop("[run_l2_v1] sanity 가 본 매니페스트 ≠ 현재 매니페스트")
  attr(pr, "integrity")
}

free_gb <- function() {
  v <- tryCatch(system2("powershell", c("-NoProfile", "-Command", "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"),
                        stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  kb <- suppressWarnings(as.numeric(trimws(v[length(v)])))
  if (is.finite(kb)) kb / 1024^2 else NA_real_
}
refresh_blocking <- function() {
  s <- tryCatch({ e <- new.env(); sys.source(file.path(ROOT, "02_Infrastructure/ops/refresh_barrier.R"), envir = e, keep.source = FALSE); e$rb_status(ROOT) },
                error = function(e) list(state = "error", blocking = TRUE, reason = conditionMessage(e)))
  list(blocking = isTRUE(s$blocking), state = as.character(s$state %||% ""), reason = as.character(s$reason %||% ""))
}

ARM <- Sys.getenv("L2V1_ARM", "")
if (!nzchar(ARM)) {
  # ── 오케스트레이터 ─────────────────────────────────────────────────────────────
  integ <- .gate()
  min_gb <- as.numeric(Sys.getenv("L2V1_MIN_FREE_GB", "8"))
  only <- Sys.getenv("L2V1_ONLY_ARMS", "")
  todo <- if (nzchar(only)) intersect(ARMS, strsplit(only, ",", fixed = TRUE)[[1]]) else ARMS
  logdir <- file.path(RUNS, "_logs"); dir.create(logdir, recursive = TRUE, showWarnings = FALSE)
  orch <- list(schema = "l2v1_orchestration_v1", prereg_id = PREREG_ID, prereg_draft = integ, started_at = now(), arms = list(), min_free_gb = min_gb)
  orch_path <- file.path(logdir, sprintf("orchestration_%s.json", format(Sys.time(), "%Y%m%d_%H%M%S")))
  for (a in todo) {
    if (length(list.files(file.path(RUNS, a), pattern = "^authoritative_remeasure[.]json$", recursive = TRUE)))
      stop(sprintf("[run_l2_v1] arm %s 는 이미 측정됐다(runs_v1/%s) — 재측정 금지(1회 측정 · 사전등록)", a, a))
    waited <- 0
    repeat {
      g <- free_gb(); rb <- refresh_blocking()
      if (is.finite(g) && g >= min_gb && !rb$blocking) break
      if (waited >= 4 * 3600) stop(sprintf("[run_l2_v1] arm %s: 4시간 대기 초과(RAM %.1fGB · refresh %s)", a, g, rb$state))
      cat(sprintf("[run_l2_v1] %s 대기 — 여유 RAM %.1fGB (기준 %.0f) · refresh %s\n", a, g, min_gb, rb$state)); flush.console()
      Sys.sleep(60); waited <- waited + 60
    }
    t0 <- Sys.time(); log <- file.path(logdir, sprintf("arm_%s.log", a))
    cat(sprintf("[run_l2_v1] %s 시작 %s · 여유 RAM %.1fGB · 로그 %s\n", a, now(), g, log)); flush.console()
    Sys.setenv(L2V1_ARM = a)
    rc <- system2("Rscript", c("--no-save", "-e", "\"source('run_l2_v1.R')\""), stdout = log, stderr = log)
    Sys.unsetenv("L2V1_ARM")
    rec_path <- file.path(RUNS, a, "run_record.json")
    rec <- if (file.exists(rec_path)) fromJSON(rec_path, simplifyVector = FALSE) else NULL
    orch$arms[[a]] <- list(rc = rc, started = format(t0, "%Y-%m-%dT%H:%M:%S%z"), finished = now(),
                           minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2),
                           free_gb_at_start = g, grade = rec$grade %||% NA, out_dir = rec$out_dir %||% NA)
    jw(orch, orch_path)
    cat(sprintf("[run_l2_v1] %s 종료 rc=%s · 등급 %s · %.1f분\n", a, rc, rec$grade %||% "NA", orch$arms[[a]]$minutes)); flush.console()
    if (!identical(as.integer(rc), 0L) || is.null(rec)) stop(sprintf("[run_l2_v1] arm %s 실패(rc=%s) — 로그 %s · 뒤 arm 중단", a, rc, log))
  }
  orch$finished_at <- now(); jw(orch, orch_path)
  cat("[run_l2_v1] 전 arm 완료\n")
} else {
  # ── arm 1개 측정 ───────────────────────────────────────────────────────────────
  if (!(ARM %in% ARMS)) stop(sprintf("[run_l2_v1] L2V1_ARM='%s' 허용 밖", ARM))
  integ <- .gate()
  out_root <- file.path(RUNS, ARM)
  if (length(list.files(out_root, pattern = "^authoritative_remeasure[.]json$", recursive = TRUE)))
    stop(sprintf("[run_l2_v1] arm %s 는 이미 측정됐다 — 재측정 금지", ARM))
  dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
  Sys.setenv(QVEST_RP_REGISTER = "0", QVEST_RP_NO_LCODE = "1", QVEST_NO_LEDGER_OPEN = "1",
             L2V1_INPUTS_SHA = sha(MAN_P), L2V1_DIAG_DIR = file.path(out_root, "engine_diag"))
  Sys.unsetenv(c("RF_CELL_SPEC", "QVEST_RP_SEED_BASE_CACHE", "QVEST_RP_NO_FACTOR_ANALYSIS"))
  source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))
  engine <- file.path(L2DIR, "allocator_engine_v1.R")
  pins <- list(prereg_id = PREREG_ID, prereg_draft_sha256 = integ$sha256, arm = ARM, layer = "L2",
               design_sha256 = sha(file.path(L2DIR, "l2v1_design.json")), inputs_manifest_sha256 = sha(MAN_P),
               engine_sha256 = sha(engine), driver_sha256 = sha(file.path(L2DIR, "run_l2_v1.R")),
               n_trials_basis = "chain — v0 T_var(PR-L2-ROLESLEEVE-V0 · 측정됨) → v1 T_var(방어 슬리브 재정의) = 2 · 대조 arm 은 선택 후보 아님",
               scope = "mechanism_only · a_eligible=false (후보 집합 사후 선정 + 1계층 C1 표식 상속 — v0 scope 승계)")
  t0 <- Sys.time()
  res <- run_paper_replication(
    strategy_name = sprintf("L2_ROLESLEEVE_V1_%s", ARM),
    strategy_idea = sprintf(paste0("2계층 역할 슬리브 로테이션 v1 arm %s — 방어 슬리브 = as-of 하방 베타 β− 하위 삼분위(Ang·Chen·Xing 2006 · ",
                                   "252일 창 t−1 끝) · 공격·반등·α = as-of 역할 · MSM as-of 고분산 확률 P 로 기울이는 배분(P·w_hi + (1−P)·w_lo · ",
                                   "w_hi={방어½,α½} · w_lo={공격⅓,반등⅓,α⅓}) · 모듈 보유 순합산 → K200∪KQ150·LIQ 2e8 · 상위 25 · Σw=1 · 월 리밸 · ",
                                   "15bps · close_t1 (%s)"), ARM, DESIGN$arms[[ARM]]$weights),
    factor_engine_path = engine,
    portfolio_spec = list(construction = "engine_direct"),
    universe = "K200_KQ150",
    source_paper = list(title = "Moreira & Muir (2017) Volatility-Managed Portfolios. Journal of Finance 72(4)",
                        url = "https://doi.org/10.1111/jofi.12513", paper_key = "doi:10.1111/jofi.12513"),
    commission_paper = 0.0015,
    start_date = "2015-09-01",
    out_root = out_root,
    send_telegram = FALSE,
    factor_analysis = FALSE,
    mechanism_hypothesis = "고분산 상태(P↑)에서 방어(저 β−)·α 슬리브로, 저분산 상태에서 공격·반등 슬리브로 기울이면 노출 맞춤 정적 혼합(K) 대비 일평균 수익이 높다(H1 · v1 방어 정의)",
    selection_type = "chain", n_trials_cumulative = 2L,
    measurement_tags = pins,
    data_cutoff = DESIGN$window$data_cutoff)
  jr <- list.files(res$out_dir, pattern = "^judge_request.*[.]json$", full.names = TRUE)
  renamed <- character(0)
  for (p in jr) { q <- sub("[.]json$", ".EXPERIMENT_HOLD.json", p); if (file.rename(p, q)) renamed <- c(renamed, basename(q)) }
  rec <- list(schema = "l2v1_run_record_v1", prereg_id = PREREG_ID, arm = ARM, out_dir = res$out_dir, strategy_id = res$strategy_id,
              grade = res$grade, essence = res$essence, n_max = res$diagnostics$n_max, has_short = res$diagnostics$has_short,
              n_rebalances = res$diagnostics$n_rebalances, avg_turnover = res$diagnostics$avg_turnover, exec_price = res$diagnostics$exec_price,
              judge_requests_renamed = as.list(renamed), pins = pins, started_at = format(t0, "%Y-%m-%dT%H:%M:%S%z"), finished_at = now(),
              minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2))
  jw(rec, file.path(out_root, "run_record.json"))
  cat(sprintf("[run_l2_v1] arm %s 완료 — 등급 %s · %s\n", ARM, res$grade, res$out_dir))
}
