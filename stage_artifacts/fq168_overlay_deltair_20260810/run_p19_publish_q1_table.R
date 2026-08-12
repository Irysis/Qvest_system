## P19 — q1 실측표를 **추적 경로**에 발행 (결정 지점에서 조회 가능하게)
## ★오늘 배운 것 적용: ①`.csv` 는 전역 무시 → **`.json`** 으로 ②추적 여부를 발행 후 **확인**
##   ③미측정은 **NA** 로 남기고 0 으로 위장하지 않는다
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(CODE_ROOT)
SRC <- "stage_artifacts/fq168_overlay_deltair_20260810/p16_q1_vs_effect.csv"
DLT <- "stage_artifacts/fq168_overlay_deltair_20260810/p15_low_q1.csv"
stopifnot(file.exists(SRC))
Q <- fread(SRC)[, .(base, q1 = round(q1_all, 4), eff_ann = round(eff_all, 3))][order(q1)]
D <- if (file.exists(DLT)) fread(DLT)[, .(base, port_t_base = t_base, port_t_ovl = t_ovl, delta)] else NULL
if (!is.null(D)) Q <- merge(Q, D, by = "base", all.x = TRUE)
cat(sprintf("[표] base %d · q1 범위 %.3f~%.3f · PORT_t Δ 실측 %d건\n",
            nrow(Q), min(Q$q1), max(Q$q1), if (!is.null(D)) nrow(D) else 0L))
out <- "06_Registry/overlay_base_q1_share_20260810.json"
write_json(list(
  schema_version = "overlay_q1_v1",
  measured_at = "2026-08-10",
  treatment = "within_sector_reversal 하위25%(1개월·Sector Lv1) 제외형 오버레이",
  definition = "q1 = base 의 top-25 중 오버레이가 자를 분위(하위25%)의 월평균 비중. 균등 = 0.25",
  window = "266개월(PG2 정렬 구간) · 유동성 20일 평균 2e8 이상 · top-25 EW · 15bps",
  evidence = paste("P15 4점 실측(2-arm canonical_screen_bt, 커버리지 1.0):",
                   "FAM_L 0.148→Δ+0.736 · FAM_CR 0.150→+0.210 · FAM_S 0.195→+0.116 · PG2 0.308→-0.846.",
                   "경로: FQ-170 순열 4/4 · FQ-168 P14(PG2 19% 초과보유) · P15"),
  caveats = c(
    "자본 후보 아님 — 오버레이 후 최고 PORT_t +0.538. 약한 재료를 덜 나쁘게 만들 뿐",
    "문턱 0.25/0.28 은 균등 기준의 잠정값이며 최적화되지 않았다",
    "한 처리(reversal)에서만 확인 — 다른 오버레이 일반화는 미검(P20)",
    "PORT_t Δ 는 4 base 만 실측. 나머지는 q1 과 eff(보유 내부 차이)만 있다"),
  consumer = "02_Infrastructure/contracts/overlay_precheck.R :: overlay_q1_precheck() / overlay_q1_lookup()",
  bases = Q), out, pretty = TRUE, auto_unbox = TRUE, digits = NA)
back <- fromJSON(out)
cat(sprintf("발행: %s · 재읽기 base %d · ignored %s\n", out, nrow(back$bases),
            if (system2("git", c("check-ignore","-q", shQuote(out))) == 0L) "Y(문제)" else "N"))
## 계약이 실제로 조회하는지 확인 (배선 확인 — 오늘 '호출부 0' 계통 방지)
source("02_Infrastructure/contracts/overlay_precheck.R")
for (b in c("PG2", "FAM_L", "없는base")) {
  v <- overlay_q1_lookup(b, out)
  r <- if (is.na(v)) list(verdict="(미측정)", message="lookup NA") else overlay_q1_precheck(v, b)
  cat(sprintf("  %-10s q1 %-6s → %-8s %s\n", b, ifelse(is.na(v),"NA",sprintf("%.3f",v)),
              r$verdict, substr(r$message, 1, 60)))
}
