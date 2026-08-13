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

# ── 공용 신선도 판정 (2026-08-09) ─────────────────────────────────────────────
#   Σ 배터리의 SIGMA_AB_FRESHNESS_GATE 와 **같은 규약**의 함수판. regime 배터리가 쓴다.
#   ★Σ 쪽 마커 블록은 검사기가 원본에서 추출하므로 건드리지 않는다(추출 계약). 대신 새 소비자는
#     이 함수를 쓰게 해서 규약이 세 번째로 복사되는 것을 막는다 — 술어 3중 재구현이 이 저장소의
#     반복 결함이었다([[project-wiring-map-standards-unconsumed-20260808]]).
#   규약 2축: ① 결과가 **실제로 읽는 입력 전부**보다 새로운가 ② max-age 백스톱
#     (입력 mtime 이 우연히 안 움직여도 새 실현월이 반영되도록).
#   ★입력이 하나도 없으면 "최신"이 아니라 **판정 불가** — 부재를 fresh 로 내려앉히지 않는다.
# ── 커버리지 게이트 (2026-08-09, 도훈 "269개월 하드코딩 없애고 최신 데이터 기반으로") ──
#   ★신선도와 커버리지는 **다른 질문**이다:
#     신선도 = "입력 파일이 바뀌었나"(mtime)  /  커버리지 = "측정창이 최신 데이터까지 닿나"
#   실사고: 배터리가 269개월을 재고 있었는데 북은 271개월(2026-08)까지 있었다. 269 는 **어디에도
#   하드코딩돼 있지 않았다** — 상류 per-stock 캐리어가 2026-06-18 빌드에서 얼어붙었고,
#   07-19 PG2 전환 때 `book_carrier_sources.json` 매핑이 갱신되지 않아 재생산이 stop() 으로
#   막혀 있었다. 신선도 게이트는 이걸 못 본다(캐리어 파일은 안 바뀌었으니 '최신'이다).
#   ⇒ 창이 뒤처져도 **아무 로그도 말해주지 않는 상태**였다. 이 함수가 그 침묵을 없앤다.
#   차단하지 않는다(측정·보고 스크립트) — 호명 + 산출물에 lag 기록이 방어선이다.
coverage_check <- function(carrier_path, label = "battery") {
  out <- list(status = "unverifiable", carrier_ym_max = NA_character_,
              book_ym_max = NA_character_, lag_months = NA_integer_)
  bsp <- tryCatch({
    bs <- fromJSON("qepm/mailbox/governor/book_state.json", simplifyVector = TRUE)
    sprintf("06_Registry/live_track/%s/live_book_series.csv", as.character(bs$admitted_ids)[1])
  }, error = function(e) NA_character_)
  if (is.na(carrier_path) || !file.exists(carrier_path) || is.na(bsp) || !file.exists(bsp)) {
    cat(sprintf("[dispatch:%s] ★커버리지 판정 불가 — 캐리어 또는 북 시계열 부재\n", label)); return(out)
  }
  cy <- tryCatch({
    d <- as.data.table(arrow::read_parquet(carrier_path, col_select = "eval_date"))
    max(format(as.Date(d$eval_date), "%Y-%m")) }, error = function(e) NA_character_)
  by <- tryCatch(max(fread(bsp)$realized_ym), error = function(e) NA_character_)
  if (is.na(cy) || is.na(by)) return(out)
  lag <- length(seq(as.Date(paste0(cy, "-01")), as.Date(paste0(by, "-01")), by = "month")) - 1L
  out <- list(status = if (lag <= 0) "current" else "BEHIND",
              carrier_ym_max = cy, book_ym_max = by, lag_months = lag,
              note = if (lag > 0)
                "측정창이 북보다 뒤처짐 — per-stock 캐리어 재생산 필요(extract_book_carrier.R → extract_book_carrier_d3.R). D3 빌더는 재현 cor<0.999 시 fail-closed 로 저장을 거부한다."
              else "측정창 = 북 최신월")
  if (lag > 0) {
    cat(sprintf("[dispatch:%s] ★★커버리지 뒤처짐 %d개월 — 캐리어 %s vs 북 %s\n", label, lag, cy, by))
    cat(sprintf("    → 이 배터리 수치는 **최신 %d개월을 못 본 창**에서 잰 것이다. 인용 시 창을 병기할 것.\n", lag))
  } else cat(sprintf("[dispatch:%s] 커버리지 OK — 캐리어 %s = 북 %s\n", label, cy, by))
  out
}

stale_check <- function(out_path, inputs, max_age_days = 35, label = "battery") {
  present <- inputs[file.exists(inputs)]
  if (length(present) < length(inputs))
    cat(sprintf("[dispatch:%s] ★입력 %d/%d 부재 — 신선도 판정 근거 축소: %s\n", label,
                length(inputs) - length(present), length(inputs),
                paste(basename(setdiff(inputs, present)), collapse = ", ")))
  if (!file.exists(out_path)) return(list(fresh = FALSE, why = "결과 파일 없음"))
  if (length(present) == 0L) return(list(fresh = FALSE, why = "입력 전부 부재 — 신선도 판정 불가"))
  out_m <- file.info(out_path)$mtime
  age_d <- as.numeric(difftime(Sys.time(), out_m, units = "days"))
  newest <- max(file.info(present)$mtime)
  if (age_d > max_age_days)
    return(list(fresh = FALSE, why = sprintf("결과 나이 %.0f일 > 백스톱 %d일", age_d, max_age_days)))
  if (out_m < newest)
    return(list(fresh = FALSE, why = sprintf("입력이 더 새로움 (최신 입력 %s > 결과 %s)",
                                             format(newest, "%Y-%m-%d %H:%M"), format(out_m, "%Y-%m-%d %H:%M"))))
  list(fresh = TRUE, why = "")
}

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
  # ★정체성(맞는 책인가)과 커버리지(최신까지 닿는가)는 다른 질문 — 둘 다 묻는다.
  carrier_cov <- coverage_check(carrier, "optimizer")

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
  battery_fresh <- isTRUE(fresh)     # ★risk 보고가 분기 밖에서 읽는다 (수리 ②)
  if (fresh && file.exists(ov_csv) && n_opt > 0) {
    tb <- fread(ov_csv)
    book_ir <- tb[method == "strategy", IR]
    oth <- tb[method != "strategy"][order(-IR)]
    best <- oth[1]
    delta <- best$IR - book_ir
    beats <- isTRUE(delta >= DELTA_IR_GATE)
    # ★(2026-08-09) arm 풀에는 **risk 라우트 유래 arm 도 섞여 있다**(같은 배터리가 잰다).
    #   그래서 "최선 타방법"이 risk 논문일 수 있고, 그걸 optimizer 판정으로만 적으면 출처가 지워진다.
    #   레인 라벨을 함께 싣는다 — 수치가 어느 레인 것인지 파일만 보고 알 수 있어야 한다.
    .rk_arms <- if (exists("risk_lane_arms")) tryCatch(vapply(risk_lane_arms(), function(a) a$arm, character(1)),
                                                      error = function(e) character(0)) else character(0)
    opt_verdict <- list(book_ir = round(book_ir, 3), best_method = best$method, best_ir = round(best$IR, 3),
                        best_method_route = if (best$method %in% .rk_arms) "risk" else "optimizer_or_builtin",
                        n_arms = nrow(oth), n_risk_route_arms = sum(.rk_arms %in% oth$method),
                        delta_ir = round(delta, 3), gate = DELTA_IR_GATE, beats_book = beats,
                        verdict = if (beats) sprintf("후보: %s ΔIR=%.3f (게이트 %.2f 이상) → 수동 검수", best$method, delta, DELTA_IR_GATE)
                                  else sprintf("가중 레버 아님: book IR %.3f 최고(최선 타방법 %s %.3f, ΔIR=%.3f, 게이트 %.2f 미달) → 채택 0", book_ir, best$method, best$IR, delta, DELTA_IR_GATE))
    cat(sprintf("[dispatch:optimizer] %s\n", opt_verdict$verdict))
  }
  # ★배터리는 risk 만 있는 날에도 돌지만, optimizer *블록*은 optimizer 논문이 있을 때만 쓴다.
  #   (중괄호 필수 — 이 저장소는 `if (..)` 다음 줄 표현식으로 파스 사고를 낸 전례가 있다.)
  if (n_opt > 0) {
    actions$optimizer <- list(n = n_opt, papers = lapply(getrt("optimizer"), function(p) p$title %||% p$arxiv_id),
                              verdict = opt_verdict,
                              method_triage = if (exists("method_triage")) method_triage("optimizer") else NULL,
                              screen_axes = check_screen_axes(getrt("optimizer"), "optimizer"),
                              # ★기준선 정체성을 산출물에 박는다 — 나중에 이 수치를 인용할 때
                              #   어느 책 위에서 잰 것인지 파일만 보고 알 수 있어야 한다(§7b).
                              baseline_identity = if (exists("carrier_id")) carrier_id else NULL,
                              # ★측정창을 산출물에 박는다 — "몇 개월로 잰 수치인가"가 파일만 보고 보여야 한다.
                              coverage = if (exists("carrier_cov")) carrier_cov else NULL)
  }
}

# ── risk: method triage + **레인 판정** (2026-08-09 수리 ③) ──
#   구판 이력: ① 06-18~08-07 = 문자열 flag 한 줄("수동 분석") ② 08-08 (b)안 = 레지스트리
#   verdict/blocker 등재. 그런데 ②에서도 `harness_status`/`action` 이 **하드코딩 문자열**이라,
#   ★08-09 실측에서 배터리가 risk method 2건을 실제로 쟀는데도(overlay CSV:
#     minvar@ProperScoreGASFilter IR 0.920 · PreferenceRobustDistortion 0.658)
#     산출물은 "하네스 미배선 · 자동 측정 아직 없음" 으로 **자기 실측을 부정**했다.
#     등재≠처분 계통의 반대 방향 판본 — 이번엔 과소보고다. 상태는 선언이 아니라 실측에서 파생한다.
#   ★그리고 판정 축이 없었다: Σ 추정기 교체의 옳은 대조는 비중 규칙을 고정한
#     `minvar@<est>` vs `minvar_lw` 인데, 그 대조가 데이터에 있는데도 계산되지 않아
#     optimizer 의 "최고 비중법" 경쟁에 흡수돼 조용히 졌다. 이제 레인 자체 대조를 낸다.
#   ★Δ 는 대조 진단량이지 자본 게이트가 아니다(§4 book-marginal admit = governor 수동).
if (n_risk > 0) {
  .rt <- if (exists("method_triage")) method_triage("risk") else list()
  # >>> RISK_LANE_VERDICT  (08_Tests/ops/test_risk_lane_verdict.R 가 이 블록을 원본에서 추출해
  #     검사한다 — 사본 검사 금지. 마커를 바꾸면 검사기부터 고칠 것.)
  #   입력 계약: battery_fresh(logical) · ov_csv(path) · risk_lane_arms() · fread()
  #   출력 계약: risk_verdict(list|NULL) · risk_state(character)
  .arms <- if (exists("risk_lane_arms")) tryCatch(risk_lane_arms(), error = function(e) list()) else list()
  risk_verdict <- NULL
  risk_state <- NULL
  if (!isTRUE(battery_fresh) || !file.exists(ov_csv)) {
    risk_state <- "배터리 결과 부재/미실행 — risk arm 측정 없음"
  } else if (!length(.arms)) {
    risk_state <- "레지스트리에 verdict=implemented 인 risk method 0건 — 측정할 arm 없음"
  } else {
    .tb <- tryCatch(fread(ov_csv), error = function(e) NULL)
    if (is.null(.tb) || !all(c("method", "IR") %in% names(.tb))) {
      risk_state <- "overlay CSV 판독 실패 또는 컬럼 결손 — 대조 불가"
    } else {
      .ir <- setNames(as.numeric(.tb$IR), as.character(.tb$method))
      .pt <- if ("PORT_t" %in% names(.tb)) setNames(as.numeric(.tb$PORT_t), as.character(.tb$method)) else setNames(numeric(0), character(0))
      .rows <- lapply(.arms, function(a) {
        got <- a$arm %in% names(.ir); ctl <- a$control %in% names(.ir)
        list(method_id = a$method_id, paper_id = a$paper_id, adapter_kind = a$adapter_kind,
             arm = a$arm, measured = got,
             ir      = if (got) round(unname(.ir[[a$arm]]), 3) else NA_real_,
             port_t  = if (got && a$arm %in% names(.pt)) round(unname(.pt[[a$arm]]), 3) else NA_real_,
             control = a$control, control_basis = a$control_basis,
             control_ir = if (ctl) round(unname(.ir[[a$control]]), 3) else NA_real_,
             delta_ir   = if (got && ctl) round(unname(.ir[[a$arm]] - .ir[[a$control]]), 3) else NA_real_,
             # ★arm 이 등재됐는데 CSV 에 없으면 그것이 **결함**이다 — 조용히 넘기지 않는다.
             note = if (!got) "★등재 implemented 인데 배터리 산출에 arm 부재 — 어댑터 로드 실패 의심"
                    else if (!ctl) sprintf("★대조군 %s 이 배터리 산출에 없음 — Δ 산출 불가", a$control)
                    else NA_character_)
      })
      .nm <- sum(vapply(.rows, function(r) isTRUE(r$measured), logical(1)))
      .win <- Filter(function(r) isTRUE(r$measured) && !is.na(r$delta_ir) && r$delta_ir > 0, .rows)
      risk_verdict <- list(
        metric_type = "canonical_screen",
        basis = "Σ-A/B 배터리 overlay arm (캐리어 선별 고정 · 15bps · IR = net-active vs KOSPI200)",
        n_arms = length(.rows), n_measured = .nm, n_improved = length(.win),
        gate_note = "ΔIR 은 추정기/비중 **교체 대조** 진단량이다 — 자본 admission 게이트(§4 book-marginal, governor 수동)가 아니다.",
        arms = .rows)
      risk_state <- if (.nm == 0) sprintf("arm %d건 등재됐으나 배터리 산출에 0건 — 배선 확인 필요", length(.rows))
                    else sprintf("Σ-A/B 배터리 합류 %d/%d건 측정 · 대조군 대비 개선 %d건", .nm, length(.rows), length(.win))
    }
  }
  # <<< RISK_LANE_VERDICT
  actions$risk <- list(n = n_risk, papers = lapply(getrt("risk"), function(p) p$title %||% p$arxiv_id),
                       method_triage = .rt,
                       screen_axes = check_screen_axes(getrt("risk"), "risk"),
                       harness_status = risk_state,          # ★실측 파생 — 하드코딩 문자열 폐기
                       verdict = risk_verdict,
                       action = if (!is.null(risk_verdict) && risk_verdict$n_measured > 0)
                                  sprintf("자동 측정 %d건 (대조 Δ 동봉) — 채택은 도훈 수동", risk_verdict$n_measured)
                                else if (length(.rt)) sprintf("레지스트리 등재 %d건 — 측정 0건 (사유: %s)", length(.rt), risk_state)
                                else "레지스트리 미등재 — triage 필요")
  cat(sprintf("[dispatch:risk] %d편 · %s\n", n_risk,
              if (exists("method_triage_line")) method_triage_line("risk") else "triage 불가"))
  cat(sprintf("[dispatch:risk] 레인 판정: %s\n", risk_state))
  if (!is.null(risk_verdict)) for (r in risk_verdict$arms) {
    cat(sprintf("    %-32s IR %s vs %s %s → ΔIR %s%s\n", r$arm,
                if (is.na(r$ir)) "  n/a" else sprintf("%6.3f", r$ir), r$control,
                if (is.na(r$control_ir)) "  n/a" else sprintf("%6.3f", r$control_ir),
                if (is.na(r$delta_ir)) "n/a" else sprintf("%+.3f", r$delta_ir),
                if (is.na(r$note)) "" else paste0("  ", r$note)))
  }
}
# ── regime: H2 오버레이 A/B 자동 실행 + 판정 (2026-08-09 배선, 도훈 "진행해") ──
#   구판은 문자열 flag 한 줄("자동 불가, 수동")뿐이었다 — 누적 38편 라우팅 · 측정 0.
#   ★하네스는 **이미 있었다**(auto_regime_overlay_ab.R, 2026-06-18). 없던 건 배선이다.
#     단 그대로 부르면 퇴역 기준선 위에서 재게 되어 있었다(캐리어 하드코딩 + layer5 노출) —
#     08-09 에 basis 2건을 수리한 뒤 배선한다. 수리 효과 실측(같은 269개월):
#       book_L5 IR 1.077→1.410 · uni_cat_x_book 0.965→1.201 · voltgt_x_book 0.680→0.891
#       (book 오버레이를 안 쓰는 bare/uni_cat/voltgt 는 **차이 0** = 양성 대조)
#   ★후보 집합은 아직 **고정**이다(unified 앙상블 + vol-target). 라우팅된 regime 논문이
#     자동으로 후보가 되지는 않는다 — 그러려면 method_registry 에 adapter_kind="exposure" 등재가
#     필요하고 현재 0건이다. 그 사실을 숨기지 않고 산출물에 수로 싣는다.
if (n_reg > 0) {
  rg_csv <- file.path("06_Registry/book_carrier", "h2_regime_overlay_ab.csv")
  # ★캐리어 경로는 optimizer 블록의 지역변수에 기대지 않는다 — regime 만 있는 날에도 돌아야 한다.
  .rg_carrier <- tryCatch({
    mt <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
    p <- as.character(mt$parquet %||% NA); if (!is.na(p)) p else character(0)
  }, error = function(e) character(0))
  .rg_inputs <- c(
    .rg_carrier,
    ".cache/rawdata.parquet", ".cache/benchmark.parquet", ".cache/unified_regime_signal.parquet",
    "02_Infrastructure/ops/auto_regime_overlay_ab.R", "02_Infrastructure/ops/auto_weighting_ab.R",
    "02_Infrastructure/contracts/weighted_screen_bt.R",
    "02_Infrastructure/validation/overlay_pit_guard.R",
    "06_Registry/method_registry.json",
    list.files("02_Infrastructure/methods/adapters", pattern = "\\.R$", full.names = TRUE))
  .rgf <- stale_check(rg_csv, .rg_inputs, label = "regime")
  reg_cov <- coverage_check(if (length(.rg_carrier)) .rg_carrier else NA_character_, "regime")
  reg_fresh <- .rgf$fresh; reg_out <- NULL; n_reg_adapters <- 0L
  if (!reg_fresh) {
    cat(sprintf("[dispatch:regime] H2 배터리 stale 판정: %s → 재실행\n", .rgf$why))
    Sys.setenv(QVEST_REGIME_AB_NORUN = "1")
    .rok <- tryCatch({ suppressWarnings(source("02_Infrastructure/ops/auto_regime_overlay_ab.R")); TRUE },
                     error = function(e) { cat(sprintf("[dispatch:regime] source fail: %s\n", conditionMessage(e))); FALSE })
    if (.rok && exists("run_regime_overlay_ab")) {
      .rex <- tryCatch(load_exposure_adapters(), error = function(e) {
        cat(sprintf("[dispatch:regime] exposure adapter load fail: %s\n", conditionMessage(e))); list() })
      n_reg_adapters <- length(.rex)
      reg_out <- tryCatch(run_regime_overlay_ab(extra_exposures = .rex),
                          error = function(e) { cat(sprintf("[dispatch:regime] battery fail: %s\n", conditionMessage(e))); NULL })
      if (!is.null(reg_out)) {
        fwrite(reg_out$tab, rg_csv)
        fwrite(reg_out$crisis, "06_Registry/book_carrier/h2_regime_crisis_eval.csv")
        reg_fresh <- TRUE
      }
    }
  } else cat("[dispatch:regime] H2 배터리 결과 재사용\n")

  reg_verdict <- NULL; reg_state <- sprintf("H2 배터리 미실행 — %s", .rgf$why)
  if (reg_fresh && file.exists(rg_csv)) {
    rt <- tryCatch(fread(rg_csv), error = function(e) NULL)
    if (is.null(rt) || !all(c("scenario", "IR") %in% names(rt))) {
      reg_state <- "H2 산출 판독 실패 또는 컬럼 결손"
    } else {
      .base <- rt[scenario == "book_L5"]
      .bare <- rt[scenario == "bare"]
      if (!nrow(.base)) reg_state <- "기준선 book_L5 팔 부재 — 판정 불가" else {
        cand <- rt[!scenario %in% c("book_L5", "bare", "uni_cat_lag1")][order(-IR)]
        cand[, `:=`(delta_ir = round(IR - .base$IR, 3), delta_mdd = round(abs_MDD - .base$abs_MDD, 4))]
        .best <- cand[1]
        .lag1 <- rt[scenario == "uni_cat_lag1"]; .uni <- rt[scenario == "uni_cat"]
        # ★lag1 스트레스 = 오버레이 동월 누출의 **유일 판별검정**(2026-07-06 BearProb 실사고).
        #   base 대비 붕괴하면 누출 의심. 비율로 기록해 다음 사람이 판단할 수 있게 한다.
        .lag_ratio <- if (nrow(.lag1) && nrow(.uni) && .uni$IR != 0) round(.lag1$IR / .uni$IR, 3) else NA_real_
        reg_verdict <- list(
          metric_type = "canonical_screen",
          basis = sprintf("H2 오버레이 A/B (가중 = 현 book strategy 고정 · 노출 스칼라만 교체 · %s · carrier=%s)",
                          rt$book_basis[1] %||% "?", rt$carrier[1] %||% "?"),
          baseline = "book_L5", baseline_ir = round(.base$IR, 3), baseline_mdd = round(.base$abs_MDD, 4),
          bare_ir = if (nrow(.bare)) round(.bare$IR, 3) else NA_real_,
          bare_mdd = if (nrow(.bare)) round(.bare$abs_MDD, 4) else NA_real_,
          best_candidate = .best$scenario, best_ir = round(.best$IR, 3),
          delta_ir = .best$delta_ir, delta_mdd = .best$delta_mdd,
          gate = DELTA_IR_GATE, beats_book = isTRUE(.best$delta_ir >= DELTA_IR_GATE),
          lag1_stress = list(uni_cat_ir = if (nrow(.uni)) round(.uni$IR, 3) else NA_real_,
                             uni_cat_lag1_ir = if (nrow(.lag1)) round(.lag1$IR, 3) else NA_real_,
                             retention = .lag_ratio,
                             note = "lag1 보존율 — 붕괴 시 동월 누출 의심(오버레이 유일 판별검정, pit.md C5)"),
          candidates = lapply(seq_len(nrow(cand)), function(i) as.list(cand[i, .(scenario, IR, abs_SR, abs_MDD, avg_exposure, delta_ir, delta_mdd)])),
          paper_adapters_registered = n_reg_adapters,
          scope_note = paste("후보 집합은 고정(unified 앙상블 · vol-target).",
                             "라우팅된 regime 논문이 후보가 되려면 method_registry 에 adapter_kind=\"exposure\" 등재 필요 —",
                             sprintf("현재 등재 %d건.", n_reg_adapters)),
          gate_note = "ΔIR 은 book-marginal 대조 진단량 — 자본 admit 아님(governor 수동). ★오버레이의 실증된 레버는 IR 이 아니라 MDD 이므로 ΔMDD 를 함께 읽을 것.",
          # ★부호 규약을 산출물에 박는다. abs_MDD 는 **음수 저장**이라 Δ 의 부호가 직관과 반대다 —
          #   ΔMDD −0.057 을 "5.7%p 개선"으로 읽는 오독이 이 저장소가 반복해 온 형태다
          #   ([[project-capw-ew-gap-is-bench-side-constant-20260808]] = 같은 부류의 부호/basis 오독).
          delta_mdd_convention = "abs_MDD 음수 저장 — ΔMDD>0 이면 낙폭이 얕아진 것(개선), ΔMDD<0 이면 깊어진 것(악화)",
          mdd_improved_candidates = cand[delta_mdd > 0, scenario])
        .mdd_word <- function(d) if (is.na(d)) "" else if (d > 0) " (낙폭 완화)" else if (d < 0) " (낙폭 심화)" else " (낙폭 동일)"
        reg_state <- if (reg_verdict$beats_book)
          sprintf("후보 %s ΔIR=%+.3f (게이트 %.2f 이상) → 수동 검수", .best$scenario, .best$delta_ir, DELTA_IR_GATE)
        else sprintf("오버레이 레버 아님: book_L5 IR %.3f 최고(최선 후보 %s %.3f, ΔIR=%+.3f, ΔMDD=%+.4f%s) → 채택 0",
                     .base$IR, .best$scenario, .best$IR, .best$delta_ir, .best$delta_mdd, .mdd_word(.best$delta_mdd))
      }
    }
  }
  actions$regime <- list(n = n_reg, papers = lapply(getrt("regime"), function(p) p$title %||% p$arxiv_id),
                         harness_status = reg_state,
                         coverage = reg_cov,
                         verdict = reg_verdict,
                         action = if (!is.null(reg_verdict))
                                    sprintf("H2 오버레이 A/B 자동 측정 (후보 %d) — 채택은 도훈 수동", length(reg_verdict$candidates))
                                  else sprintf("측정 없음 — %s", reg_state))
  cat(sprintf("[dispatch:regime] %d편 · %s\n", n_reg, reg_state))
  if (!is.null(reg_verdict)) {
    cat(sprintf("    기준선 book_L5 IR %.3f (MDD %.4f) · bare IR %s (MDD %s)\n",
                reg_verdict$baseline_ir, reg_verdict$baseline_mdd,
                format(reg_verdict$bare_ir), format(reg_verdict$bare_mdd)))
    cat("    (ΔMDD 부호: abs_MDD 는 음수 저장 — + 이면 낙폭 완화, − 이면 낙폭 심화)\n")
    for (c1 in reg_verdict$candidates)
      cat(sprintf("    %-18s IR %6.3f  ΔIR %+.3f  ΔMDD %+.4f%-10s 평균노출 %.4f\n",
                  c1$scenario, c1$IR, c1$delta_ir, c1$delta_mdd,
                  if (c1$delta_mdd > 0) " 완화" else if (c1$delta_mdd < 0) " 심화" else " 동일",
                  c1$avg_exposure))
    cat(sprintf("    lag1 보존율 %s (uni_cat %s → lag1 %s)\n",
                format(reg_verdict$lag1_stress$retention),
                format(reg_verdict$lag1_stress$uni_cat_ir), format(reg_verdict$lag1_stress$uni_cat_lag1_ir)))
    cat(sprintf("    논문 유래 노출 어댑터 등재 %d건 — %s\n", n_reg_adapters,
                if (n_reg_adapters == 0) "regime 논문은 아직 후보로 자동 합류하지 않는다(등재 필요)" else "합류함"))
  }
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
    # ★(2026-08-09) 텔레그램도 실측에서 파생한다 — 구 하드코딩 "수동 분석"은 배터리가 실제로
    #   risk arm 을 잰 날에도 그대로 나가 durable 기록과 보고가 함께 과소보고됐다.
    if (n_risk > 0) {
      .rv <- actions$risk$verdict
      bullets <- c(bullets, if (!is.null(.rv) && .rv$n_measured > 0) {
        .best <- Filter(function(r) isTRUE(r$measured) && !is.na(r$delta_ir), .rv$arms)
        .bl <- if (length(.best)) {
          .b <- .best[[which.max(vapply(.best, function(r) r$delta_ir, numeric(1)))]]
          sprintf(" 최선 %s ΔIR=%+.3f (대조 %s)", .b$method_id, .b$delta_ir, .b$control)
        } else ""
        sprintf("risk(%d편) Σ-교체 A/B: %d건 측정 · 개선 %d건%s", n_risk, .rv$n_measured, .rv$n_improved, .bl)
      } else sprintf("risk %d편 → %s", n_risk, actions$risk$harness_status %||% "측정 없음"))
    }
    # ★(2026-08-09) regime 도 실측 파생. 구 문자열은 하네스가 배선된 뒤에도 "추출 필요"로 남았을 것.
    if (n_reg > 0) {
      .gv <- actions$regime$verdict
      bullets <- c(bullets, if (!is.null(.gv)) {
        sprintf("regime(%d편) H2 오버레이 A/B: %s (기준 book_L5 IR %.3f · 최선 %s ΔIR %+.3f ΔMDD %+.4f · 논문 어댑터 %d건)",
                n_reg, if (.gv$beats_book) "후보 있음" else "레버 아님",
                .gv$baseline_ir, .gv$best_candidate, .gv$delta_ir, .gv$delta_mdd, .gv$paper_adapters_registered)
      } else sprintf("regime %d편 → %s", n_reg, actions$regime$harness_status %||% "측정 없음"))
    }
    if (length(bullets) < 2) bullets <- c(bullets, "자본 admit 없음 — 측정·보고만(governor 정지)")

    # ══ 레인별 발송 (2026-08-13 도훈 보고: "리스크·옵티마이저 논문 리서치 결과가 온 적이 없다") ══
    #   원인 2중. ①**라벨** — 전 레인을 `AlphaSearch`(🔭) 하나로 보냈다. `Risk`(🛡️)·`Optimizer`(⚖️)
    #     라벨이 이미 있는데 안 썼다. 받는 쪽에선 전부 알파 메시지로 보인다.
    #   ②★**논문이 한 편도 안 나온다** — 본문에 제목이 없고, 수치는 큐가 아니라 레지스트리 arm 에서
    #     나오므로 **다른 논문 집합인데 숫자가 똑같다**(실측: 큐 1편인 08-13 과 5편인 07-05 의
    #     optimizer 줄이 ΔIR=-0.021 로 완전 동일). 그러면 "이 논문들을 리서치한 결과"로 읽힐 수 없다.
    #   ⇒ 레인별로 그 에이전트 이름으로 보내고, **큐 N편 → 어댑터 등재 M편 → 측정 arm K개**를
    #     명시한다. M=0 이면 "등재 0 — 이 논문들은 아직 측정되지 않았다"가 본문에 찍힌다.
    #     (등재 경로는 02_Infrastructure/methods/register_method.R)
    .titles <- function(rt, k = 5L) {
      x <- getrt(rt); if (!length(x)) return(character(0))
      tt <- vapply(x, function(e) as.character(e$title %||% e$paper %||% "?"), character(1))
      if (length(tt) > k) c(tt[seq_len(k)], sprintf("… 외 %d편", length(tt) - k)) else tt
    }
    .lane_send <- function(lane, agent_name, n_q, n_arm, result_line) {
      if (n_q <= 0) return(invisible(NULL))
      st <- if (n_arm > 0)
              sprintf("큐 %d편 → 어댑터 등재 %d건 → 측정 arm %d개", n_q, n_arm, n_arm)
            else
              sprintf("큐 %d편 → **어댑터 등재 0건 → 이 논문들은 아직 측정되지 않았습니다**", n_q)
      secs2 <- list(
        list(type = "summary", heading = sprintf("%s 레인", lane), body = st),
        list(type = "bullet", heading = "이번 큐 논문", items = .titles(lane)),
        list(type = "bullet", heading = "측정 결과(등재된 arm 기준)", items = result_line),
        list(type = "kv", heading = "다음 단계",
             kv = list("등재 경로" = "02_Infrastructure/methods/register_method.R",
                       "후보 큐" = "06_Registry/adapter_registration_queue.json",
                       "주의" = "측정 arm 수는 큐 길이가 아니라 등재 수에 비례합니다"))
      )
      tryCatch(tg_agent_brief(agent = agent_name,
                              title = sprintf("논문 → %s 리서치", lane),
                              relaxed = TRUE, force = TRUE,
                              lock_scope = sprintf("paper_dispatch_%s_%s", lane, today),
                              sections = secs2),
               error = function(e) cat(sprintf("[dispatch] tg fail(%s): %s\n", lane, conditionMessage(e))))
    }
    .n_arm_opt  <- tryCatch(length(opt_verdict$arms %||% list()), error = function(e) 0L)
    .n_arm_risk <- tryCatch(as.integer(actions$risk$verdict$n_measured %||% 0L), error = function(e) 0L)
    .n_arm_reg  <- tryCatch(as.integer(actions$regime$verdict$paper_adapters_registered %||% 0L), error = function(e) 0L)
    .lane_send("optimizer", "Optimizer", n_opt, .n_arm_opt,
               bullets[grepl("^optimizer", bullets)] %||% "측정 결과 없음")
    .lane_send("risk", "Risk", n_risk, .n_arm_risk,
               bullets[grepl("^risk", bullets)] %||% "측정 결과 없음")
    .lane_send("regime", "Q-Lead", n_reg, .n_arm_reg,
               bullets[grepl("^regime", bullets)] %||% "측정 결과 없음")
    # ★(2026-08-13) 큐 날짜를 헤드라인에 명시한다. 백로그 소급 구동(paper_dispatch_backfill.sh)이
    #   2개월 전 큐를 처리해도 구 문구는 오늘 결과처럼 읽혔다 — 보고가 시점을 숨기면 안 된다.
    .qlbl <- if (identical(today, format(Sys.Date(), "%Y%m%d"))) today else sprintf("%s · 백로그 소급", today)
    headline <- sprintf("논문 라우트 디스패치 [큐 %s]: optimizer %d·risk %d·regime %d", .qlbl, n_opt, n_risk, n_reg)
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
