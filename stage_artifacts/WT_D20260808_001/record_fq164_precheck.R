suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector = FALSE)
E <- q$entries
i <- which(sapply(E, function(x) isTRUE(identical(x$id, "FQ-164"))))[1]
cat("[164] 인덱스:", i, "\n")
if (is.na(i)) { cat("[164] 미발견 — 중단\n"); quit(status = 0) }

E[[i]]$precheck_20260809 <- list(
  by = "Q-Lead main session (read-only, required_effect_size.R 경유). 착수 전 사전 확인.",
  cost_channel_ceiling = paste(
    "★회전율을 건드려 **비용 채널**에서 얻을 수 있는 최대치 = 총 비용 = 회전율 11.7422/yr x 15bps =",
    "**연 1.76%**. WT-D20260809_001 이 회계 항등으로 검증(실측 alpha 차이 1.76%p 일치).",
    "이 값은 **신호 손실 0** 이라는 비현실적 가정 하의 상한이다."),
  detection_bar = paste(
    "같은 프레임(n=283, t=2.0, paired) 검출 필요치: sd 0.010 -> 1.78% / 0.015 -> 2.67% /",
    "0.020 -> 3.57% / 0.026 -> 4.64%. 승계 실측(M26 staleness 11셀) 필요치는 연 3.01~5.55%,",
    "관측 효과는 -2.70~+2.00%(최대 |t| 0.858)."),
  verdict = paste(
    "**비용 절감만으로는 t=2.0 도달이 원리적으로 불가하다** — 가장 낙관적 sd(0.010)에서도",
    "필요 1.78% > 상한 1.76%. 간발이나 넘지 못한다."),
  IMPORTANT_scope_limit = paste(
    "★이 상한은 **비용 채널에만** 적용된다. 부분-리밸은 회전율을 줄이는 동시에 **보유 종목 구성도 바꾸므로**",
    "알파 채널 효과가 별도로 있고 그것은 비용으로 상한이 잡히지 않는다(부호도 양방향 가능).",
    "따라서 '설계가 무엇이든 불가' 는 과장이며, 정확히는 '비용 절감 단독으로는 불가' 다.",
    "★자기 정정: 최초 판정문이 채널 하나의 상한을 전체 상한으로 서술했다 — 라벨을 실체로 읽는 계통."),
  admission_condition = c(
    "①착수 자격 = 알파 채널 효과가 실재한다는 사전 근거를 제시할 것. 비용 절감만 겨냥한 설계는 착수 전 폐기.",
    "②paired diff sd 를 arm 자신의 계열에서 실측해 필요치를 재산출할 것. sd <= 0.0099 여야 비용 채널만으로도 경계에 닿는다.",
    "③verdict_with_power 반환의 implied_t_threshold 를 확인할 것 — 문턱 근방이면 바가 t 검정의 재진술이라 정보가 없다(2026-08-09 개정판).",
    "④M26 staleness 축의 1:1 교환(비용 절감 1.20%p vs 알파 손실 1.17%p)은 **점추정 우연일 수 있다**(±3%p 도 구별 못하는 검정력) — 기전으로 인용하지 말 것."),
  evidence = "stage_artifacts/WT_D20260808_001/fq164_precheck.R"
)
E[[i]]$next_action <- paste(
  if (is.null(E[[i]]$next_action)) "" else E[[i]]$next_action,
  "★착수 전 의무(2026-08-09 추가): precheck_20260809 의 admission_condition 4항을 먼저 통과할 것.",
  "특히 ①(알파 채널 사전 근거) 미충족 시 착수 금지 — 비용 채널 단독은 상한 1.76% < 필요 1.78%+ 로 검출 불가다.")

q$entries <- E
write(toJSON(q, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
cat("[164] 사전 확인 기록 완료 (폐기 아님 — 착수 조건 부과)\n")
