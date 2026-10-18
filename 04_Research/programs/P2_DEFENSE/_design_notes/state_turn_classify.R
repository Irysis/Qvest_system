## 빠른 급락의 '직전 상태' 분류(벤치만 · 전략 성과 무관) — P2R04 설계 입력 · 판단 Superfan T2 C-20261018-001 반증 검사
##   질문: 빠른 급락은 대개 월간 가격 상태(12개월 수익 · 낙폭 국면)가 이미 꺾인 뒤에 오는가, 꼭대기에서 바로 오는가.
##   대상 = P2R03 사전등록 fast_crash_prior 표(2000-01 ~ 2022-12 · LT 20/20 · 21거래일 창 ≤ −20% · 구간 직전 월말 pre_me).
##   상태 정의 = P2R03 장치와 같은 식: r252 = 252거래일 수익(D5 추세 현금 게이트 = r252 < 0) · dd = 1 − nav/cummax(nav) ·
##   낙폭 국면 = dd 가 2000-01 이후 월말 dd 의 확장창 중앙값 위(D7 · D6 의 국면 조건). 전환 = r252 < 0 ∨ 낙폭 국면.
##   반증 조건(T2 사전 진술): 판정 창 앞 빠른 급락 4건 중 3건 이상이 이미 전환 상태면 '빠른 급락은 대개 상태 전환 뒤' — 표적 정의를 다시 쓴다.
##   실행: Rscript state_turn_classify.R → 같은 폴더 state_turn_classify.md
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/_design_notes")
pre  <- fromJSON(file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay/prereg.json"), simplifyVector = FALSE)
TAU  <- as.Date(pre$tau_d)
B <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))[is.finite(BM_Ret), .(Date = as.Date(Date), r = BM_Ret)]
setorder(B, Date)
B <- B[Date <= TAU]                                                     # 보는 창까지만(설계 입력 · τ_D)
B[, nav := cumprod(1 + r)][, dd := 1 - nav / cummax(nav)][, r252 := nav / shift(nav, 252L) - 1]
B[, ym := format(Date, "%Y-%m")]
ME <- B[, .SD[.N], by = ym][Date >= as.Date("2000-01-01")]
ME[, dd_med := vapply(seq_len(.N), function(i) stats::median(dd[seq_len(i)]), numeric(1))]   # 확장창(그 월말까지)
T0 <- rbindlist(lapply(pre$fast_crash_prior$table, function(z) data.table(crisis = z$crisis, fast = isTRUE(z$fast), seg = z$seg %||% NA_character_,
                                                                         pre_me = as.Date(z$pre_me %||% NA), depth = as.numeric(z$depth %||% NA))), fill = TRUE)
T0 <- T0[!is.na(pre_me)]                                               # 빠른 · 느린 위기 모두(최대 21거래일 하락 구간 직전 월말)
S <- ME[, .(pre_me = Date, r252, dd, dd_med)]
T1 <- merge(T0, S, by = "pre_me", all.x = TRUE)
T1[, `:=`(trend_off = r252 < 0, dd_regime = dd > dd_med)][, turned := trend_off | dd_regime]
T1[, window := ifelse(pre_me < as.Date("2005-02-01"), "판정 창 앞(엔진 실효 시작 전)", "판정 창")]
setorder(T1, pre_me)
md <- function(D) c(paste0("| ", paste(names(D), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(D))),
                    apply(D, 1, function(r) paste0("| ", paste(trimws(r), collapse = " | "), " |")))
show <- T1[, .(crisis, fast, seg, pre_me = format(pre_me), r252 = sprintf("%+.3f", r252), dd = sprintf("%.3f", dd), dd_med = sprintf("%.3f", dd_med),
               trend_off, dd_regime, turned, window)]
n_pre <- T1[window != "판정 창" & fast %in% TRUE, .N]; k_pre <- T1[window != "판정 창" & fast %in% TRUE, sum(turned)]   # T2 반증 조건 = 빠른 급락만
n_vis <- T1[window == "판정 창" & fast %in% TRUE, .N]; k_vis <- T1[window == "판정 창" & fast %in% TRUE, sum(turned)]
top_vis <- T1[window == "판정 창" & turned %in% FALSE, crisis]                                   # 최대 하락 구간이 상태 전환 전(꼭대기 시작 손실)
verdict <- if (k_pre >= 3L) "반증 조건 충족 — 빠른 급락은 대개 상태 전환 뒤에 온다(표적 정의 재작성)" else
           "반증 조건 미충족 — 판정 창 앞에서도 빠른 급락 다수가 상태 전환 전(꼭대기)에서 시작 · '상태 미전환 위기' 표적 유지"
txt <- c("# 빠른 급락의 직전 상태 분류(벤치만 · 2000-01 ~ 2022-12 · 2026-10-18)", "",
  "- 상태 = 구간 직전 월말(그 달 노출을 정한 신호일)의 12개월 수익 r252 · 낙폭 dd · 낙폭 확장창 중앙값(2000-01 이후 월말). 전환 = r252 < 0(추세 꺼짐) ∨ dd > 중앙값(낙폭 국면).",
  "- 반증 조건(판단 Superfan T2 C-20261018-001 사전 진술): 판정 창 앞 빠른 급락 4건 중 3건 이상이 이미 전환이면 표적 정의를 다시 쓴다.", "",
  md(show), "",
  sprintf("- 빠른 급락(T2 반증 조건 대상): 판정 창 앞 전환 %d/%d · 판정 창 전환 %d/%d", k_pre, n_pre, k_vis, n_vis),
  sprintf("- 판정 창에서 최대 하락 구간이 상태 전환 전에 온 위기(빠른 · 느린 모두): %s", paste(top_vis, collapse = " · ")),
  sprintf("- **%s**", verdict),
  "- 주의: 판정 창 앞 빠른 급락은 2000~2004(닷컴 · 카드채)라 표본이 한 시대에 몰려 있다 — 분류는 표적 정의의 근거이지 장치 성과의 근거가 아니다.")
writeLines(txt, file.path(OUT, "state_turn_classify.md"), useBytes = TRUE)
print(show); cat(sprintf("\npre-window turned %d/%d · visible turned %d/%d\n%s\n", k_pre, n_pre, k_vis, n_vis, verdict))
