## FQ-164 P0 — 새 배정 가드 첫 실전 사용 + 착수 전 사전 확인
## 대상: 부분-리밸 연산자 — 점수는 **fresh 유지**하고 하위 k개만 교체(교체 상한 c)
## 배경: FQ-178 이 staleness(점수를 늙히는 축)에서 비용절감 ≈ 신호손실 **1:1 교환**을 실측했다.
##   부분-리밸은 **다른 축**이다: 매월 fresh 점수로 재평가하되 경계 churn 만 잘라낸다.
##   상위 신선도를 보존하므로 교환이 **비대칭**일 수 있다 — 이것이 미측정 가설.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ164")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/claim_state.R")
source("02_Infrastructure/ops/frontier_queue_io.R")

## ---- 0. ★새 가드 첫 실전 — assert_can_start() 경유 --------------------------
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
i <- which(ids == "FQ-164")
if (!length(i)) { say("★FQ-164 부재 — 중단"); quit(status = 1) }
say("=== 0. 배정 가드 (claim_state.R 첫 실전) ===")
cs <- claim_state(Q$entries[[i]])
say("  state=%s · source=%s · safe_to_start=%s", cs$state, cs$source, cs$safe_to_start)
say("  owner 원문: %s", substr(cs$note, 1, 150))
MY <- "Q-Lead 2026-08-09"
g <- assert_can_start(Q$entries[[i]], "FQ-164", my_session = MY)  # 안전하지 않으면 stop()
say("  ★가드 통과 — 착수 자격 확인 (재진입=%s)", isTRUE(g$reentry))

if (!isTRUE(g$reentry)) {   # 이미 내 claim 이면 재기록 불필요
  Q$entries[[i]] <- make_claim(Q$entries[[i]], "claimed", MY,
    "부분-리밸 연산자 측정. 완료 시 complete 로 전이하고 result_ref 기입.")
  Q$updated <- "2026-08-09"; write_frontier_queue(Q)
  say("  claim 선언 기록 · 재읽기 state=%s",
      claim_state(read_frontier_queue()$entries[[i]])$state)
}

## ---- 1. 입력 실측 -------------------------------------------------------------
say("=== 1. 입력 실측 ===")
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
A <- as.data.table(P$A); ret <- as.data.table(P$ret); liq <- as.data.table(P$liq)
say("  scores %d행 · %d개월 · %s ~ %s", nrow(A), uniqueN(A$Date), min(A$Date), max(A$Date))
S <- A[, .(Date, Ticker, score = M26_Revenue_Mom)][!is.na(score)]
say("  M26 점수 %d행 · 대상 = FQ-178 이 쓴 것과 동일 패널(중복 측정 회피)", nrow(S))

## ---- 2. ★핵심 사전 확인 — 경계 churn 이 실제로 존재하나 ----------------------
say("=== 2. ★경계 churn 실측 — 부분-리밸이 잘라낼 대상이 있나 ===")
S2 <- merge(S, liq[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
S2 <- S2[is.na(adv) | adv >= 2e8]
setorder(S2, Date, -score)
S2[, rk := seq_len(.N), by = Date]
dts <- sort(unique(S2$Date))
top <- S2[rk <= 25L, .(Date, Ticker, rk)]
ch <- list()
for (j in 2:length(dts)) {
  a <- top[Date == dts[j-1], Ticker]; b <- top[Date == dts[j], Ticker]
  new <- setdiff(b, a); out <- setdiff(a, b)
  ## 이탈 종목이 **직전 달 순위 하위**였나(경계) vs 상위였나
  rk_out <- top[Date == dts[j-1] & Ticker %in% out, rk]
  ## 신규 진입 종목의 **현재 순위**
  rk_in <- top[Date == dts[j] & Ticker %in% new, rk]
  ch[[length(ch)+1L]] <- data.table(Date = dts[j], n_turn = length(new),
    med_rk_out = if (length(rk_out)) median(rk_out) else NA_real_,
    med_rk_in  = if (length(rk_in))  median(rk_in)  else NA_real_,
    n_out_bottom10 = sum(rk_out > 15L), n_in_bottom10 = sum(rk_in > 15L))
}
C <- rbindlist(ch)
say("  월평균 교체 %.1f종 / 25 (%.1f%%)", mean(C$n_turn), 100*mean(C$n_turn)/25)
say("  이탈 종목의 직전 순위 중앙 %.1f · 신규 진입 종목의 현재 순위 중앙 %.1f",
    median(C$med_rk_out, na.rm=TRUE), median(C$med_rk_in, na.rm=TRUE))
say("  ★이탈 중 하위권(rk>15) 비율 %.1f%% · 신규 중 하위권 비율 %.1f%%",
    100*sum(C$n_out_bottom10)/sum(C$n_turn), 100*sum(C$n_in_bottom10)/sum(C$n_turn))
say("  ⇒ 교체가 **경계(하위권)에 몰려 있으면** 부분-리밸이 잘라낼 대상이 실재한다.")
say("     상위권에서도 많이 갈리면 교체 상한은 **알파를 자른다**(설계 재고).")

## ---- 3. 이탈 종목의 사후 성과 — 자를 가치가 있나 -----------------------------
say("=== 3. ★이탈 종목이 실제로 나빴나 (자를 가치 판정) ===")
R <- ret[!is.na(Ret_1m)]
perf <- list()
for (j in 2:length(dts)) {
  a <- top[Date == dts[j-1], Ticker]; b <- top[Date == dts[j], Ticker]
  out <- setdiff(a, b); keep <- intersect(a, b); new <- setdiff(b, a)
  m <- R[Date == dts[j]]
  f <- function(tk) { v <- m[Ticker %in% tk, Ret_1m]; if (length(v)) mean(v) else NA_real_ }
  perf[[length(perf)+1L]] <- data.table(Date = dts[j], r_out = f(out), r_keep = f(keep), r_new = f(new))
}
PF <- rbindlist(perf)[!is.na(r_out) & !is.na(r_new)]
say("  이탈군 익월 평균 %+.5f · 유지군 %+.5f · 신규군 %+.5f (n=%d개월)",
    mean(PF$r_out), mean(PF$r_keep, na.rm=TRUE), mean(PF$r_new), nrow(PF))
d <- PF$r_new - PF$r_out
say("  ★신규 − 이탈 = %+.5f/월 (연 %+.2f%%) · t %.3f",
    mean(d), mean(d)*12*100, mean(d)/(sd(d)/sqrt(length(d))))
say("  ⇒ **양수면 교체가 가치를 만든다**(자르면 손해) · 음수면 교체가 소모다(자를 가치 있음)")
say("  ★이 부호가 라운드 설계를 정한다 — 사전 확인이 설계를 바꾼 6번째 지점")

fwrite(C, file.path(OUT, "p0_churn.csv")); fwrite(PF, file.path(OUT, "p0_perf.csv"))
saveRDS(list(churn = C, perf = PF), file.path(OUT, "p0.rds"))
say("=== P0 완료 ===")
