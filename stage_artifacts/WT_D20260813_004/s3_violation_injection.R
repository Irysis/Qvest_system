# WT-D20260813_004 — s3: PIT 방향 검사의 '차단 실효' 실증 (위반 주입 테스트)
# 문제: s1 의 pit_direction_test 가 PASS 했다. 그러나 검사기가 진짜 위반을 잡는지 확인하지 않으면
#       그 PASS 는 '결함 없음' 이 아니라 '검사기가 죽어 있음' 과 구분되지 않는다.
#       (memory: feedback-verify-both-directions-always — 유일 방어 = 양성 대조 + 위반 주입)
# 방법: 동일 코드에 clean 판 / 오염 판(동월 정보 포함) 을 각각 먹여 판정이 갈리는지 본다.
# ★역할경계: Sigma 추정 없음 · weight 없음 · 성과 통계량 없음. 신호 타이밍 진단만.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_004")

BD <- unique(as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "BM_Ret"))), by = "Date")[order(Date)][is.finite(BM_Ret)]
BD <- BD[Date <= as.Date("2026-08-08")]
BD[, ym := format(Date, "%Y-%m")]
MO <- BD[, .(n_days = .N, last_day = max(Date)), by = ym][order(ym)]
MO[, hold_start := as.Date(paste0(ym, "-01"))]
LB <- 252L

sd_before <- function(cut) { r <- BD[Date < cut, BM_Ret]
  if (length(r) < LB) return(NA_real_); stats::sd(tail(r, LB)) }
sd_through <- function(last_d) { r <- BD[Date <= last_d, BM_Ret]     # ★오염: 홀딩월 말까지 포함
  if (length(r) < LB) return(NA_real_); stats::sd(tail(r, LB)) }

MO[, sigma_clean := vapply(hold_start, sd_before,  numeric(1))]
MO[, sigma_dirty := vapply(last_day,   sd_through, numeric(1))]
# 홀딩월 내 실현 vol (검정 대상 — 양 판에서 동일)
RV <- BD[, .(realized_vol = stats::sd(BM_Ret)), by = ym]
MO <- merge(MO, RV, by = "ym")[order(ym)]
S  <- MO[is.finite(sigma_clean) & is.finite(sigma_dirty) & is.finite(realized_vol)]

# 검사기 본체 — s1 과 동일 규칙: clean PIT 이면 cor(sig_{m+1}, rv_m) > cor(sig_m, rv_m)
direction_test <- function(sig, rv) {
  n <- length(sig)
  c_same <- cor(sig, rv, method = "spearman")
  c_next <- cor(sig[-1], rv[-n], method = "spearman")
  list(cor_same_month = c_same, cor_next_month = c_next,
       margin = c_next - c_same, passed = c_next > c_same)
}
r_clean <- direction_test(S$sigma_clean, S$realized_vol)
r_dirty <- direction_test(S$sigma_dirty, S$realized_vol)

res <- list(
  purpose = "PIT 방향 검사의 차단 실효 확인 — 검사기가 실제 위반에 발화하는가",
  n_months = nrow(S), window = c(S$ym[1], S$ym[nrow(S)]),
  arms = list(
    clean = c(list(arm = "sigma_hat: Date < 홀딩월 1일 (승계 패널과 동일 규약)"), r_clean),
    injected_violation = c(list(arm = "sigma_dirty: Date <= 홀딩월 말일 (동월 정보 포함 = C5 위반 주입)"), r_dirty)
  ),
  detector_verdict = list(
    clean_passed = r_clean$passed,
    violation_caught = !r_dirty$passed,
    both_directions_ok = isTRUE(r_clean$passed) && isTRUE(!r_dirty$passed),
    separation = r_clean$margin - r_dirty$margin
  ),
  reading = paste0(
    "clean 판이 PASS 하고 오염 판이 FAIL 해야 검사가 살아 있다. 둘 다 PASS 면 이 검사는 ",
    "판별력이 없는 것이며 s1 의 PASS 를 근거로 인용해서는 안 된다."),
  metric_type = "interface_verification_violation_injection",
  role_boundary = list(covariance_estimated = FALSE, weights_proposed = FALSE, performance_measured = FALSE)
)
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null"),
           file.path(OUT, "pit_violation_injection.json"))
cat(toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null"))
