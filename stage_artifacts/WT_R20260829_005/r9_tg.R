suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
R3<-readRDS(file.path(OUT,"risk_r3.rds")); R5<-readRDS(file.path(OUT,"risk_r5.rds"))
A <-readRDS(file.path(OUT,"risk_r7_adversarial.rds"))
deg <- R3$deg; bias <- R3$bias
gv <- function(nm, f) { x <- deg[[nm]]; f(x) }
bs <- function(nm) { b <- bias[method==nm]; if (nrow(b)) sprintf("%.2f", b$bias_stat) else "-" }
tab <- data.frame(
  Estimator = c("Sample","LedoitWolf","LW-NLS","GerberRMT","Factor*"),
  `cond|keep|bias` = c("4173|1.00|1.38", "1|0.00|3.04", "928|0.93|1.39",
                       "10081|1.63|1.07", "472|0.98|1.38"),
  check.names = FALSE, stringsAsFactors = FALSE)

res <- tg_agent_brief(
  agent = "Risk",
  title = "WT-R20260829_005 RISK_DONE — Sigma factor BwB+D cond 472",
  as_of = "2026-07-31",
  sections = list(
    list(emoji="📌", heading="현재 리서치 상황", type="bullet",
         items=c("단계: 강화 프로세스 심층 QEPM 체인의 risk 구간",
                 "대상: JT1993 강화 5/20 — AMP2013_valmom_rankavg_top25",
                 "직전 판정: alpha 가 AMP2013 음(-)상관 전제를 KR 구성 아티팩트로 판정",
                 "체인 완주 의무(도훈 2026-08-29)로 음성 위에서도 진행",
                 "위치: worktask/WT-R20260829_005/risk_package.json")),
    list(emoji="🔬", heading="공분산 추정기 비교 (추정품질 축만)", type="table",
         df=tab, max_col_width=16L,
         notes=c("Factor* = 채택분 (Sigma = B Omega B' + D). cond=조건수, keep=상관구조 보존율, bias=walk-forward bias(이상 1.0)",
                 "LedoitWolf 는 p<n(330<756) 인데도 축퇴 — Sigma -> mu*I, 상관구조 전멸. 기존 p>n 가드 미발화",
                 "Gerber 는 bias 1위이나 상관을 63% 증폭 + 조건수 최악 -> 기각")),
    list(emoji="💡", heading="핵심 실측", type="bullet",
         items=c("기준바스켓 예상 변동성 34.2%/yr (진단용 균등 top-25)",
                 "분산 귀속: 시장 74.9% · 섹터 5.9% · 개별위험 5.3%",
                 "무신호 대조: 무작위 25종 균등 = 시장 87.4% (본 후보가 더 낮다)",
                 "MDD -53.03% = 베타 낙폭. GFC 전략 -42.0% vs 벤치 -36.5%",
                 "cap-tier OTHER 92.7%는 소형주 베팅 아님 (유니버스 기준선 91.2%)",
                 "월별 GPD shape 0.170 · Hill alpha 3.14 (벤치 1.95)",
                 "일별 바스켓 Hill alpha 1.83 — 월 집계가 꼬리를 평활한다")),
    list(emoji="🛡️", heading="하류 소비 주의", type="bullet",
         items=c("Sigma 단위 = 월간 (연율화 x12). alpha 1M 지평과 정합",
                 "수준보정계수 1.384 별도 발행 (Sigma 에 미적용)",
                 "적용 대상 = 절대 위험목표/CVaR 예산. 비중 산출에는 불필요",
                 "추적오차 = (w-w_b)Sigma(w-w_b), w_b = K200 시가총액 가중")),
    list(emoji="🚨", heading="위험 플래그", type="bullet",
         items=c("시장 지배도: 발화 — 74.9% (임계 40%)",
                 "  롱온리 바스켓의 형태이지 신호 탓 아님 (무신호 대조 확인)",
                 "조건수 · 크라우딩 · 스트레스 · 팩터상관: 모두 미발화",
                 "다만 조건수 통과는 형식적임을 패키지에 명기했다")),
    list(emoji="🧪", heading="자기적대검증 (수용 2 · 부분 2 · 반박 2)", type="bullet",
         items=c("수용: 레짐 상관 결론 철회 — 중첩창이 관측수를 24배 부풀림",
                 "  에피소드 단위 재검 p=0.585 -> 미결(검정력 부족)",
                 "수용: 개별위험 바닥 상향이 소비량 불변 (+0.01%)",
                 "반론 1: 인라인 Ledoit-Wolf 가 p<n 에서도 축퇴 (가드 미발화)",
                 "반론 2: 베타 창의존 — 일별 0.700 vs 전기간 월별 0.869",
                 "인프라: fExtremes 미설치 -> evir 로 국소 재구현")),
    list(emoji="⚠️", heading="역할 경계", type="text",
         body="alpha_vector 무수정(read-only) · 비중 벡터 미산출 · 등급 미선언 · 오버레이 미적용.")
  ),
  footer = "➡️ Next: Optimizer Agent (alpha_package + risk_package 소비)"
)
print(res)
