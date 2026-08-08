## FQ-161 next_action(②유니버스 필터) 착수 전 검정력 사전 계산
## 목적: WT-D20260808_001 이 필터면에서 INCONCLUSIVE_UNDERPOWERED 로 끝난 실패를 M26 에서 반복하지 않기.
## read-only 진단. 자본 주장 없음. metric_type = canonical_screen_diag
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[pow] ",fmt,"\n"),...))

src <- "02_Infrastructure/contracts/required_effect_size.R"
say("계약 함수: %s (존재 %s)", src, file.exists(src))
if (!file.exists(src)) { say("★부재 — 중단"); quit(status=0) }
source(src)

## ★입력 실측 (가정 금지 — 오늘 규약)
say("--- 입력 실측 ---")
say("  M26 factor_db 산출월      : 318 / 442 (FQ-161 data_gate 기재)")
say("  증분 회귀 유효월(FMB)     : 283 (FQ-161 hypothesis 기재)")
say("  WT-001 필터면 실패 기준선 : 필요 연 D03 +4.47%% / Q01 +3.02%% vs 관측 0.79%% / 0.81%%")

n_vals <- c(283L, 318L)
say("--- required_effect: 전표본(full) 프레임 ---")
for (n in n_vals) {
  r <- tryCatch(required_effect(n = n, design = "full"), error = function(e) NULL)
  if (is.null(r)) { say("  n=%d : 호출 실패", n); next }
  v <- if (is.list(r)) unlist(r) else r
  say("  n=%3d : %s", n, paste(sprintf("%s=%.4f", names(v), as.numeric(v)), collapse="  "))
}

## 필터면은 paired(동일 base 대비 차이)라 sd 가 낮다 — WT-001 실측 sd 를 대입해 비교
say("--- paired 필터 프레임 (WT-001 실측 diff sd 대입) ---")
for (sd_m in c(0.017, 0.026)) {          # WT-001 보고 paired diff sd 범위
  for (n in n_vals) {
    r <- tryCatch(required_effect(n = n, sd_monthly = sd_m, design = "full"),
                  error = function(e) NULL)
    if (is.null(r)) next
    v <- if (is.list(r)) unlist(r) else r
    say("  sd=%.3f n=%3d : %s", sd_m, n, paste(sprintf("%s=%.4f", names(v), as.numeric(v)), collapse="  "))
  }
}

say("--- 판정 규약 (착수 전 고정) ---")
say("  관측 가능 효과가 위 필요치 미만이면 그 설계는 착수 전 폐기하고 형태를 바꾼다.")
say("  MAX5 선례 실측 = 필터 ΔIR +0.1692 · PORT_t 2.879->3.620 (WT-014).")
say("  M26 필터가 그 정도 크기를 낼 수 있는지가 착수 자격 판정 기준이다.")
