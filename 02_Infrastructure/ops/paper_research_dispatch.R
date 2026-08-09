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

# >>> SCREEN_AXES_CHECK  (08_Tests/ops/test_screen_axes_check.R 가 이 블록을 원본에서 추출해 검사한다
#     — 사본 검사 금지. 마커를 바꾸면 검사기부터 고칠 것.)
# (2026-08-08 신설) STEP 1-b 2축 존재·유효성 검사.
#   배경: 라우터 프롬프트에 "optimizer/risk 항목에 shrinkage_builtin·statistic_order·screen_priority 를
#   실어라"고 적었지만, **지시만 있고 검사가 없으면 조용히 안 지켜진다**(이번 세션에서 반복 확인된 부류).
#   ★존재 검사로 유효성 검사를 대체하지 않는다 — 필드가 있어도 enum 밖 값이면 소비단이 우선순위를
#   못 매기므로 없는 것과 같다. 그래서 존재·enum 을 따로 센다.
#   차단하지 않는다(라우터는 LLM 이고 파이프 정지는 과잉). **호명 + 커버리지 기록**이 방어선이다.
SCREEN_AX_ENUM <- list(
  shrinkage_builtin = c("yes", "weak", "no"),
  statistic_order   = c("<=2nd", "higher", "tail_quantile")
)
check_screen_axes <- function(items, route) {
  n <- length(items); if (n == 0L) return(NULL)
  miss <- character(0); badv <- character(0)
  for (i in seq_len(n)) {
    p <- items[[i]]
    lbl <- p$arxiv_id %||% (p$title %||% sprintf("#%d", i))
    for (f in names(SCREEN_AX_ENUM)) {
      v <- p[[f]]
      if (is.null(v) || !nzchar(as.character(v)[1])) miss <- c(miss, sprintf("%s:%s", lbl, f))
      else if (!(as.character(v)[1] %in% SCREEN_AX_ENUM[[f]]))
        badv <- c(badv, sprintf("%s:%s=%s", lbl, f, as.character(v)[1]))
    }
    if (is.null(p$screen_priority) || !nzchar(as.character(p$screen_priority)[1]))
      miss <- c(miss, sprintf("%s:screen_priority", lbl))
  }
  n_fields <- n * (length(SCREEN_AX_ENUM) + 1L)
  cov <- 1 - (length(miss) + length(badv)) / n_fields
  if (length(miss) || length(badv)) {
    cat(sprintf("[dispatch:%s] ★STEP 1-b 2축 결손 — 커버리지 %.0f%% (결측 %d · enum밖 %d)\n",
                route, cov * 100, length(miss), length(badv)))
    if (length(miss)) cat(sprintf("    결측: %s\n", paste(utils::head(miss, 8), collapse = ", ")))
    if (length(badv)) cat(sprintf("    enum밖: %s\n", paste(utils::head(badv, 8), collapse = ", ")))
    cat("    → 라우터가 STEP 1-b 를 안 실었다. 우선순위 없이 선입선출로 소비된다(실측 3/3 미달 계열을 먼저 태울 위험).\n")
  } else cat(sprintf("[dispatch:%s] STEP 1-b 2축 커버리지 100%%\n", route))
  list(n_items = n, coverage = round(cov, 3), missing = miss, invalid_enum = badv)
}
# <<< SCREEN_AXES_CHECK

# ((b)안 2026-08-08) method 레지스트리는 **무조건** 로드한다.
#   구판 배선은 이걸 재계산 분기 *안*에 뒀다 → 캐시 재사용 날엔 triage 함수가 없어
#   risk 보고가 "triage 불가"로 퇴화했다(실측). 보고 경로는 계산 경로와 독립이어야 한다.
.reg_ok <- tryCatch({ suppressWarnings(source("02_Infrastructure/methods/method_registry.R")); TRUE },
                    error = function(e) { cat(sprintf("[dispatch] method_registry source 실패: %s\n",
                                                      conditionMessage(e))); FALSE })

# ── Σ-가중 A/B 배터리 자동 실행 + ΔIR 게이트 판정 ──
#   (2026-08-09 수리 ①) 발화 조건을 optimizer 단독 → **optimizer ∪ risk** 로 넓힌다.
#   같은 배터리가 risk 레인의 Σ-추정기 arm(`minvar@<est>`)도 잰다. 구판 `if (n_opt > 0)` 은
#   **optimizer 0편 · risk N편인 날엔 risk method 를 한 번도 안 돌렸다**(실측: 20260704 opt 0/risk 1,
#   20260702 opt 0/risk 0/regime 1). "optimizer 레인 소속"이라는 코드 배치가 곧 소비 경계였던 것.
#   (2026-08-09 수리 ②) ov_csv / battery_fresh 를 **분기 밖으로** 뺀다 — risk 보고가 이 값을 읽는데,
#   계산 분기 안에 두면 캐시 날·optimizer 0편 날에 보고가 통째로 죽는다((b)안 ④ 교훈의 재발 방지).
opt_verdict <- NULL
ov_csv <- file.path("06_Registry/book_carrier", "h1b_sigma_ab_overlay.csv")
battery_fresh <- FALSE
if (n_opt > 0 || n_risk > 0) {
  # (2026-08-08 1안 ④) 캐리어 = carrier_meta 경유 (하드코딩이 구 PG2 7주 사용의 원인 — 도훈 적발)
  carrier <- tryCatch({
    mt <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
    p <- as.character(mt$parquet %||% NA)
    if (!is.na(p) && file.exists(p)) p else "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"
  }, error = function(e) "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")
  # >>> CARRIER_IDENTITY_GATE
  # (2026-08-08 도훈 적발) ★mtime 신선도로는 **"이 입력이 아직 옳은 입력인가"**를 못 묻는다.
  #   실사고: 배터리가 캐리어 `STR_1715_AR_on_M4_R05_overlay_PG2`(2026-06-18 빌드, book_state
  #   2026-06-02 기준)를 계속 썼는데, 그 사이 book_state 는 07-19 로 갱신되고 admitted_ids 는
  #   `STR_1715_on_M4gAE_R05_noLayer4_PG2`(오토인코더 + Layer4 제거)로 바뀌어 있었다.
  #   즉 배터리는 **07-02 에 도훈이 FINAL 로 제거 지시한 Layer4/overlay 구성**을 기준선으로 재고 있었다.
  #   incumbent_book_ir 1.416 vs 배터리 strategy 팔 1.077 — 기준선이 다른 책이다.
  #   ★근본: PG2 정체성이 book_state 안에서 두 필드로 갈라져 있다.
  #     admitted_ids(권위) ≠ current_pg2_official_name(stale) → 캐리어가 stale 한 쪽을 따라갔다.
  #   ★carrier_meta.json 에 "PG2 변경 시 재실행"이 **주석으로만** 있었다. 지시는 검사가 아니다.
  #   차단하지 않는다(측정·보고 스크립트라 정지는 과잉) — 호명 + 산출물에 basis_mismatch 기록.
  carrier_identity_check <- function(carrier_path) {
    meta_p <- file.path(dirname(carrier_path), "carrier_meta.json")
    bs_p   <- "qepm/mailbox/governor/book_state.json"
    if (!file.exists(meta_p) || !file.exists(bs_p)) {
      cat("[dispatch] ★캐리어 정체성 검사 불가 — carrier_meta.json 또는 book_state.json 부재\n")
      return(list(status = "unverifiable"))
    }
    mt <- tryCatch(fromJSON(meta_p, simplifyVector = FALSE), error = function(e) NULL)
    bs <- tryCatch(fromJSON(bs_p,   simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(mt) || is.null(bs)) return(list(status = "unverifiable"))
    cstrat <- as.character(mt$strategy %||% NA)
    admit  <- unlist(bs$admitted_ids %||% list())
    c_bs_at <- as.character(mt$book_state_updated_at %||% NA)
    b_at    <- as.character(bs$updated_at %||% NA)
    id_ok   <- length(admit) > 0 && cstrat %in% admit
    # 시각 비교는 날짜까지만(타임존 표기 혼재) — 문자열 앞 10자리
    stale   <- !is.na(c_bs_at) && !is.na(b_at) && substr(c_bs_at, 1, 10) < substr(b_at, 1, 10)
    out <- list(status = if (id_ok && !stale) "ok" else "MISMATCH",
                carrier_strategy = cstrat, admitted_ids = admit,
                carrier_book_state_at = c_bs_at, book_state_updated_at = b_at,
                identity_match = id_ok, carrier_older_than_book_state = stale)
    if (!id_ok) {
      cat(sprintf("[dispatch] ★★캐리어 정체성 불일치 — 캐리어=%s 이나 현 admitted_ids=%s\n",
                  cstrat, paste(admit, collapse = ", ")))
      cat("    → 배터리 기준선이 **현 incumbent 가 아니다**. ΔIR 수치를 채택 근거로 쓰지 말 것 (§7b).\n")
    }
    if (stale) cat(sprintf("[dispatch] ★캐리어가 book_state 보다 오래됨 — 캐리어 기준 %s < book_state %s\n",
                           substr(c_bs_at, 1, 10), substr(b_at, 1, 10)))
    if (id_ok && !stale) cat("[dispatch] 캐리어 정체성 OK (현 admitted_ids 와 일치)\n")
    out
  }
  carrier_id <- carrier_identity_check(carrier)
  # <<< CARRIER_IDENTITY_GATE

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
    # ★(2026-08-09) 배터리가 **source 하는 측정 코드**도 입력이다.
    #   실사고: 08-08 08:40:57 에 auto_sigma_weighting_ab.R 의 오버레이 노출 산출을
    #   구 2-1 layer5 CSV → 캐리어 `invested` 실측으로 고쳤는데, 결과 CSV 가 08:42(더 나중)라
    #   게이트는 그 수리를 **낡은 것으로 보지 못했다**. 그날 rawdata 가 갱신된 덕에 우연히
    #   재실행돼 반영됐을 뿐이고(book IR 1.077 → 1.410), 데이터가 안 움직였으면 수리는 잤다.
    #   측정 primitive(weighted_screen_bt) · 가중 커널(hrp_core) · 제약 정규화(strategy_tilt_weights)
    #   는 전부 결과를 바꾸는 코드이므로 신선도 판정 근거에 넣는다.
    "02_Infrastructure/contracts/weighted_screen_bt.R",
    "02_Infrastructure/portfolio/hrp_core.R",
    "02_Infrastructure/portfolio/strategy_tilt_weights.R",
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
      # risk 레인: Σ 추정기 교체 A/B (`minvar@<est_id>`). 비중 규칙 고정 → 차이 = 추정기.
      .ests <- tryCatch(load_sigma_estimators(),
                        error = function(e) { cat(sprintf("[dispatch] sigma estimator load fail: %s\n",
                                                          conditionMessage(e))); list() })
      tb <- tryCatch(run_sigma_ab(with_overlay = TRUE, extra_adapters = .extra, sigma_estimators = .ests),
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
                            method_triage = if (exists("method_triage")) method_triage("optimizer") else NULL,
                            screen_axes = check_screen_axes(getrt("optimizer"), "optimizer"),
                            # ★기준선 정체성을 산출물에 박는다 — 나중에 이 수치를 인용할 때
                            #   어느 책 위에서 잰 것인지 파일만 보고 알 수 있어야 한다(§7b).
                            baseline_identity = if (exists("carrier_id")) carrier_id else NULL)
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
                       screen_axes = check_screen_axes(getrt("risk"), "risk"),
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
