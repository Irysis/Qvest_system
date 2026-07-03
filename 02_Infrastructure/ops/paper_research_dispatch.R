#!/usr/bin/env Rscript
# paper_research_dispatch.R — 라우터 STEP2/3 후속: mode_queue의 비-alpha 라우트를 *실제 리서치 액션*으로 배선 (도훈 mandate 2026-06-18).
#
# 목적: paper_router가 큐에 넣은 optimizer/risk/regime 논문을, 각 모드 하니스로 *자동 소비*하고 결과를 텔레그램+JSON으로 보고.
#   - optimizer: Σ-가중 A/B 배터리(auto_sigma_weighting_ab.R) 실행 → book-marginal ΔIR≥0.05 게이트로 "후보/레버아님" 판정.
#       (배터리는 book(캐리어) 의존이지 논문별 아님 → 오늘 결과 있으면 재사용, 없으면 1회 실행. novel method는 게이트 통과시만 수동구현 flag.)
#   - risk: risk-research stress 모듈 후보로 flag(수동 분석 — Σ/tail 보강).
#   - regime: H2 오버레이 후보로 flag(candidate timing signal 추출 필요 — 자동 불가, 수동).
# 가드: ★자본 admit/book_state 쓰기 절대 없음(governor 정지, 도훈+Q-Lead 수동). 가중 채택도 수동. 본 스크립트는 *측정·보고*만.
# 게이트: QVEST_PAPER_DISPATCH_ENABLE=1 일 때만 동작(기본 0). morning_run [0.6]에서 호출.
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); if (dir.exists(root)) setwd(root)

today <- Sys.getenv("QVEST_DISPATCH_TODAY", format(Sys.Date(), "%Y%m%d"))
stage <- "stage_artifacts/paper_recharge"
qpath <- file.path(stage, sprintf("mode_queue_%s.json", today))
if (Sys.getenv("QVEST_PAPER_DISPATCH_ENABLE", "0") != "1") { cat("[dispatch] disabled (QVEST_PAPER_DISPATCH_ENABLE!=1)\n"); quit(status = 0) }
if (!file.exists(qpath)) { cat(sprintf("[dispatch] no queue: %s\n", qpath)); quit(status = 0) }
Q <- fromJSON(qpath, simplifyVector = FALSE)
getrt <- function(rt) { x <- Q[[rt]]; if (is.null(x)) list() else x }
n_opt <- length(getrt("optimizer")); n_risk <- length(getrt("risk")); n_reg <- length(getrt("regime"))
cat(sprintf("[dispatch] queue %s: optimizer=%d risk=%d regime=%d\n", today, n_opt, n_risk, n_reg))

DELTA_IR_GATE <- 0.05   # book-marginal admission 문턱(§4) — 측정 기준만(자본 admit 아님)
actions <- list()

# ── optimizer: Σ-가중 A/B 배터리 자동 실행 + ΔIR 게이트 판정 ──
opt_verdict <- NULL
if (n_opt > 0) {
  ov_csv <- file.path("06_Registry/book_carrier", "h1b_sigma_ab_overlay.csv")
  carrier <- "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"
  # 배터리는 book(캐리어) 의존 — 캐리어보다 새로우면 재사용(매일 재실행 방지, PG2 변경 시만 재계산)
  fresh <- file.exists(ov_csv) && file.exists(carrier) && file.info(ov_csv)$mtime >= file.info(carrier)$mtime
  if (!fresh) {
    cat("[dispatch] Σ-배터리 재실행(stale 또는 부재)...\n")
    Sys.setenv(QVEST_SIGMA_AB_NORUN = "1")
    src_ok <- tryCatch({
      suppressWarnings(source("02_Infrastructure/contracts/weighted_screen_bt.R"))
      suppressWarnings(source("02_Infrastructure/ops/auto_sigma_weighting_ab.R"))
      TRUE }, error = function(e) { cat(sprintf("[dispatch] source fail: %s\n", conditionMessage(e))); FALSE })
    if (src_ok && exists("run_sigma_ab")) {
      tb <- tryCatch(run_sigma_ab(with_overlay = TRUE), error = function(e) { cat(sprintf("[dispatch] battery fail: %s\n", conditionMessage(e))); NULL })
      if (!is.null(tb)) { fwrite(tb, ov_csv); fresh <- TRUE }
    }
  } else cat("[dispatch] Σ-배터리 오늘자 결과 재사용\n")
  if (fresh && file.exists(ov_csv)) {
    tb <- fread(ov_csv)
    book_ir <- tb[method == "strategy", IR]
    oth <- tb[method != "strategy"][order(-IR)]
    best <- oth[1]
    delta <- best$IR - book_ir
    beats <- isTRUE(delta >= DELTA_IR_GATE)
    opt_verdict <- list(book_ir = round(book_ir, 3), best_method = best$method, best_ir = round(best$IR, 3),
                        delta_ir = round(delta, 3), gate = DELTA_IR_GATE, beats_book = beats,
                        verdict = if (beats) sprintf("후보: %s ΔIR=%.3f (게이트 %.2f 이상) → 수동 검수", best$method, delta, DELTA_IR_GATE)
                                  else sprintf("가중 레버 아님: book IR %.3f 최고(최선 타방법 %s %.3f, ΔIR=%.3f, 게이트 %.2f 미달) → 채택 0", book_ir, best$method, best$IR, delta, DELTA_IR_GATE))
    cat(sprintf("[dispatch:optimizer] %s\n", opt_verdict$verdict))
  }
  actions$optimizer <- list(n = n_opt, papers = lapply(getrt("optimizer"), function(p) p$title %||% p$arxiv_id),
                            verdict = opt_verdict)
}

# ── risk: 수동 분석 flag (Σ/tail/stress 보강 후보) ──
if (n_risk > 0) {
  actions$risk <- list(n = n_risk, papers = lapply(getrt("risk"), function(p) p$title %||% p$arxiv_id),
                       action = "risk-research stress/Σ 모듈 후보 — 수동 분석(자동 method 추출 불가)")
  cat(sprintf("[dispatch:risk] %d편 flag(수동)\n", n_risk))
}
# ── regime: H2 오버레이 후보 flag (candidate signal 추출 필요) ──
if (n_reg > 0) {
  actions$regime <- list(n = n_reg, papers = lapply(getrt("regime"), function(p) p$title %||% p$arxiv_id),
                         action = "H2 오버레이 후보 — candidate timing signal 추출 필요(자동 불가, 수동)")
  cat(sprintf("[dispatch:regime] %d편 flag(수동)\n", n_reg))
}

# ── 저장 + 텔레그램 ──
out <- list(date = today, schema = "paper_research_dispatch_v1",
            note = "라우터 큐 → 리서치 액션 배선. optimizer=Σ배터리 ΔIR게이트 자동, risk/regime=수동 flag. 자본 admit 없음(governor 정지).",
            actions = actions)
opath <- file.path(stage, sprintf("research_status_%s.json", today))
write(toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"), opath)
cat(sprintf("[dispatch] saved %s\n", opath))

if (Sys.getenv("QVEST_DISPATCH_NO_TG", "0") != "1") {
  tg_ok <- tryCatch({ suppressWarnings(source("02_Infrastructure/telegram/telegram_notify.R")); exists("tg_agent_brief") }, error = function(e) FALSE)
  if (tg_ok) {
    bullets <- c()
    if (!is.null(opt_verdict)) bullets <- c(bullets, sprintf("optimizer(%d편) Σ-A/B: %s", n_opt, opt_verdict$verdict))
    else if (n_opt > 0) bullets <- c(bullets, sprintf("optimizer %d편 — Σ-배터리 미실행(결과 없음)", n_opt))
    if (n_risk > 0) bullets <- c(bullets, sprintf("risk %d편 → risk-research stress/Σ 모듈 후보(수동 분석)", n_risk))
    if (n_reg > 0) bullets <- c(bullets, sprintf("regime %d편 → H2 오버레이(candidate signal 추출 필요)", n_reg))
    if (length(bullets) < 2) bullets <- c(bullets, "자본 admit 없음 — 측정·보고만(governor 정지)")
    headline <- sprintf("논문 라우트 디스패치: optimizer %d·risk %d·regime %d", n_opt, n_risk, n_reg)
    secs <- list(
      list(type = "summary", heading = "디스패치", body = headline),
      list(type = "bullet", heading = "리서치 액션", items = bullets)
    )
    tryCatch(tg_agent_brief(agent = "AlphaSearch", title = "논문 라우트 → 리서치 디스패치",
                            relaxed = TRUE, force = TRUE, lock_scope = sprintf("paper_dispatch_%s", today),
                            sections = secs),
             error = function(e) cat(sprintf("[dispatch] tg fail: %s\n", conditionMessage(e))))
  }
}
cat("[dispatch] done\n")
