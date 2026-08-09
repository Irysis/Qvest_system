## FQ-143 P8 — 사전선언 반증축 (a): 꼬리 분리가 단일 에피소드에 업혀 있는가 + 군집 확인
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")
source(file.path(ROOT, "02_Infrastructure/contracts/label_eligibility_gate.R"))
S <- readRDS(file.path(DIR, "p3.rds")); u <- S$u; bmm <- S$bmm
m <- merge(u[, .(ym, lab_on)], bmm[, .(ym, k = .I)], by = "ym"); setorder(m, k)
m[, k_evt := k + 1L]
m <- merge(m, bmm[, .(k_evt = .I, evt_ym = ym, evt = bm_ret)], by = "k_evt"); setorder(m, k)

cat("=== [P8-1] 에피소드 제거 강건성 (사건 = 다음달 시장 < -10%) ===\n")
drops <- list(none = character(0),
              GFC_2008_09 = c("2008","2009"), COVID_2020 = c("2020"),
              ASIA_1997_98 = c("1997","1998"), both_GFC_COVID = c("2008","2009","2020"),
              all_three = c("1997","1998","2008","2009","2020"))
out <- rbindlist(lapply(names(drops), function(nm) {
  yy <- drops[[nm]]
  d <- if (length(yy)) m[!(substr(evt_ym,1,4) %in% yy)] else m
  g <- label_eligibility(d$lab_on, d$evt < -0.10)
  data.table(drop = nm, n = g$n, n_on = g$n_on, n_evt = g$n_event,
             recall = g$recall, base = g$base_rate, lift = g$lift, p = g$fisher_p, verdict = g$verdict)
}))
print(out[, .(drop, n, n_on, n_evt, recall = round(recall,4), base = round(base,4),
              lift = round(lift,3), p = signif(p,3), verdict)])

cat("\n=== [P8-2] 라벨 ON 의 군집(run) 구조 — 산발인가 에피소드인가 ===\n")
r <- rle(m$lab_on)
onlen <- r$lengths[r$values]
cat(sprintf("  ON run 개수=%d  총 ON월=%d  평균 run 길이=%.2f  중앙값=%.1f  최장=%d\n",
            length(onlen), sum(onlen), mean(onlen), median(onlen), max(onlen)))
cat(sprintf("  무작위 재배치 시 기대 run 길이 = %.2f (기하분포 1/(1-p), p=%.3f)\n",
            1/(1-mean(m$lab_on)), mean(m$lab_on)))
cat("  -> 실측 run 길이 >> 무작위 기대치면 에피소드 군집 = 유효표본 < 명목 표본\n")
## 유효표본 근사: run 단위로 세면
cat(sprintf("  ★유효 독립단위 근사 = ON run 수 %d (명목 ON월 %d 의 %.0f%%)\n",
            length(onlen), sum(onlen), 100*length(onlen)/sum(onlen)))

cat("\n=== [P8-3] 꼬리 사건(<-10%)의 군집 ===\n")
ev <- m$evt < -0.10
re <- rle(ev); evlen <- re$lengths[re$values]
cat(sprintf("  꼬리월 %d개 -> 연속 run %d개 (평균 %.2f). 에피소드 수 기준 유효표본 = %d\n",
            sum(ev), length(evlen), mean(evlen), length(evlen)))
cat(sprintf("  꼬리월 연도: %s\n", paste(sort(unique(substr(m$evt_ym[ev],1,4))), collapse=", ")))
fwrite(out, file.path(DIR, "p8_episode_robustness.csv"))
cat("\n[P8 DONE]\n")
