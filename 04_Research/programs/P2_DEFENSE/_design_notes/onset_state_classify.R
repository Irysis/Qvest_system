## LT 위기의 '시작 직전 상태' 분류(벤치만 · 전략 성과 무관) — P2R04 표적 위기 목록(사전등록 고정용)
##   표적 = '꼭대기에서 시작하는 위기'(상태 미전환): 위기 시작(고점일) 직전 월말에 12개월 수익 r252 ≥ 0 ∧ 낙폭 dd ≤ 확장창 중앙값.
##   P2R03 의 시장 수준 타이밍 층(D5 추세 현금 r252 < 0 · D6 · D7 낙폭 국면)이 위기 초입에 켜질 수 없던 위기다(판단 T2 C-20261018-001 ·
##   철학 P2 C-20261018-008). 상태 식 = state_turn_classify.R 과 같음(r252 = 252거래일 수익 · dd = 1 − nav/cummax · 중앙값 = 2000-01 이후 월말 확장창).
##   위기 목록 = P2R03 사전등록 fast_crash_prior 표(LT 20/20 · 2000-01 ~ 2022-12 · 깊은 위기 = 보는 창 판정 위기 중 bm_dd ≥ 중앙값 — 판정은 평가 계약).
##   실행: Rscript onset_state_classify.R → 같은 폴더 onset_state_classify.md · onset_state_classify.json(사전등록이 읽는다)
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/_design_notes")
pre  <- fromJSON(file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay/prereg.json"), simplifyVector = FALSE)
TAU  <- as.Date(pre$tau_d)
B <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))[is.finite(BM_Ret), .(Date = as.Date(Date), r = BM_Ret)]
setorder(B, Date); B <- B[Date <= TAU]
B[, nav := cumprod(1 + r)][, dd := 1 - nav / cummax(nav)][, r252 := nav / shift(nav, 252L) - 1][, ym := format(Date, "%Y-%m")]
ME <- B[, .SD[.N], by = ym][Date >= as.Date("2000-01-01")]
ME[, dd_med := vapply(seq_len(.N), function(i) stats::median(dd[seq_len(i)]), numeric(1))]
T0 <- rbindlist(lapply(pre$fast_crash_prior$table, function(z) {
  k <- strsplit(z$crisis, " → ", fixed = TRUE)[[1]]
  data.table(crisis = z$crisis, peak = as.Date(k[1]), trough = as.Date(k[2]), depth = as.numeric(z$depth %||% NA), fast = isTRUE(z$fast))
}), fill = TRUE)
T0[, onset_me := vapply(peak, function(p) { d <- ME[Date < p, Date]; if (length(d)) as.numeric(max(d)) else NA_real_ }, numeric(1))]
T0[, onset_me := as.Date(onset_me, origin = "1970-01-01")]
T1 <- merge(T0, ME[, .(onset_me = Date, r252, dd, dd_med)], by = "onset_me", all.x = TRUE)
T1[, `:=`(trend_off = r252 < 0, dd_regime = dd > dd_med)][, turned := trend_off | dd_regime][, from_top := !turned]
T1[, window := ifelse(peak < as.Date("2005-02-01"), "판정 창 앞", "판정 창")]
setorder(T1, peak)
md <- function(D) c(paste0("| ", paste(names(D), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(D))),
                    apply(D, 1, function(r) paste0("| ", paste(trimws(r), collapse = " | "), " |")))
show <- T1[, .(crisis, depth = sprintf("%.3f", depth), fast, onset_me = format(onset_me), r252 = sprintf("%+.3f", r252),
               dd = sprintf("%.3f", dd), dd_med = sprintf("%.3f", dd_med), trend_off, dd_regime, from_top, window)]
tgt <- T1[window == "판정 창" & from_top == TRUE, crisis]
writeLines(c("# LT 위기 시작 직전 상태 — '꼭대기 시작'(상태 미전환) 표적(벤치만 · 2000-01 ~ 2022-12 · 2026-10-18)", "",
             "- 시작 직전 월말(고점일 앞 마지막 월말)의 r252 · dd · dd 확장창 중앙값. 꼭대기 시작 = r252 ≥ 0 ∧ dd ≤ 중앙값(시장 수준 추세 · 낙폭 게이트가 초입에 켜질 수 없음).",
             "- 깊은 위기 판정(bm_dd ≥ 보는 창 중앙값)은 평가 계약이 정한다 — 이 표는 시작 상태만 분류한다.", "",
             md(show), "",
             sprintf("- 판정 창 꼭대기 시작 위기: %s", paste(tgt, collapse = " · "))),
           file.path(OUT, "onset_state_classify.md"), useBytes = TRUE)
writeLines(toJSON(list(source = "onset_state_classify.R(벤치만 · τ_D 까지)", rule = "r252 >= 0 & dd <= expanding median(2000-01~ month-ends) at last month-end before peak",
                       visible_from_top = as.list(tgt), table = show), auto_unbox = TRUE, pretty = TRUE),
           file.path(OUT, "onset_state_classify.json"), useBytes = TRUE)
print(show); cat("\nvisible from-top:", paste(tgt, collapse = " | "), "\n")
