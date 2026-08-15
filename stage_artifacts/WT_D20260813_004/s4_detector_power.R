# WT-D20260813_004 — s4: s3 에서 방향검사가 판별력 0 으로 드러난 뒤, 판별력 있는 통계량이 있는지 탐색.
# 원인 가설: 252d 창에 홀딩월 ~21일을 더해도 창의 8% 만 바뀌어 지속성이 순서를 지배한다.
#           따라서 '내부 순서 비교'는 오염에 둔감하다. 창 밖/안 대비를 직접 재는 통계량이 필요하다.
# ★역할경계: Sigma·weight·성과 없음.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_004")

BD <- unique(as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","BM_Ret"))), by="Date")[order(Date)][is.finite(BM_Ret)]
BD <- BD[Date <= as.Date("2026-08-08")]
BD[, ym := format(Date, "%Y-%m")]
MO <- BD[, .(last_day = max(Date)), by = ym][order(ym)]
MO[, hold_start := as.Date(paste0(ym, "-01"))]
LB <- 252L
MO[, sigma_clean := vapply(hold_start, function(cut){ r <- BD[Date < cut, BM_Ret]
  if (length(r) < LB) NA_real_ else stats::sd(tail(r, LB)) }, numeric(1))]
MO[, sigma_dirty := vapply(last_day, function(ld){ r <- BD[Date <= ld, BM_Ret]
  if (length(r) < LB) NA_real_ else stats::sd(tail(r, LB)) }, numeric(1))]
RV <- BD[, .(rv = stats::sd(BM_Ret)), by = ym]
S <- merge(MO, RV, by="ym")[order(ym)][is.finite(sigma_clean) & is.finite(sigma_dirty) & is.finite(rv)]
S[, rv_prev := shift(rv, 1L, type = "lag")]
S2 <- S[is.finite(rv_prev)]

# 통계량 A (s3 판) — 내부 순서: cor(sig_{m+1}, rv_m) > cor(sig_m, rv_m)
statA <- function(sig, rv) { n <- length(sig)
  cor(sig[-1], rv[-n], method="spearman") - cor(sig, rv, method="spearman") }
# 통계량 B — 창-밖/창-안 대비: cor(sig_m, rv_{m-1}) - cor(sig_m, rv_m)
#   clean 이면 rv_{m-1} 은 창 안, rv_m 은 창 완전 밖 -> 큰 양수. 오염이면 rv_m 이 창에 들어와 축소.
statB <- function(sig, rv, rvp) cor(sig, rvp, method="spearman") - cor(sig, rv, method="spearman")
# 통계량 C — 마지막 거래일 민감도: sig_m 이 홀딩월 첫 거래일 수익에 반응하는가(있으면 안 됨)
firstday <- BD[, .(r1 = BM_Ret[1]), by = ym]
S3 <- merge(S, firstday, by="ym")

A_clean <- statA(S$sigma_clean, S$rv);            A_dirty <- statA(S$sigma_dirty, S$rv)
B_clean <- statB(S2$sigma_clean, S2$rv, S2$rv_prev); B_dirty <- statB(S2$sigma_dirty, S2$rv, S2$rv_prev)
C_clean <- cor(S3$sigma_clean, abs(S3$r1), method="spearman")
C_dirty <- cor(S3$sigma_dirty, abs(S3$r1), method="spearman")

mk <- function(nm, cl, dy, rule) list(statistic = nm, clean = cl, injected = dy,
  separation = cl - dy, discriminates = rule(cl, dy))
res <- list(
  purpose = "s3 에서 방향검사(통계량 A)가 위반 주입에 발화하지 않았다. 판별력 있는 대안 통계량 탐색.",
  n = nrow(S), n_B = nrow(S2), window = c(S$ym[1], S$ym[nrow(S)]),
  statistics = list(
    mk("A: cor(sig_{m+1},rv_m) - cor(sig_m,rv_m)  [s3 판]", A_clean, A_dirty,
       function(c_, d_) c_ > 0 && d_ <= 0),
    mk("B: cor(sig_m,rv_{m-1}) - cor(sig_m,rv_m)  [창-밖/안 대비]", B_clean, B_dirty,
       function(c_, d_) c_ > 0 && d_ <= 0),
    mk("C: cor(sig_m, |홀딩월 첫 거래일 수익|)  [동월 반응 직접]", C_clean, C_dirty,
       function(c_, d_) abs(d_) - abs(c_) > 0.05)
  ),
  interpretation = paste0(
    "판별 규칙은 '오염 판에서 부호가 뒤집히거나 문턱을 넘는가' 다. 분리폭(separation)만 크고 ",
    "양쪽 다 같은 부호면 문턱 없는 통계량이라 단독 판정 근거가 못 된다 — 기준선이 필요하다."),
  metric_type = "interface_verification_detector_power",
  role_boundary = list(covariance_estimated = FALSE, weights_proposed = FALSE, performance_measured = FALSE)
)
writeLines(toJSON(res, auto_unbox=TRUE, pretty=TRUE, digits=10, na="null"),
           file.path(OUT, "detector_power.json"))
cat(toJSON(res, auto_unbox=TRUE, pretty=TRUE, digits=6, na="null"))
