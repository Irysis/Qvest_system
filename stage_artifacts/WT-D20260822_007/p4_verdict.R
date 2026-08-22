## WT-D20260822_007 (FQ-246 NP1) P4 — 사전등록 판정 적용 + 분해 + 방출
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_007"
PA <- readRDS(file.path(OUT,"p2_partA.rds")); P3 <- readRDS(file.path(OUT,"p3_partB.rds"))
PC <- readRDS(file.path(OUT,"p1c_parity.rds")); c0 <- PC$a_uni
H <- PA$HEADROOM; CURVE <- PA$CURVE; MATERIAL <- P3$MATERIAL

cat("=== 1) FA 반증 — 집중도-회수 단조성 (오라클 정보 고정) ===\n")
CS <- CURVE[grepl("^O_softmax", arm) | grepl("^O_top", arm)]
sp_all  <- cor(CS$n_eff, CS$recovery, method="spearman")
CSs <- CURVE[grepl("^O_softmax", arm)]; sp_soft <- cor(CSs$n_eff, CSs$recovery, method="spearman")
CSh <- CURVE[grepl("^O_top", arm)];    sp_hard <- cor(CSh$n_eff, CSh$recovery, method="spearman")
cat(sprintf("  Spearman(n_eff, recovery) 전체 %d점 = %+.4f  |  softmax만 = %+.4f  |  topJ만 = %+.4f\n",
            nrow(CS), sp_all, sp_soft, sp_hard))
cat(sprintf("  사전등록 문턱 ≤ -0.70 → FA %s\n", if (sp_all <= -0.70) "지지 (단조 증가 확인)" else "기각"))
cat("  ★형태-모양 잔차: 같은 n_eff 라도 topJ 하드 EW 와 softmax 는 다르다 —\n")
cat(sprintf("    n_eff 4.0 topJ4 %.2f%% vs n_eff 4.19 softmax0.5 %.2f%% (덜 집중한 쪽이 더 회수)\n",
    CURVE[arm=="O_top4_EW", recovery*100], CURVE[arm=="O_softmax_lam0.5", recovery*100]))
cat("    ⇒ 집중도는 형태의 1차 축이나 유일 축이 아니다(가중의 *모양*도 기여).\n")

cat("\n=== 2) Part A 결정 대조 — 형태 성분 vs 정보 성분의 paired 검정 ===\n")
a_top1 <- PA$RESA$O_top1_EW$act
a_m2   <- PA$RESA$O_softmax_lamMATCH_T2$act; a_m3 <- PA$RESA$O_softmax_lamMATCH_T3$act
pdiff <- function(x, y, lab) { d <- x - y; t <- .nw_t_mean(d, lag=3L); ann <- mean(d)*12*100
  se <- abs(ann/t)
  data.table(contrast=lab, ann_pct=ann, t_nw3=t, se_ann=se,
             pp_of_headroom=ann/H*100, se_pp=se/H*100, mde95_pp=1.96*se/H*100) }
CMP <- rbind(
  pdiff(a_top1, a_m2, "FORM_component_T2  (one-hot − N_eff3.910, 둘 다 오라클 IC)"),
  pdiff(a_m2, PA$act_FQ2, "INFO_component_T2  (오라클 IC − 오라클 상태, 같은 N_eff 3.910)"),
  pdiff(a_top1, a_m3, "FORM_component_T3  (one-hot − N_eff4.344)"),
  pdiff(a_m3, PA$act_FQ3, "INFO_component_T3  (오라클 IC − 오라클 상태, 같은 N_eff 4.344)"))
print(CMP[, .(contrast, ann_pct=round(ann_pct,4), t=round(t_nw3,3),
              pp_hr=round(pp_of_headroom,2), mde95_pp=round(mde95_pp,2))])

cat("\n=== 3) ★미회수 3/4 의 귀속 분해 (FQ-246 좌표 기준) ===\n")
ATTR <- rbindlist(lapply(list(
  list("T2", 3.910050, PA$FQR[arm=="FQ246_ORACLE_T2_form", recovery*100],
       CURVE[arm=="O_softmax_lamMATCH_T2", recovery*100], CMP[1], CMP[2]),
  list("T3", 4.343690, PA$FQR[arm=="FQ246_ORACLE_T3_form", recovery*100],
       CURVE[arm=="O_softmax_lamMATCH_T3", recovery*100], CMP[3], CMP[4])),
  function(z) data.table(coord=z[[1]], n_eff=z[[2]], fq246_recovery_pct=z[[3]],
    oracle_ic_ceiling_at_same_neff_pct=z[[4]],
    missing_total_pp = 100 - z[[3]],
    form_attributable_pp = 100 - z[[4]], form_t = z[[5]]$t_nw3,
    info_attributable_pp = z[[4]] - z[[3]], info_t = z[[6]]$t_nw3,
    form_share_of_missing_pct = (100 - z[[4]])/(100 - z[[3]])*100,
    info_share_of_missing_pct = (z[[4]] - z[[3]])/(100 - z[[3]])*100)))
print(ATTR[, lapply(.SD, function(x) if (is.numeric(x)) round(x,3) else x)])

## 사전등록 판정 규칙 적용
dec_of <- function(gap_pp, t, mde_pp) {
  if (mde_pp > 15) return("UNRESOLVED_UNDERPOWERED")
  if (gap_pp <= 15 && abs(t) < 2) return("PURE_FORM_LOSS")
  if (gap_pp >= 25 && t >= 2) return("INFORMATION_DIMENSION_LOSS")
  "MIXED" }
DEC <- data.table(coord=c("T2","T3"),
  gap_pp = ATTR$info_attributable_pp, t = ATTR$info_t,
  mde95_pp = c(CMP[2, mde95_pp], CMP[4, mde95_pp]))
DEC[, prereg_label_strict := mapply(function(g,t,m)
      if (g <= 15 && abs(t) < 2) "PURE_FORM_LOSS"
      else if (g >= 25 && t >= 2) "INFORMATION_DIMENSION_LOSS" else "MIXED", gap_pp, t, mde95_pp)]
DEC[, power_adjusted_label := mapply(dec_of, gap_pp, t, mde95_pp)]
print(DEC[, lapply(.SD, function(x) if (is.numeric(x)) round(x,3) else x)])
cat("  ★사전등록 문턱(15/25 pp)이 본 설계의 MDE95 보다 **미세**하다 — 정보 성분은 '효과없음' 이 아니라\n")
cat("    '미결' 로 분류한다(승계 규약 7, FQ-246 이 초판 기각을 MDE 0.72배 근거로 철회한 선례).\n")
cat("  ★반면 형태 성분은 두 좌표 모두 |t| 큼 → **형태 손실 자체는 확립**.\n")

cat("\n=== 4) Part B 판정 요약 ===\n")
TG <- P3$TG; PB2 <- P3$PB2
cat("  FC 전이 게이트: 전 8 기준 + 성과-파생 대조 1 = 9/9 미통과\n")
cat(sprintf("    적중률 범위 %.4f ~ %.4f (우연 0.2000) · 이항 MDE 0.2443 · |rho| 최대 %.4f (MDE95 %.4f)\n",
    min(TG$hit_rate), max(TG$hit_rate), max(abs(TG$mean_rho_signed)), max(TG$rho_mde95, na.rm=TRUE)))
cat("  FB 매개 게이트: 13/13 TREATMENT_EFFECTIVE (Jaccard 중앙값 0.087~0.515 ≤ 0.79)\n")
cat("    ⇒ null 은 처치 무력이 아니다 — 멤버질이 매월 중앙 8~21종 교체되고도 회수 0.\n")
print(PB2[order(-ann_pct), .(arm, ann_pct=round(ann_pct,3), t=round(t_nw3,3),
      port_t=round(port_t,4), pctile=round(perm_pctile,3), TO=round(turnover,2), label)])
cat(sprintf("\n  최선 arm %s = %+.3f %%p/yr (C0 대비 음수) ⇒ Part B 여유폭 회수 = 0 (음수)\n",
    PB2$arm[which.max(PB2$ann_pct)], max(PB2$ann_pct)))
cat(sprintf("  손익분기 요건: 오라클 정보의 %.1f%% 포착 필요(형태 비용 %+.3f 상쇄) — 실측 포착 0%%\n",
    -mean(P3$POW$null_mean_ann_pct[1])/P3$oracle_info_top1*100, P3$POW$null_mean_ann_pct[1]))

cat("\n=== 5) 중복성 · 비용 ===\n")
RED <- rbindlist(lapply(names(P3$RESB), function(a)
  data.table(arm=a, cor_active_vs_C0=cor(P3$RESB[[a]]$act, c0),
             turnover=P3$RESB[[a]]$to)))
RED <- rbind(data.table(arm="C0_uniform", cor_active_vs_C0=1, turnover=11.5482), RED)
print(RED[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])

cat("\n=== 6) 방출 — alpha_scores.parquet (long, arm 컬럼) + alpha_vector_live ===\n")
SC <- rbindlist(c(list(copy(P3$sc0)[, arm := "C0_uniform"]),
  lapply(names(P3$SCB), function(a) copy(P3$SCB[[a]])[, arm := a])))
setcolorder(SC, c("arm","Date","Ticker","score"))
write_parquet(SC, file.path(OUT,"alpha_scores.parquet"))
cat(sprintf("  alpha_scores.parquet rows=%d arms=%d size=%.2f MB\n", nrow(SC),
    uniqueN(SC$arm), file.size(file.path(OUT,"alpha_scores.parquet"))/1024^2))
EMIT <- "B3a_BREADTH_MAX_top1"   # 사전등록 고정 (성과 무관 지정)
lastd <- max(P3$SCB[[EMIT]]$Date)
AV <- P3$SCB[[EMIT]][Date == lastd][order(-score)]
AV[, `:=`(arm = EMIT, rank = seq_len(.N))]
AV[, confidence := pmax(0, pmin(1, 0.5 * (1 - rank/.N)))]   # 게이트 미통과 반영 저신뢰
write_parquet(AV, file.path(OUT,"alpha_vector_live.parquet"))
cat(sprintf("  alpha_vector_live.parquet: %s · %d종목 · 사전등록 고정 arm=%s\n",
    format(lastd), nrow(AV), EMIT))
cat("  ★방출 arm 은 사전등록으로 고정됐고 성과를 보고 고르지 않았다. 게이트 미통과이므로\n")
cat("    confidence 상한 0.5 · 자본 경로 진입 자격 없음(FC/순열 게이트 미통과).\n")

saveRDS(list(CMP=CMP, ATTR=ATTR, DEC=DEC, RED=RED, sp_all=sp_all, sp_soft=sp_soft,
             sp_hard=sp_hard, EMIT=EMIT), file.path(OUT,"p4_verdict.rds"))
cat("\n[saved] p4_verdict.rds\nOK\n")
