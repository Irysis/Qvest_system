suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")
S <- readRDS(file.path(DIR, "p3.rds")); u <- S$u; bmm <- S$bmm
m <- merge(u[, .(ym, lab_on)], bmm[, .(ym, k = .I)], by = "ym"); setorder(m, k)
m[, k_evt := k + 1L]
m <- merge(m, bmm[, .(k_evt = .I, evt = bm_ret)], by = "k_evt"); setorder(m, k)
sig <- ifelse(m$lab_on, -1, 1)
cat(sprintf("point-biserial IC (라벨 신호 부호 vs 다음달 시장수익), 전표본 n=%d : %+.4f\n",
            nrow(m), cor(sig, m$evt, method = "spearman")))
p2 <- readRDS(file.path(DIR, "p4_panel_labeled.rds")); setDT(p2)
s2 <- ifelse(p2$lab_on, -1, 1)
cat(sprintf("point-biserial IC (배포창 vs base ret_orig), n=%d : %+.4f\n",
            nrow(p2), cor(s2, p2$ret_orig, method = "spearman")))
cat(sprintf("배포창 incumbent MDD 최저점 구간의 라벨 ON 비율 확인용: ON=%d/%d\n", sum(p2$lab_on), nrow(p2)))
