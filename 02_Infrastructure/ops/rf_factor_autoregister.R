#!/usr/bin/env Rscript
#==============================================================================
# rf_factor_autoregister.R — 충실구현 **B등급 이상 신호를 팩터 DB 에 무인 등록** (2026-09-01 도훈 지시)
#
# 왜: 충실구현이 낸 신호가 어디에도 적립되지 않았다. B+ 를 받은 논문 신호도 그 논문의 25칸이
#   끝나면 사라지고, **다음 논문의 B1 조합 후보가 되지 못한다**. 팩터 DB 는 373종을 담고 매일
#   갱신되는데 리서치가 만든 신호가 그 안으로 들어가는 길이 없었다. 이 파일이 그 길이다 —
#   리서치 산출이 다음 리서치의 입력이 되는 닫힌 루프.
#
# ★기존 온보딩 계약을 우회하지 않는다: add_factor() -> build_factor_db() ->
#   backfill_custom_factor() -> compute_all_factor_ic_monthly(). parquet 직접 쓰기 없음.
#   막히던 지점 하나(수식 템플릿만 허용)는 engine 템플릿 신설로 풀었다.
#
# 발화 조건 (전부 만족해야 등록):
#   ① essence_grade ∈ {A,B}  (문턱 = config factor_autoregister.min_grade)
#   ② factors_panel.parquet 존재 (FACTORS 형 엔진). PORTFOLIO 형은 스코어가 없어 사유 남기고 건너뜀
#   ③ 기존 팩터와 중복 아님 (횡단면 rank 상관 max|rho| <= dedup_rho_max)
#   ④ add_factor 의 기존 중복 id 거부는 그대로
#
# 실패는 조용히 넘기지 않는다 — 사유를 로그에 남기고 등록하지 않는다.
# 사용: Rscript rf_factor_autoregister.R <artifacts_dir> [engine_path] [paper_key]
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT)
LOG_P <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
CFG_P <- { .c <- Sys.getenv("QVEST_RF_CONFIG", ""); if (nzchar(.c) && file.exists(.c)) .c
           else file.path(ROOT, "06_Registry/reinforce_auto_config.json") }

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "factor_autoreg"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[fautoreg] %s %s\n", event,
              paste(names(rec)[-(1:3)], unlist(lapply(rec[-(1:3)], function(z) substr(paste(z, collapse=","), 1, 90))),
                    sep = "=", collapse = " ")))
}

#' 등록 브리핑 sections — ★발신기 계약: tg_agent_brief 에는 `body` 인자가 **없다**(sections 배열이다).
#'   2026-09-21 수리: 구판이 body= 를 넘겨 매번 `사용되지 않은 인자 (body = ...)` 로 죽었다.
#'   결과 — 이 레인의 **유일한 성공 등록**(2026-09-17 RP_combo_1403_8125…)이 그대로 침묵했다.
#'   발화했는데 아무도 몰랐다는 것이 이 결함의 크기다(침묵 실패).
#'   ★인라인으로 두지 않는 이유: 호출부 안에 있으면 드라이런 양성 대조를 걸 자리가 없다.
#'   상한은 relaxed 없이도 통과하도록 잡는다(summary 20~100 · text 30~220 · bullet <=80 · 섹션 >=2 · >=400B).
rf_fa_brief_sections <- function(fid, grade, n_rows, d_from, d_to, max_rho, worst, rho_max) {
  .rho <- if (is.finite(max_rho %||% NA_real_)) sprintf("%.3f", max_rho) else "NA"
  .nr  <- format(as.integer(n_rows), big.mark = ",")
  list(
    # ★SKILL.md 6.1 필수 4종(단계/대상/위치/직전 판정) — 없으면 발신기가 v8 WARN 을 낸다.
    #   "지금 어디서 무엇을 돌고 있는지" 가 최상단에 없으면 무인 브리핑은 연속성을 잃는다.
    list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
         items = c("단계: 1계층 충실구현 — 무인 팩터 등록 레인",
                   substr(sprintf("대상: %s", fid), 1, 78),
                   "위치: 팩터 DB 등재 완료 · B1 조합 후보 풀 편입 대기",
                   substr(sprintf("직전 판정: 권위 등급 %s · 중복 max|rho| %s", grade, .rho), 1, 78))),
    list(type = "summary", emoji = "\U0001F52D",
         body = substr(sprintf("논문 충실구현 신호를 팩터 DB 에 등록했습니다 — 등급 %s · 패널 %s행.",
                               grade, .nr), 1, 100)),
    list(type = "bullet", emoji = "\U0001F4E6", heading = "등록 내역",
         items = c(substr(sprintf("id: %s", fid), 1, 78),
                   substr(sprintf("등급: %s (문턱 B) · 패널 %s행", grade, .nr), 1, 78),
                   substr(sprintf("기간: %s ~ %s", d_from, d_to), 1, 78),
                   substr(sprintf("중복 판정: max|rho| %s (%s) · 문턱 %s",
                                  .rho, worst %||% "-", rho_max), 1, 78))),
    list(type = "text", emoji = "\U0001F501", heading = "다음",
         body = substr(sprintf(paste0("다음 논문의 B1 조합 후보 풀에 들어갑니다. IC 이력이 서야 후보가 ",
                                      "되므로 야간 백필 tick 이 이어받습니다. 되돌리기 = ",
                                      "remove_custom_factor(\"%s\", from_registry=TRUE)"), fid), 1, 220))
  )
}

#' 신규 패널이 기존 팩터의 재구현인가 — 횡단면 rank 상관으로 판정
#' ★"모멘텀 12-1 재구현"이 새 팩터로 등록되는 것을 막는다. 등록 **전에** 재야 의미가 있다.
rf_panel_dedup <- function(PN, n_months = 6L, root = ROOT) {
  suppressMessages(source(file.path(root, "02_Infrastructure/factor_db/factor_db_connector.R")))
  ds <- sort(unique(PN$Date), decreasing = TRUE)
  ds <- ds[seq_len(min(n_months, length(ds)))]
  acc <- list()
  for (d in ds) {
    d <- as.Date(d, origin = "1970-01-01")
    F0 <- tryCatch(as.data.table(load_month_factors(d)), error = function(e) NULL)   # C15 단일 경유
    if (is.null(F0) || !nrow(F0) || !("Z_Score_Aligned" %in% names(F0))) next
    P0 <- PN[Date == d, .(Ticker = as.character(Ticker), s = as.numeric(Score))]
    if (nrow(P0) < 30L) next
    M <- merge(F0[, .(Ticker = as.character(Ticker), Factor_Name, z = as.numeric(Z_Score_Aligned))],
               P0, by = "Ticker")
    if (!nrow(M)) next
    r <- M[, .(rho = { if (.N < 30L) NA_real_ else
      suppressWarnings(stats::cor(z, s, method = "spearman", use = "complete.obs")) }), by = Factor_Name]
    acc[[length(acc) + 1L]] <- r[is.finite(rho)]
  }
  if (!length(acc)) return(list(ok = NA, max_rho = NA_real_, worst = NA_character_, n_months = 0L))
  A <- rbindlist(acc)[, .(rho = mean(abs(rho))), by = Factor_Name][order(-rho)]
  list(ok = TRUE, max_rho = A$rho[1], worst = A$Factor_Name[1], n_months = length(acc), top = head(A, 5))
}

main <- function(argv) {
  if (nzchar(Sys.getenv("QVEST_RP_NO_FACTOR_REGISTER", ""))) { jlog("halt_kill_switch"); return(0L) }
  CFG <- if (file.exists(CFG_P)) fromJSON(CFG_P, simplifyVector = FALSE) else list()
  FA  <- CFG$factor_autoregister %||% list()
  if (!isTRUE(FA$enabled %||% FALSE)) { jlog("halt_disabled"); return(0L) }

  ART <- argv[1] %||% ""
  if (!nzchar(ART) || !dir.exists(ART)) { jlog("halt_no_artifacts", art = ART); return(0L) }
  AR_P <- file.path(ART, "authoritative_remeasure.json")
  if (!file.exists(AR_P)) { jlog("halt_no_remeasure", art = ART); return(0L) }
  AR <- fromJSON(AR_P, simplifyVector = FALSE)

  # ── ① 등급 게이트 (권위 등급만 인용 — 손계산 금지) ────────────────────────
  grade <- as.character(AR$essence_grade %||% "NA")
  minG  <- as.character(FA$min_grade %||% "B")
  ord <- c(A = 1, B = 2, C = 3, F = 4)
  if (is.na(ord[grade]) || ord[grade] > (ord[minG] %||% 2)) {
    jlog("skip_grade", grade = grade, min_grade = minG,
         note = "문턱 미달 — 등록하지 않는다(측정·기록은 산출물에 남는다)"); return(0L) }

  # ── ② FACTORS 형인가 (PORTFOLIO 형은 스코어가 없다) ───────────────────────
  PN_P <- file.path(ART, "factors_panel.parquet")
  if (!file.exists(PN_P)) {
    jlog("skip_no_panel", art = ART,
         note = "factors_panel 부재 — PORTFOLIO 형 엔진이거나 구 산출물. 조용히 넘기지 않고 기록한다")
    return(0L) }
  suppressMessages(library(arrow))
  PN <- as.data.table(arrow::read_parquet(PN_P))
  if (!all(c("Date", "Ticker", "Score") %in% names(PN)) || !nrow(PN)) {
    jlog("skip_bad_panel", art = ART); return(0L) }
  if (!inherits(PN$Date, "Date")) PN[, Date := as.Date(Date)]

  paper_key <- argv[3] %||% (AR$replication$source_paper$paper_key %||% "")
  if (!nzchar(paper_key)) paper_key <- as.character(AR$strategy_id %||% "unknown")
  fid <- paste0("RP_", gsub("[^A-Za-z0-9]", "_", paper_key))
  fid <- substr(fid, 1, 40)

  # ── ③ 중복 판정 (등록 전에 잰다) ──────────────────────────────────────────
  DD <- tryCatch(rf_panel_dedup(PN, root = ROOT), error = function(e) {
    jlog("dedup_failed", err = conditionMessage(e)); list(ok = NA, max_rho = NA_real_) })
  rho_max <- as.numeric(FA$dedup_rho_max %||% 0.8)
  if (isTRUE(DD$ok) && is.finite(DD$max_rho) && DD$max_rho > rho_max) {
    jlog("skip_duplicate", id = fid, max_rho = round(DD$max_rho, 4), worst = DD$worst,
         threshold = rho_max, n_months = DD$n_months,
         note = "기존 팩터의 재구현 — 등록하지 않는다(어느 팩터와 겹치는지 기록)")
    return(0L) }

  # ── 동결 (재현 가능 + 빠름) ───────────────────────────────────────────────
  FRZ <- file.path(ROOT, ".cache/factor_db/engine_frozen")
  dir.create(FRZ, recursive = TRUE, showWarnings = FALSE)
  panel_frozen <- file.path(FRZ, sprintf("%s_panel.parquet", fid))
  file.copy(PN_P, panel_frozen, overwrite = TRUE)
  eng <- argv[2] %||% ""
  if (nzchar(eng) && file.exists(eng)) file.copy(eng, file.path(FRZ, sprintf("%s_engine.R", fid)), overwrite = TRUE)

  # ── 등록 (기존 온보딩 계약 경유 — parquet 직접 쓰기 없음) ─────────────────
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/factor_db/add_factor.R")))
  sp <- AR$replication$source_paper %||% list()
  ok <- tryCatch({
    add_factor(id = fid,
               name = substr(as.character(sp$title %||% AR$strategy_name %||% fid), 1, 120),
               category = as.character(FA$category %||% "custom"),
               template = "engine",
               params = list(panel_path = panel_frozen),
               direction = "higher_better",          # 엔진 스코어는 내림차순 정렬이 곧 선호
               source = "rawdata",
               evidence_tier = grade,
               definition = sprintf("논문 충실구현 신호(동결 패널). 출처: %s · 등급 %s · 패널 %d행 %s~%s",
                                    as.character(sp$url %||% "?"), grade, nrow(PN),
                                    as.character(min(PN$Date)), as.character(max(PN$Date))),
               note = sprintf("origin=paper_replication_auto · artifacts=%s · dedup max|rho|=%s(%s)",
                              ART, if (is.finite(DD$max_rho %||% NA)) round(DD$max_rho, 4) else "NA",
                              DD$worst %||% "-"))
    TRUE }, error = function(e) { jlog("register_failed", id = fid, err = conditionMessage(e)); FALSE })
  if (!isTRUE(ok)) return(1L)
  jlog("factor_registered", id = fid, grade = grade, paper = paper_key,
       max_rho = if (is.finite(DD$max_rho %||% NA)) round(DD$max_rho, 4) else NA,
       panel_rows = nrow(PN), panel = panel_frozen)

  # ── 후속: 이력 + ★IC (이걸 빼면 Z_Score_Aligned 가 안 서서 방향이 조용히 뒤집힌다) ──
  tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_builder.R")))
    backfill_custom_factor(fid)
    jlog("backfill_done", id = fid)
    compute_all_factor_ic_monthly()
    jlog("ic_refreshed", id = fid,
         note = "★필수 후속 — 없으면 커넥터의 Z_Score_Aligned(C13 방향 정렬)가 이 팩터에 서지 않는다")
  }, error = function(e) jlog("post_register_failed", id = fid, err = conditionMessage(e),
                              note = "등록은 됐으나 이력/IC 미완 — 다음 [6c] 백필 tick 이 이어받는다"))

  tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
    .res <- tg_agent_brief(agent = "AlphaSearch", relaxed = TRUE,
      lock_scope = sprintf("rf_factor_autoreg_%s", fid),
      title = substr(sprintf("[1계층] 팩터 DB 자동등록 — %s (등급 %s)", fid, grade), 1, 120),
      sections = rf_fa_brief_sections(
        fid = fid, grade = grade, n_rows = nrow(PN),
        d_from = as.character(min(PN$Date)), d_to = as.character(max(PN$Date)),
        max_rho = DD$max_rho %||% NA_real_, worst = DD$worst, rho_max = rho_max))
    # ★발신기가 list(ok=FALSE, error=…) 로 **조용히** 돌아오는 경로가 있다 — 그것도 실패다.
    #   예외만 잡으면 이 레인은 또 발화한 줄 모른다.
    if (!isTRUE((.res %||% list())$ok)) jlog("telegram_failed", err = (.res %||% list())$error %||% "ok!=TRUE")
    else jlog("telegram_sent", id = fid, bytes = (.res %||% list())$bytes %||% NA)
  }, error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  0L
}

rc <- tryCatch(main(commandArgs(trailingOnly = TRUE)), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
