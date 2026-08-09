## FQ176 — 조건부 IC 측정 · 그룹 flow_consensus (INV*/CR*/C*/MA*/S*)
## metric_type = canonical_screen_diag. 자본 주장 없음.
##
## ★시간축 규약 (실측 검증됨, probe 로그):
##   panel/IC 의 Date = 신호 관측 월말 t (= 월 M 의 말일)
##   Ret_1m[t]        = forward 1M, 즉 t -> t+1 (월 M+1 동안 실현되는 수익)
##                      실측 근거: cor(xs_mean_ret[d], BM_Ret[d]) = +0.8353
##                                 cor(xs_mean_ret[d], BM_Ret[d-1]) = -0.0884
##                      (BM_Ret 은 power_gate 선언대로 forward. 같은 행 상관이 압도)
##   IC[t]            = spearman(z_t , Ret_1m[t]) = "t 월말 팩터값 x 그 다음 달 수익"
##   신호 S[t]        = ret_realized[t] = BM_Ret[t-1] 기반 -> t 시점 관측가능 (PIT clean)
##
## 따라서 "신호 ON 인 달의 *다음달* 횡단면 rank-IC" =
##   H1 (primary, same-row) : IC[t]      — 신호 직후 1개월 창 (t -> t+1)
##   H2 (literal, lead-1)   : IC[t+1]    — 신호 후 2번째 달 창 (t+1 -> t+2, 1개월 스킵)
## 지시문은 "다음 행(t+1)" 이라 썼으나, 그 근거로 든 PIT 조건("t+1 forward 수익")은
## 실측 규약에서 H1 이 충족한다. 두 정렬 모두 PIT 위반 아님(둘 다 신호 이후 창).
## 자격단계 required 바가 계산된 분할(n_ON=46/n_OFF=236)도 same-row 매칭이므로 H1 = primary.
## 은폐 없이 둘 다 산출·저장한다.

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[fc] ", fmt, "\n"), ...)); flush.console() }

GRP      <- "flow_consensus"
GRP_RE   <- "^(INV[0-9]|CR[0-9]|C[0-9]|MA[0-9]|S[0-9])"
SE_INFL  <- 1.25
T_CRIT   <- 2.0

## ---------------------------------------------------------------
## 0. 입력 로드 + 실측
## ---------------------------------------------------------------
IC  <- as.data.table(readRDS(file.path(OUT, "ic_series.rds"))); IC[, Date := as.Date(Date)]
SIG <- fread(file.path(OUT, "signals.csv")); SIG[, Date := as.Date(Date)]
ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
mo  <- sort(unique(SIG$Date))

say("=== 0. 입력 실측 ===")
say("  ic_series : %d행 · 팩터 %d · 개월 %d · %s ~ %s (관측단위 = 팩터 x 월)",
    nrow(IC), uniqueN(IC$factor), uniqueN(IC$Date), format(min(IC$Date)), format(max(IC$Date)))
say("  IC 값     : mean %+.5f · sd %.5f · min %+.4f · max %+.4f · NA %d",
    mean(IC$ic), sd(IC$ic), min(IC$ic), max(IC$ic), sum(is.na(IC$ic)))
say("  n_xs      : median %.0f (min %d / max %d)", median(IC$n_xs), min(IC$n_xs), max(IC$n_xs))
say("  signals   : %d개월 · %s ~ %s · S1 %d / S2 %d / S3 %d ON",
    nrow(SIG), format(min(SIG$Date)), format(max(SIG$Date)), sum(SIG$S1), sum(SIG$S2), sum(SIG$S3))
say("  eligible  : %d쌍", nrow(ELI))

## 신호 ON 의 군집성(유효표본 진단) — 연속 ON 런 개수
run_info <- function(v) { r <- rle(v); sum(r$values); list(n_on = sum(v), n_runs = sum(r$values),
                                                           max_run = if (any(r$values)) max(r$lengths[r$values]) else 0L) }
for (s in c("S1","S2","S3")) {
  ri <- run_info(SIG[[s]])
  say("  %s 군집성: n_ON %d · 연속 런 %d개 · 최장 런 %d개월 (독립 에피소드 ~%d)",
      s, ri$n_on, ri$n_runs, ri$max_run, ri$n_runs)
}

## ---------------------------------------------------------------
## 1. 그룹 필터
## ---------------------------------------------------------------
say("=== 1. 그룹 %s 필터 (정규식 %s) ===", GRP, GRP_RE)
G <- ELI[grepl(GRP_RE, factor)]
if (!nrow(G)) { say("  ★그룹 소속 자격통과 쌍 0건 — 빈 결과 정직 반환 (0 = 정지 신호)"); }
say("  자격통과 %d쌍 중 그룹 소속 %d쌍:", nrow(ELI), nrow(G))
for (i in seq_len(nrow(G)))
  say("    %-30s %s  ic_mean %+.5f · ic_sd %.5f · required %.5f · n_ON %d / n_OFF %d",
      G$factor[i], G$signal[i], G$ic_mean[i], G$ic_sd[i], G$required[i], G$n_ON[i], G$n_OFF[i])

## ---------------------------------------------------------------
## 2. ★정렬 구성 + 검증 출력
## ---------------------------------------------------------------
say("=== 2. 신호 -> IC 정렬 구성 ===")
MIDX <- data.table(Date = mo, midx = seq_along(mo))
SG   <- merge(SIG, MIDX, by = "Date")[order(midx)]

align_tbl <- function(sig_col) {
  ## H1: 신호월 t 의 IC 행(=t) ; H2: 신호월 t 의 다음 행(t+1) IC
  on_idx  <- SG[get(sig_col) == TRUE]$midx
  off_idx <- SG[get(sig_col) == FALSE]$midx
  list(
    h1 = list(on = mo[on_idx], off = mo[off_idx]),
    h2 = list(on = mo[on_idx[on_idx + 1L <= length(mo)] + 1L],
              off = mo[off_idx[off_idx + 1L <= length(mo)] + 1L])
  )
}

## 검증: S3 ON 처음 4개 신호월과 각 정렬이 실제로 어떤 IC 월/수익창을 집는지 명시 출력
ai <- align_tbl("S3")
ex_on <- head(SG[S3 == TRUE]$midx, 4)
say("  검증 (S3 ON 앞 4건) — 신호월 t / H1 IC월 / H1 수익창 / H2 IC월 / H2 수익창:")
for (k in ex_on) {
  say("    t=%s | H1 IC=%s (ret %s->%s) | H2 IC=%s (ret %s->%s)",
      format(mo[k]), format(mo[k]), format(mo[k]), format(mo[min(k+1L,length(mo))]),
      format(mo[min(k+1L,length(mo))]), format(mo[min(k+1L,length(mo))]), format(mo[min(k+2L,length(mo))]))
}
say("  -> H1 수익창 = 신호 직후 1개월. H2 수익창 = 신호 후 2번째 달(1개월 스킵).")
say("  H1 ON월 수 %d / OFF월 수 %d · H2 ON월 수 %d / OFF월 수 %d",
    length(ai$h1$on), length(ai$h1$off), length(ai$h2$on), length(ai$h2$off))
say("  H1 ON/OFF 교집합 %d (0 이어야 정상) · H2 ON/OFF 교집합 %d (>0 가능: 스킵정렬 중첩)",
    length(intersect(ai$h1$on, ai$h1$off)), length(intersect(ai$h2$on, ai$h2$off)))

## ---------------------------------------------------------------
## 3. 측정
## ---------------------------------------------------------------
say("=== 3. 조건부 IC 측정 ===")
res <- list()
for (i in seq_len(nrow(G))) {
  f <- G$factor[i]; s <- G$signal[i]
  ics <- IC[factor == f][order(Date)]
  a   <- align_tbl(s)
  row <- list(group = GRP, factor = f, signal = s,
              ic_mean_full = G$ic_mean[i], ic_sd_full = G$ic_sd[i],
              n_months_ic = nrow(ics),
              required_stage = G$required[i], bar_stage = G$bar[i], ratio_stage = G$ratio[i])
  for (h in c("h1","h2")) {
    on_ic  <- ics[Date %in% a[[h]]$on]$ic
    off_ic <- ics[Date %in% a[[h]]$off]$ic
    n_on <- length(on_ic); n_off <- length(off_ic)
    m_on <- mean(on_ic); m_off <- mean(off_ic)
    d    <- m_on - m_off
    se   <- G$ic_sd[i] * sqrt(1/n_on + 1/n_off) * SE_INFL     # 지시 규약 se
    tt   <- d / se
    req  <- T_CRIT * se                                        # 이 정렬 실측 n 으로 재계산한 바
    ## 교차확인용 Welch (지시 se 와 별개 진단)
    se_w <- sqrt(var(on_ic)/n_on + var(off_ic)/n_off)
    t_w  <- d / se_w
    ## ★군집-강건 진단: 신호는 연속 에피소드로 뭉침 -> 유효표본 = 월수 아닌 런 수.
    ##   ON/OFF 각 연속 런의 IC 평균을 1관측으로 접어 재계산 (지시 se 와 별개, 진단용)
    on_d  <- a[[h]]$on;  off_d <- a[[h]]$off
    lab_d <- data.table(Date = c(on_d, off_d), grp = c(rep("ON", length(on_d)), rep("OFF", length(off_d))))
    lab_d <- merge(ics[, .(Date, ic)], lab_d, by = "Date")[order(Date)]
    rl <- rle(lab_d$grp); lab_d[, blk := rep(seq_along(rl$lengths), rl$lengths)]
    BL <- lab_d[, .(grp = grp[1], m = mean(ic), k = .N), by = blk]
    bo <- BL[grp == "ON"]$m; bf <- BL[grp == "OFF"]$m
    se_c <- if (length(bo) >= 2 && length(bf) >= 2)
              sqrt(var(bo)/length(bo) + var(bf)/length(bf)) else NA_real_
    t_c  <- d / se_c
    lab  <- if (abs(tt) >= T_CRIT) "SIGNIFICANT"
            else if (abs(d) >= G$required[i]) "NULL_POWERED"
            else "INCONCLUSIVE_UNDERPOWERED"
    row[[paste0(h,"_n_on")]]      <- n_on
    row[[paste0(h,"_n_off")]]     <- n_off
    row[[paste0(h,"_ic_on")]]     <- m_on
    row[[paste0(h,"_ic_off")]]    <- m_off
    row[[paste0(h,"_ic_on_sd")]]  <- sd(on_ic)
    row[[paste0(h,"_ic_off_sd")]] <- sd(off_ic)
    row[[paste0(h,"_delta_ic")]]  <- d
    row[[paste0(h,"_se")]]        <- se
    row[[paste0(h,"_t")]]         <- tt
    row[[paste0(h,"_required_meas")]] <- req
    row[[paste0(h,"_abs_delta_vs_required_stage")]] <- abs(d) / G$required[i]
    row[[paste0(h,"_t_welch")]]   <- t_w
    row[[paste0(h,"_verdict")]]   <- lab
  }
  res[[length(res)+1L]] <- as.data.table(row)
}
R <- rbindlist(res)
R[, `:=`(metric_type = "canonical_screen_diag",
         alignment_primary = "h1_same_row_signal_t_to_t_plus_1",
         alignment_secondary = "h2_lead1_skip_one_month",
         verdict = h1_verdict)]
setcolorder(R, c("group","factor","signal","verdict","h1_delta_ic","h1_t","h1_verdict",
                 "h2_delta_ic","h2_t","h2_verdict","required_stage"))
fwrite(R, file.path(OUT, "measured_flow_consensus.csv"))

say("  --- 결과 (H1 primary) ---")
for (i in seq_len(nrow(R)))
  say("    %-30s %s | ON %.5f (n=%d) vs OFF %.5f (n=%d) | dIC %+.5f | t %+.3f | req_stage %.5f | %s",
      R$factor[i], R$signal[i], R$h1_ic_on[i], R$h1_n_on[i], R$h1_ic_off[i], R$h1_n_off[i],
      R$h1_delta_ic[i], R$h1_t[i], R$required_stage[i], R$h1_verdict[i])
say("  --- 결과 (H2 지시-문언 lead-1) ---")
for (i in seq_len(nrow(R)))
  say("    %-30s %s | ON %.5f (n=%d) vs OFF %.5f (n=%d) | dIC %+.5f | t %+.3f | %s",
      R$factor[i], R$signal[i], R$h2_ic_on[i], R$h2_n_on[i], R$h2_ic_off[i], R$h2_n_off[i],
      R$h2_delta_ic[i], R$h2_t[i], R$h2_verdict[i])
say("  --- Welch 교차확인 (t_welch) ---")
for (i in seq_len(nrow(R)))
  say("    %-30s H1 t %+.3f (welch %+.3f) · H2 t %+.3f (welch %+.3f)",
      R$factor[i], R$h1_t[i], R$h1_t_welch[i], R$h2_t[i], R$h2_t_welch[i])

say("  저장: %s (%d행 · %d열)", file.path(OUT,"measured_flow_consensus.csv"), nrow(R), ncol(R))
say("=== 완료 ===")
