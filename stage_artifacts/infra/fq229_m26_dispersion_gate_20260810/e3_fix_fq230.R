## =============================================================================
## FQ-229 (E3) — 자기정정: FQ-230 항목의 가설이 내 사이징 실측과 어긋난다
##  내가 쓴 가설: "현대 감쇠의 상당분이 횡단면 분산 **축소**"
##  실측(e2):     분산은 오히려 **증가**했다(초기 0.1082 → 현대 0.1145, 비 1.057) ⇒ 설명분 −9.0%
##  ⇒ 가설 방향이 틀렸다. 그러나 **더 나은 질문**이 그 자리에서 나온다:
##     FQ-225 nested 표에서 disp_t 통제 시 시간계수가 **2배**(잔존율 1.963)로 커지고 t 가 −0.85 → −1.57 로 간다.
##     즉 분산은 설명변수가 아니라 **억제변수(suppressor)** 다. 그렇다면 FQ-225 가 선언한
##     "판정 불가 — 추세검정에 501개월 필요"의 지평이 통제 하에서 얼마로 줄어드는가?
## metric_type: canonical_screen_diag (필요표본 산출은 관측 효과 지속 가정 — FQ-225 와 동일 규약)
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[e3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
T_THRESH <- 2.0; NWLAG <- 3L
ols_nw <- function(y, X, lag = NWLAG) {
  X <- cbind(`(Intercept)` = 1, as.matrix(X)); ok <- is.finite(y) & apply(is.finite(X), 1, all)
  y <- y[ok]; X <- X[ok, , drop = FALSE]; n <- length(y)
  XtXi <- solve(crossprod(X)); b <- as.numeric(XtXi %*% crossprod(X, y)); e <- as.numeric(y - X %*% b)
  S <- crossprod(X*e)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1)
    G <- crossprod((X*e)[(l+1):n,,drop=FALSE], (X*e)[1:(n-l),,drop=FALSE])/n; S <- S + w*(G+t(G)) }
  V <- XtXi %*% (n*S) %*% XtXi; se <- sqrt(pmax(diag(V),0))
  data.table(term = colnames(X), est = b, se = se, t = b/se, n = n,
             r2 = 1 - sum(e^2)/sum((y-mean(y))^2)) }

A <- readRDS(file.path(OUT, "a1_results.rds")); DT <- as.data.table(A$DT); setorder(DT, signal_ym)
DT[, tau := (seq_len(.N) - (.N + 1)/2)/12]
say("================ 무통제 vs 분산통제 추세 (FQ-225 재현 + 필요표본 재계산) ================")
r_un <- ols_nw(DT[["M26_Revenue_Mom"]], DT[, .(tau)])
r_cd <- ols_nw(DT[["M26_Revenue_Mom"]], DT[, .(tau, disp_t)])
show <- function(r, lab) { row <- r[term == "tau"]
  say("  %-16s c_tau %+.8f · se %.8f · t %+.3f · R2 %.4f", lab, row$est, row$se, row$t, r$r2[1]); row }
u <- show(r_un, "무통제"); k <- show(r_cd, "분산통제")
say("  disp_t 계수 t = %+.3f (FQ-225 nested 기록 +3.63 계열)", r_cd[term == "disp_t", t])
say("★억제 효과: 시간계수 %+.8f → %+.8f (배수 %.3f) · |t| %.3f → %.3f",
    u$est, k$est, k$est/u$est, abs(u$t), abs(k$t))

nreq <- function(row, n) { need <- T_THRESH * row$se
  n * (need/abs(row$est))^(2/3) }   ## 등간격 tau 에서 se_c ∝ n^{-1.5} (FQ-225 A4 와 동일 규약)
n0 <- nrow(DT)
nu <- nreq(u, n0); nk <- nreq(k, n0)
say("★필요표본 (관측 효과 지속 가정 — FQ-225 A4 와 동일 규약):")
say("   무통제  %.0f개월 (%.1f년) ⇒ 추가 %.1f년   [FQ-225 기록 501.8개월 / 추가 18.2년]", nu, nu/12, max(0,(nu-n0)/12))
say("   분산통제 %.0f개월 (%.1f년) ⇒ 추가 %.1f년", nk, nk/12, max(0,(nk-n0)/12))
say("   ⇒ 지평 단축 %.1f년 (%.0f%% 감소)", (nu-nk)/12, 100*(1-nk/nu))

## 검정력 바 (80%) 로도 병기
n80 <- function(row, n) { need <- (T_THRESH + qnorm(0.80)) * row$se; n * (need/abs(row$est))^(2/3) }
say("   80%% 검정력 기준: 무통제 %.0f개월 · 분산통제 %.0f개월 (추가 %.1f년)",
    n80(u, n0), n80(k, n0), max(0, (n80(k, n0)-n0)/12))

## ---------------------------------------------------------------- 큐 항목 정정
say("================ FQ-230 항목 정정 (read -> modify -> write -> re-read) ================")
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-230"); if (!length(i)) stop("[e3] FQ-230 부재 — 0은 정지 신호")
e <- Q$entries[[i]]
e$title <- "분산 통제 하 M26 시간추세 — 분산은 설명변수가 아니라 억제변수, FQ-225 '판정 불가' 지평 재계산"
e$hypothesis <- paste0(
  "FQ-225 는 현대 약화를 '판정 불가'로 남겼다(추세검정 필요 501.8개월 = 추가 18.2년). ",
  "그 계산은 **무통제** 추세 기준이다. FQ-229 가 payoff 의 동시점 분산 비례를 확정했고(h=0 스케일 t +3.491 ∧ 기술 t +3.400), ",
  "FQ-225 nested 표에서 disp_t 통제 시 시간계수 잔존율이 1.963 = **2배로 커진다**. ",
  "즉 분산은 감쇠를 설명하는 변수가 아니라 감쇠를 **가리는 억제변수**다. ",
  "가설: 분산을 통제하면 추세 추정이 커지고 잔차분산이 줄어 판정 지평이 크게 단축된다.")
e$ev_rationale <- sprintf(paste0(
  "★사이징 실측(FQ-229 e2/e3, 즉시 산출): ①분산은 현대에 **증가**했다(초기 0.1082 → 현대 0.1145, 비 1.057). ",
  "b_t 평균은 초기 0.002251 → 현대 0.000822 인데, 분산비만으로 예측되는 현대 평균은 0.002380 ",
  "(즉 분산은 payoff 를 **키우는** 방향으로 움직였다) ⇒ '감쇠 = 분산 축소' 가설은 실측으로 기각, 설명분 −9.0%%. 방향이 반대다. ",
  "②그 대신 억제 효과가 실재한다: 시간계수 %+.8f → %+.8f (배수 %.2f) · |t| %.2f → %.2f · R2 %.4f → %.4f. ",
  "③필요표본(효과 지속 가정, FQ-225 A4 동일 규약): 무통제 %.0f개월(추가 %.1f년) → 분산통제 %.0f개월(추가 %.1f년), 지평 %.0f%% 단축. ",
  "80%% 검정력 기준으로도 분산통제 %.0f개월. 신규 데이터 없이 사양 변경만으로 얻는 이득이다."),
  u$est, k$est, k$est/u$est, abs(u$t), abs(k$t), r_un$r2[1], r_cd$r2[1],
  nu, max(0,(nu-n0)/12), nk, max(0,(nk-n0)/12), 100*(1-nk/nu), n80(k, n0))
e$wall_check <- paste0(
  "미측정(사전등록 전). 주의 3종: ①분산통제 추세는 여전히 |t| ", sprintf("%.2f", abs(k$t)),
  " < 2.0 — 현 표본으로는 검출 아님. 지평 단축이지 판정 역전이 아니다. ",
  "②FQ-225 nested 표(잔존율 1.963)는 그 라운드가 A1 미검출을 이유로 N/A 처리한 셀이다 — 미등록 관측을 가설로 승격하는 것이므로 사전등록 필수. ",
  "③추세 t 는 횡단면 신호력 계수의 시간변화이지 PORT_t 감쇠가 아니다. 전이 벽 별도.")
e$data_gate <- "closed — alpha_scores.parquet + FQ-229 a1_monthly_components.csv 로 즉시 착수 가능. 신규 수집 불요"
e$next_action <- paste0(
  "사전등록: 주판정 = 분산통제 연속 추세(분할 금지) · 보조 = 억제 구조 확인(disp_t 와 tau 의 상관 부호) · ",
  "양성 대조 = C01/C02/C04 에 같은 통제(억제가 M26 고유인가) · 필요표본 재산출. ",
  "소비면 = monitoring 감쇠 판정의 분산 정규화(저분산 달 payoff 저하를 신호 열화로 오독 차단) — ",
  "단 FQ-229 실측상 분산 정규화는 원계열 t 를 낮춘다(2.555 → 1.815)므로 정규화 방향을 먼저 규정할 것.")
Q$entries[[i]] <- e
res <- write_frontier_queue(Q)
say("기록: 총 %d · 추가 %d · 삭제 %d", res$n, length(res$added), length(res$removed))
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(x) as.character(x$id)[1], character(1))
e2c <- Q2$entries[[which(ids2 == "FQ-230")]]
say("★재읽기 검증: FQ-230 title = %s", substr(as.character(e2c$title)[1], 1, 80))
say("   가설 방향 정정 반영 여부 = %s", grepl("억제변수", as.character(e2c$hypothesis)[1]))
if (!grepl("억제변수", as.character(e2c$hypothesis)[1])) stop("[e3] ★정정 미반영 — 침묵 실패")

saveRDS(list(unctrl = u, ctrl = k, n_req_unctrl = nu, n_req_ctrl = nk,
             n_req_ctrl_80 = n80(k, n0), disp_early = 0.1082, disp_modern = 0.1145),
        file.path(OUT, "e3_results.rds"))
say("저장 완료 -> %s", OUT)
