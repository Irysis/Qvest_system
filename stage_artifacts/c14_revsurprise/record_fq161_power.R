suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"
q <- fromJSON(p, simplifyVector = FALSE)
E <- q$entries
i <- which(sapply(E, function(x) isTRUE(identical(x$id, "FQ-161"))))[1]
cat("[161] 인덱스:", i, "\n")
if (is.na(i)) { cat("[161] 미발견 — 중단\n"); quit(status = 0) }

E[[i]]$power_precheck_20260808 <- list(
  by = "Q-Lead main session (read-only, required_effect_size.R 경유)",
  why = paste(
    "next_action 이 지정한 소비면 ②유니버스 필터는 WT-D20260808_001 이 D03/Q01 로 이미 시험했고",
    "전 arm INCONCLUSIVE_UNDERPOWERED 로 끝났다(필요 연 +4.47%/+3.02% vs 관측 0.79%/0.81%).",
    "같은 실패를 M26 에서 반복하지 않도록 착수 자격 바를 미리 계산해 고정한다."),
  required_effect_annual = list(
    full_basket_pair_sd0.0394 = "n=283 -> 7.03% / n=318 -> 6.63%",
    paired_filter_sd0.017     = "n=283 -> 3.03% / n=318 -> 2.86%  (낙관 — WT-001 실측 diff sd 하한)",
    paired_filter_sd0.026     = "n=283 -> 4.64% / n=318 -> 4.37%  (보수 — WT-001 실측 diff sd 상한)"),
  admission_bar = paste(
    "★필터면 착수 자격 = 관측 가능 효과가 연 2.86~4.64% 를 넘을 개연이 있을 때만.",
    "그 미만이면 착수 전 폐기하고 형태를 바꾼다(전표본 횡단면 회귀 등).",
    "비교 기준선 = MAX5 선례(WT-014) 필터 ΔIR +0.1692 · PORT_t 2.879->3.620 — 이 저장소에서 필터면이 성공한 유일 사례."),
  caveat = paste(
    "①paired diff sd 는 M26 고유값이 아니라 WT-001 의 D03/Q01 실측을 대입한 참고치다.",
    "착수 시 M26 자체 diff sd 로 재계산할 것.",
    "②required_effect() 반환에서 design 필드가 NA 로 에코됐다(effective_n = n 이므로 분할 축소는 적용 안 됨 — 계산은 정상, 에코만 결손).",
    "③이 계산은 t=2.0 재료 자격 기준이며 자본 게이트(HARD PORT_t 2.95)와 다른 문턱이다."),
  evidence = "stage_artifacts/c14_revsurprise/m26_filter_power.R"
)
E[[i]]$next_action <- paste(
  E[[i]]$next_action,
  "★착수 전 의무(2026-08-08 추가): power_precheck_20260808 의 바(연 2.86~4.64%)를 M26 자체 diff sd 로 재계산해 대조하고,",
  "미달이면 필터 형태를 착수 전 폐기한다. WT-D20260808_001 이 같은 소비면에서 검정력 미달로 유보된 직접 교훈.")

q$entries <- E
write(toJSON(q, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
cat("[161] 검정력 바 기록 완료\n")
