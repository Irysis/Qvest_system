## FQ-181 P6 — 자기 적대검증 실측 (주장 대신 측정)
##
## 내가 P4 에서 "2018+ 창이면 parity 판정에 **충분**" 이라고 썼다. 근거 없는 '충분'은
## 회피 표현이다(answer-principles). 불일치가 가장 큰 초기 구간(~2004, 12.9%)에서 다시 잰다.
## 함께: 워밍업 확장평균(adaptive)이 판정에 얼마나 기여하는지 — 내 **설계 선택**이지
## 헌법 정의가 아니므로 크기를 밝힌다.
##
## 산출: p6_selfadv.json

suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
QM <- gsub("\\\\","/",Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(QM)
OUT <- file.path(QM, "stage_artifacts/FQ181_liquidity_ruler")
LIQ_MIN <- 2e8
source(file.path(QM, "02_Infrastructure/ramp/factor_validation.R"))
legacy_env <- new.env()
suppressMessages(sys.source(file.path(OUT, "_legacy_factor_validation.R"), envir = legacy_env))
old_fn <- get("build_monthly_forward_returns", envir = legacy_env)

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size")
R <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select = all_of(.need)))
R[, Date := as.Date(Date)]

## ── (1) 초기 구간 parity (불일치 최대 구간) ─────────────────────────────────
cat("=== (1) 초기 구간 parity — 불일치 최대 구간에서 재검 ===\n")
RE <- R[Date >= as.Date("1999-01-01") & Date <= as.Date("2005-12-31")]
D <- sort(unique(RE$Date))
ME <- sort(unname(as.Date(vapply(split(D, format(D,"%Y-%m")), function(v) as.character(max(v)), character(1)))))
cat(sprintf("[1] 창 %s..%s · 행 %s · 월말 %d\n", min(ME), max(ME), format(nrow(RE), big.mark=","), length(ME)))
fo <- old_fn(RE, ME); fn <- suppressWarnings(build_monthly_forward_returns(RE, ME))
p_ret <- isTRUE(all.equal(fo$returns_dt, fn$returns_dt))
p_bm  <- isTRUE(all.equal(fo$bench_dt, fn$bench_dt))
cat(sprintf("[1] returns_dt 동일 = %s · bench_dt 동일 = %s · liq_ruler = %s\n", p_ret, p_bm, fn$liq_ruler))
L <- merge(fo$liq_dt[, .(Date,Ticker,a_old=adv)], fn$liq_dt[, .(Date,Ticker,a_new=adv)], by=c("Date","Ticker"))
L <- L[!is.na(a_old) & !is.na(a_new)]
cat(sprintf("[1] liq 불일치 %.3f%% (구판만통과 %.3f%% / 교정만통과 %.3f%%) — 초기 구간이라 크다\n",
            100*L[, mean((a_old>=LIQ_MIN)!=(a_new>=LIQ_MIN))],
            100*L[, mean((a_old>=LIQ_MIN)&(a_new<LIQ_MIN))],
            100*L[, mean((a_old<LIQ_MIN)&(a_new>=LIQ_MIN))]))

## ── (2) 워밍업 확장평균의 기여 — 내 설계 선택의 크기 ────────────────────────
cat("\n=== (2) 워밍업 확장평균(adaptive) 기여 — 헌법 정의가 아닌 내 설계 선택 ===\n")
R2 <- R[, .(Date, Ticker, dval = Vol*Close)]
setorder(R2, Ticker, Date)
R2[, strict := shift(frollmean(dval, n=20L, align="right"), 1L), by = Ticker]   # 워밍업 = NA
R2[, adapt  := shift(frollmean(dval, n=pmin(seq_len(.N),20L), adaptive=TRUE, na.rm=TRUE), 1L), by = Ticker]
DD <- sort(unique(R$Date))
MEA <- sort(unname(as.Date(vapply(split(DD, format(DD,"%Y-%m")), function(v) as.character(max(v)), character(1)))))
U <- merge(R2[Date %in% MEA], R[Date %in% MEA, .(Date,Ticker,K200,KQ150)], by=c("Date","Ticker"))
U <- U[(K200==TRUE|KQ150==TRUE)]
n_warm <- U[is.na(strict) & !is.na(adapt), .N]
cat(sprintf("[2] 유니버스 종-월 %s 중 워밍업(strict=NA, adaptive 로 채운) = %s (%.3f%%)\n",
            format(nrow(U), big.mark=","), format(n_warm, big.mark=","), 100*n_warm/nrow(U)))
if (n_warm > 0) {
  W <- U[is.na(strict) & !is.na(adapt)]
  cat(sprintf("[2] 그 중 확장평균으로 **통과** = %d · **탈락** = %d\n",
              W[adapt>=LIQ_MIN, .N], W[adapt<LIQ_MIN, .N]))
  cat(sprintf("[2] ★대안(NA 유지)이었다면 이 %s 건이 canonical_screen_bt 의 `is.na(adv)|adv>=min` 로 **전건 통과**했다\n",
              format(nrow(W), big.mark=",")))
  cat(sprintf("[2] ⇒ adaptive 선택의 순효과 = %d 건 추가 탈락 (조임). 완화 아님.\n", W[adapt<LIQ_MIN, .N]))
} else cat("[2] 워밍업 케이스 0 — 이 설계 선택은 유니버스 판정에 무영향\n")
n_still_na <- U[is.na(adapt), .N]
cat(sprintf("[2] 교정 후에도 adv=NA (종목 첫 관측) = %d 건 → 이들은 여전히 필터 통과(잔여 구멍, 자백)\n", n_still_na))

## ── (3) 자 A/B 판정 방향의 대칭성 재확인 (조임/완화 양쪽 실재 확인) ──────────
cat("\n=== (3) 방향 대칭성 ===\n")
cat("[3] P2 실측: 구판만통과 1,388(교정이 조임) vs 교정만통과 4,959(교정이 품) → **net looser**\n")
cat("[3] ★이것은 지시문 기대(조이는 방향만)와 반대다. 문턱(2e8) 은 불변이고 자만 헌법 정의로\n")
cat("    바꿨으므로 '제약 완화'는 아니지만, 통과 종목 수가 느는 것은 사실이다 → 도훈 판단 대상으로 상신.\n")

res <- list(
  early_window_parity = list(window = paste0(min(ME),"..",max(ME)),
    returns_identical = p_ret, bench_identical = p_bm, liq_ruler = fn$liq_ruler,
    liq_disagree_pct = 100*L[, mean((a_old>=LIQ_MIN)!=(a_new>=LIQ_MIN))],
    legacy_only_pct = 100*L[, mean((a_old>=LIQ_MIN)&(a_new<LIQ_MIN))],
    new_only_pct = 100*L[, mean((a_old<LIQ_MIN)&(a_new>=LIQ_MIN))]),
  warmup_design_choice = list(
    n_universe = nrow(U), n_warmup_filled = n_warm,
    pct = 100*n_warm/nrow(U),
    n_warmup_excluded_by_adaptive = if (n_warm>0) U[is.na(strict)&!is.na(adapt)&adapt<LIQ_MIN,.N] else 0L,
    n_still_na_after_fix = n_still_na,
    note = "adaptive 는 헌법 '20일 평균' 의 문자적 정의가 아니라 워밍업 처리 설계 선택. 대안(NA)은 필터를 통과시켜 더 느슨하다."),
  direction = "net_looser_vs_mandate_expectation — 도훈 판단 상신"
)
write_json(res, file.path(OUT, "p6_selfadv.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("\n[done] p6_selfadv.json\n")
