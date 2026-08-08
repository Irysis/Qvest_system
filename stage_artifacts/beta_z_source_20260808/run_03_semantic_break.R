# run_03_semantic_break.R — 동결 패널의 **의미 전환**과 문턱 단위 불일치 검증
# run_02 발견:
#   2004-01~2026-04 : n≈343, sd_z 0.08~0.95 (표준화 안 됨), mean_z ≈ +0.25  → 유니버스-부분집합 z
#   2026-05~2026-06 : n≈2528, sd_z **정확히 1.0000**, mean_z ≈ −0.09        → 전체시장 재표준화 z
# 가설: 패널 생성 규약이 2026-05 에 바뀌었고, q20 문턱은 **옛 의미의 분포**에서 나온 값이라
#   전환 이후 z 가 상시 문턱 아래로 떨어져 flag 이 **상시 발화**로 고착됐다(단위 불일치).
# 검증: ①전환 전/후 z 분포와 발화율 ②전환이 없었다면 발화했을까(동일 의미 문턱으로 재계산)
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
OUT <- "stage_artifacts/beta_z_source_20260808"
P <- fread("stage_artifacts/tilt_realign_20260808/p20_flag_spec_panel.csv"); P[, Date := as.Date(Date)]
S <- fread(file.path(OUT, "frozen_panel_monthly.csv")); S[, Date := as.Date(Date)]
D <- merge(P, S[, .(Date, n_row, mean_z_panel = mean_z, sd_z)], by="Date", all.x=TRUE)
setorder(D, Date)
BREAK <- as.Date("2026-05-01")
D[, era := ifelse(Date >= BREAK, "post(전체시장·sd=1)", "pre(부분집합)")]
V <- D[is.finite(z) & is.finite(q20)]
cat("[① 전환 전/후 비교]\n")
print(V[, .(개월 = .N,
            패널행수 = round(mean(n_row, na.rm=TRUE)),
            패널_sd_z = round(mean(sd_z, na.rm=TRUE), 3),
            top20_z_평균 = round(mean(z), 4),
            문턱_q20 = round(mean(q20), 4),
            발화율 = sprintf("%.0f%%", 100*mean(z < q20))), by=era])

## ② 동일 의미 문턱으로 재계산 — post 구간의 z 를 post 구간 자체 분포로 표준화해 비교
post <- V[era == "post(전체시장·sd=1)"]; pre <- V[era == "pre(부분집합)"]
cat(sprintf("\n[② 단위 불일치 진단]\n"))
cat(sprintf("  pre  z: 평균 %+.4f · sd %.4f · q20(자체) %+.4f\n", mean(pre$z), sd(pre$z), quantile(pre$z, 0.20, names=FALSE)))
cat(sprintf("  post z: 평균 %+.4f · sd %.4f · (표본 %d개월)\n", mean(post$z), sd(post$z), nrow(post)))
cat(sprintf("  ★현 문턱(pre 분포 유래) = %.4f → post z 전부 그 아래인가: %s (%d/%d)\n",
    mean(post$q20), ifelse(all(post$z < post$q20), "예", "아니오"), sum(post$z < post$q20), nrow(post)))
z_pre_pct <- sapply(post$z, function(x) mean(pre$z < x))
cat(sprintf("  post z 를 **pre 분포 백분위**로 환산: %s → 옛 의미로는 %s\n",
    paste(sprintf("%.1f%%", 100*z_pre_pct), collapse=", "),
    ifelse(all(z_pre_pct < 0.2), "하위20%(발화 정당)", "하위20% 아님(★과발화)")))

cat("\n[③ 전환 이후 β 실제 경로]\n")
print(D[Date >= as.Date("2026-03-01"),
        .(Date, regime, z = round(z,4), q20 = round(q20,4), zlt = ifelse(is.finite(z), z < q20, NA),
          beta = beta_spec, n_valid, 패널행수 = n_row)])
cat(sprintf("\n[해석] 전환 이후 flag 이 상시 발화면, 2026-07/08 의 z 결측(β 무뎌짐)은 **과발화를 우연히 취소**한 셈이다.\n"))
cat(sprintf("       즉 '결측 수리' 만으로는 부족하고 **문턱을 새 의미로 재산출**해야 한다(단위 정합).\n"))
fwrite(D, file.path(OUT, "semantic_break_panel.csv"))
