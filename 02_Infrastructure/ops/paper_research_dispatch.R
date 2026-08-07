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
# >>> MODE_QUEUE_ROUTE_RESOLVER  (08_Tests/ops/test_mode_queue_dispatch_schema.R 가 이 블록을
#     원본에서 추출해 검사한다 — 사본 검사 금지. 마커를 바꾸면 검사기부터 고칠 것.)
# (2026-08-02 수리) 생산자 스키마 2형태 관용.
#   실사고: mode_queue_20260727.json 은 3키를 최상위가 아니라 `queue`{} 안에 넣었는데
#   구 resolver 는 최상위만 봐서 optimizer=0 risk=0 regime=0 으로 읽었다 →
#   research_status_20260727.json::actions = [] 로 **14편(opt 7·risk 4·regime 3) 전량 드롭**.
#   optimizer 7편은 Σ-가중 A/B 배터리를 타야 했는데 한 편도 돌지 않았다.
#   ★schema_version 으로 분기할 수 없다 — 07-27 은 "mode_queue_v1", 08-02 는 "paper_router_v2"
#     (생산자 이름)라 그 필드가 형태를 구별하지 못한다. 그래서 모양으로 해석한다.
#   생산자 정본 = 평면(paper_router_prompt.md §STEP3). queue{} 는 관용 수용일 뿐이다.
getrt <- function(rt) {
  x <- Q[[rt]]
  if (is.null(x) && is.list(Q[["queue"]])) x <- Q[["queue"]][[rt]]
  if (is.null(x)) list() else x
}
# <<< MODE_QUEUE_ROUTE_RESOLVER
n_opt <- length(getrt("optimizer")); n_risk <- length(getrt("risk")); n_reg <- length(getrt("regime"))
cat(sprintf("[dispatch] queue %s: optimizer=%d risk=%d regime=%d\n", today, n_opt, n_risk, n_reg))
# ★미해석 경고 — 큐 파일에 내용이 있는데 3라우트가 전부 비면 스키마 드리프트다.
#   "0편"과 "못 읽음"은 겉보기가 같으므로 숨기지 않고 이름을 부른다(차단은 아님).
if (n_opt + n_risk + n_reg == 0) {
  .known <- c("date", "schema", "schema_version", "note", "dispatch_note",
              "generated_by", "generated_at", "source", "router_version")
  .other <- setdiff(names(Q), c(.known, "optimizer", "risk", "regime"))
  if (length(.other) > 0)
    cat(sprintf("[dispatch] ★경고: 3라우트가 전부 비었는데 미해석 키가 있다 — 스키마 드리프트 의심: %s (%s)\n",
                paste(.other, collapse = ", "), basename(qpath)))
}

DELTA_IR_GATE <- 0.05   # book-marginal admission 문턱(§4) — 측정 기준만(자본 admit 아님)
actions <- list()

# ((b)안 2026-08-08) method 레지스트리는 **무조건** 로드한다.
#   구판 배선은 이걸 재계산 분기 *안*에 뒀다 → 캐시 재사용 날엔 triage 함수가 없어
#   risk 보고가 "triage 불가"로 퇴화했다(실측). 보고 경로는 계산 경로와 독립이어야 한다.
.reg_ok <- tryCatch({ suppressWarnings(source("02_Infrastructure/methods/method_registry.R")); TRUE },
                    error = function(e) { cat(sprintf("[dispatch] method_registry source 실패: %s\n",
                                                      conditionMessage(e))); FALSE })

# ── optimizer: Σ-가중 A/B 배터리 자동 실행 + ΔIR 게이트 판정 ──
opt_verdict <- NULL
if (n_opt > 0) {
  ov_csv <- file.path("06_Registry/book_carrier", "h1b_sigma_ab_overlay.csv")
  carrier <- "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"
  # >>> SIGMA_AB_FRESHNESS_GATE
  # (2026-08-08 수리) 구 게이트 = `ov_csv$mtime >= carrier$mtime` 단독.
  #   ★캐리어는 PG2 재구성 때만 갱신되므로 한 번 배터리를 돌린 뒤엔 **영구 참**이 된다.
  #   실사고: carrier 06-18 14:15 / ov_csv 06-18 16:46 → 07-01·07-26·08-02·08-04·08-06
  #   research_status 가 전부 동일값(book_ir 1.209 / EW 1.106 / ΔIR −0.103, n_months 269).
  #   **7주간 캐시 1벌을 "오늘의 optimizer 판정"으로 텔레그램까지 재발송**했다.
  #   "재계산 회피"로 쓴 게이트가 실제로는 **재계산 영구 정지**였다.
  # 수리 2축: ① 캐리어가 아니라 배터리가 *실제로 읽는 입력 전부* 와 비교(auto_sigma_weighting_ab.R
  #   run_sigma_ab/build_period_bench/build_overlay_exposure 인자 = 아래 4종)
  #   ② 입력 mtime 이 우연히 안 움직여도 새 실현월은 반영되도록 max-age 백스톱(35일).
  #   현 상태에서 ①만으로도 stale 판정된다(rawdata 08-08 00:09 ≫ ov_csv 06-18) — 실측 확인.
  SIGMA_AB_MAX_AGE_DAYS <- 35
  sigma_ab_inputs <- c(
    carrier,
    ".cache/rawdata.parquet",
    ".cache/benchmark.parquet",
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv",
    # ★(2026-08-08 (b)안) **method 집합도 입력이다.**
    #   데이터가 그대로여도 새 논문 method 를 등록하면 캐시는 낡은 것이다. 구판 게이트는
    #   데이터 staleness 만 봐서, ConformalKelly 를 등재한 직후 실행이 "오늘자 결과 재사용"으로
    #   **새 method 를 한 번도 안 돌리고** 종료했다(실측). 배터리 코드 자체도 같은 이유로 포함.
    "06_Registry/method_registry.json",
    "02_Infrastructure/ops/auto_sigma_weighting_ab.R",
    "02_Infrastructure/methods/method_registry.R",
    list.files("02_Infrastructure/methods/adapters", pattern = "\\.R$", full.names = TRUE)
  )
  .in_present <- sigma_ab_inputs[file.exists(sigma_ab_inputs)]
  fresh <- FALSE; .stale_why <- "결과 파일 없음"
  if (file.exists(ov_csv)) {
    .out_m <- file.info(ov_csv)$mtime
    .age_d <- as.numeric(difftime(Sys.time(), .out_m, units = "days"))
    if (length(.in_present) == 0L) {
      # ★입력이 하나도 없으면 "최신"이 아니라 **판정 불가**다 — 부재를 fresh 로 내려앉히지 않는다.
      .stale_why <- "입력 4종 전부 부재 — 신선도 판정 불가"
    } else {
      .newest_in <- max(file.info(.in_present)$mtime)
      if (.age_d > SIGMA_AB_MAX_AGE_DAYS) {
        .stale_why <- sprintf("결과 나이 %.0f일 > 백스톱 %d일", .age_d, SIGMA_AB_MAX_AGE_DAYS)
      } else if (.out_m < .newest_in) {
        .stale_why <- sprintf("입력이 더 새로움 (최신 입력 %s > 결과 %s)",
                              format(.newest_in, "%Y-%m-%d %H:%M"), format(.out_m, "%Y-%m-%d %H:%M"))
      } else { fresh <- TRUE }
    }
    if (length(.in_present) < length(sigma_ab_inputs))
      cat(sprintf("[dispatch] ★입력 %d/%d 부재 — 신선도 판정 근거 축소: %s\n",
                  length(sigma_ab_inputs) - length(.in_present), length(sigma_ab_inputs),
                  paste(basename(setdiff(sigma_ab_inputs, .in_present)), collapse = ", ")))
  }
  if (!fresh) cat(sprintf("[dispatch] Σ-배터리 stale 판정: %s\n", .stale_why))
  # <<< SIGMA_AB_FRESHNESS_GATE
  if (!fresh) {
    cat("[dispatch] Σ-배터리 재실행(stale 또는 부재)...\n")
    Sys.setenv(QVEST_SIGMA_AB_NORUN = "1")
    src_ok <- tryCatch({
      suppressWarnings(source("02_Infrastructure/contracts/weighted_screen_bt.R"))
      suppressWarnings(source("02_Infrastructure/ops/auto_sigma_weighting_ab.R"))
      TRUE }, error = function(e) { cat(sprintf("[dispatch] source fail: %s\n", conditionMessage(e))); FALSE })
    if (src_ok && exists("run_sigma_ab")) {
      # ((b)안 2026-08-08) 논문 유래 method 어댑터 합류 — 이게 "논문이 실제로 소비되는" 지점이다.
      #   구판은 여기서 배터리를 **고정 6종**으로만 돌려, 그날 라우팅된 논문은 제목만 기록됐다.
      .extra <- tryCatch(load_method_adapters(route = "optimizer"),
                         error = function(e) { cat(sprintf("[dispatch] method registry fail: %s\n",
                                                           conditionMessage(e))); list() })
      tb <- tryCatch(run_sigma_ab(with_overlay = TRUE, extra_adapters = .extra),
                     error = function(e) { cat(sprintf("[dispatch] battery fail: %s\n", conditionMessage(e))); NULL })
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
                            verdict = opt_verdict,
                            method_triage = if (exists("method_triage")) method_triage("optimizer") else NULL)
}

# ── risk: method 레지스트리 triage ((b)안 2026-08-08) ──
#   구판은 문자열 flag 한 줄("수동 분석")만 남겼다 — 등재와 처분이 구별되지 않아, 큐가 쌓여도
#   무엇이 왜 안 돌았는지 기록에 없었다. 이제 레지스트리 verdict/blocker 를 그대로 싣는다.
#   ★risk 레인 하네스(Σ-교체 A/B)는 아직 미배선이다. 그 사실을 **숨기지 않고 이름을 부른다** —
#     "수동 분석"은 처분처럼 보이지만 실제로는 아무도 안 본다는 뜻이었다.
if (n_risk > 0) {
  .rt <- if (exists("method_triage")) method_triage("risk") else list()
  actions$risk <- list(n = n_risk, papers = lapply(getrt("risk"), function(p) p$title %||% p$arxiv_id),
                       method_triage = .rt,
                       harness_status = "risk 레인 Σ-교체 A/B 하네스 미배선 — optimizer 레인 검증 후 착수 예정",
                       action = if (length(.rt)) sprintf("레지스트리 등재 %d건 (verdict 별도) — 자동 측정 아직 없음", length(.rt))
                                else "레지스트리 미등재 — triage 필요")
  cat(sprintf("[dispatch:risk] %d편 · %s\n", n_risk,
              if (exists("method_triage_line")) method_triage_line("risk") else "triage 불가"))
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
