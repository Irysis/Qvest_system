# Telegram brief — alpha-search 큐 소비 결과 (ReSGA 2606.04576)
suppressWarnings(suppressMessages(library(data.table)))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

sections <- list(
  list(type = "bullet", emoji = "📥", heading = "큐 소비",
       items = c(
         "큐 testable 미소비 1편: ReSGA 2606.04576 (size x tail-risk 상호작용)",
         "이번 런 실행 1편, 2방향(POS/NEG) 재검증 (논문 부호가 시장의존적이라 양방향)",
         "batch_434 skip 없음: Eq.(11) 충실 구현으로 라벨과 실행 신호 일치"
       )),
  list(type = "bullet", emoji = "🔬", heading = "ReSGA 2606.04576 실행 결과",
       items = c(
         "신호식: alpha = (logCap 단면demean) 곱하기 (1 minus exp(ES_hat)), ES_hat=직전252일 하위5퍼 평균",
         "POS 대형주x고꼬리 롱: 등급 B 점수 43 초과 -6.0퍼p, 실측 essence 등급 F",
         "POS 실측 포트검정 PORT_t(NW3) -2.81, 정보비율 -0.62 로 벤치 유의 미달",
         "NEG 소형주x고꼬리 롱: 등급 F 점수 6 초과 +1.1퍼p, 최대낙폭 74.6퍼 정보비율 0.05 screening 탈락"
       )),
  list(type = "bullet", emoji = "⚠️", heading = "검증 게이트 5층 fail-closed",
       items = c(
         "PIT 통과, 계약 통과, 견고성 실패, 충실성 실패(독립검증 미실행 moot)",
         "최종 판정 QUARANTINE, 실패층 robustness 와 fidelity",
         "결론: 두 방향 모두 KR long-only 알파 부재, 논문의 미국 대 아시아 부호역전 KR 재현",
         "조치: 모드 L-code 2건 회수(QUARANTINE 적립금지), 음성지식 quarantine 보존, 자본 미편입"
       ))
)

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "alpha-search 큐 가동 (팩터 to 모드)",
  sections = sections,
  relaxed = TRUE,
  smart_break = FALSE,
  force = TRUE,
  dry_run = FALSE
)
cat("TG ok=", isTRUE(res$ok), " bytes=", res$bytes %||% NA, "\n")
