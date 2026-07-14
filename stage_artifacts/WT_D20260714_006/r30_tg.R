setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")
WT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_D20260714_006"
tg_agent_brief(
  agent = "Alpha",
  title = "R30 (FQ-045) 밸류 잔여 소비면 — cap-w 국소화 벽 최초 관통(스크리닝), 단 자본 미검",
  sections = list(
    list(type="summary",
      body="밸류를 중소형(non-mega)에만 태우니 cap-w 스크리닝 관문을 처음 통과(paired 2.378). 단 최근 감쇠로 자본은 미검. book 무변경."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "문제: R29에서 밸류를 모든 종목에 태우니 대형주 벤치(cap-w) 기준 기여가 약했다(paired 1.24 < 2.0 문턱)",
        "가설: 밸류 초과수익은 중소형에 몰려있다(cap-tier 국소화) → 대형주엔 밸류 안 태우고 중소형만 태우면?",
        "결과 B2: 그렇게 하니 paired 2.38로 문턱 통과. 밸류를 무작위로 섞으면(placebo) 사라짐(진짜 신호)",
        "단서: 통과는 과거(2017년 이전)가 견인, 최근 2년은 기여 0 근처 → '스크리닝 통과'지 '자본 승인'은 아님",
        "리스크: 밸류-품질 스프레드가 백분위 0.175로 압축(작년 최대치서 되돌림) = 늦은-사이클, 앞으로 기대 낮춰야")),
    list(type="kv", emoji="🅱️", heading="B갈래 — 중소형 조건부 밸류(대형주가중 권위)",
      kv=list(
        "B2 중소형 페어드 t값"="2.378 (문턱 2.0 통과)",
        "B2 정보비율 증분"="+0.232 (문턱 0.05 통과) → 동시게이트 통과",
        "R29 전종목(비교)"="1.243 미달",
        "B1 중형만(비교)"="1.072 미달 (소형 포함이 관건)",
        "위약검정 / 지연1 t값"="p=0.000 / 2.473 (실신호·미래참조 아님)",
        "홀드아웃 증분 / 2017년후 t"="-0.022 / 1.73 (최근 감쇠 — 자본 미검)")),
    list(type="kv", emoji="🅰️", heading="A갈래 — 동일가중 배포성(페이퍼트래킹 3호 실사)",
      kv=list(
        "순수밸류 지속성(표본외 유지율)"="0.659 (밴드, 감쇠 미검출·회전율 낮음)",
        "기존 P-pure와 겹침"="활성상관 0.50 / 보유중첩 19.5% (V02_EP 0.34보다 큼)",
        "판정"="독립 페이퍼트래킹 3호 부적격(중복) — 상위 기대가치는 B갈래(book 한계기여)")),
    list(type="bullet", emoji="🚩", heading="Challenge flags (self-adversarial)",
      items=c(
        "B2 관통은 IS/pre-2017 견인, 홀드아웃 기여 -0.022 → screening-tier(자본 NO-GO)",
        "밸류-스프레드 0.175 압축 = 늦은-사이클, 홀드아웃 양성이 소진 되돌림 후행일 가능성",
        "B2 기여가 중소형 소가중(wMID 0.06) tail 증폭 — 구현성 미검증",
        "metric_type=cap-w 스크리닝 (forge graduation HARD 3종 미검증)")),
    list(type="bullet", emoji="➡️", heading="다음 단계 (도훈 결정 재료)",
      items=c(
        "P1=FQ-046: B2를 forge/judge 자본 게이트(t 2.95·oos 0.7·calmar 0.64)로 판정 (도훈 confirm)",
        "P2: tier 경계 민감도 + 소형 유동성/수용력 정제 (IS-only)",
        "P3: 최근 감쇠가 일시적인지 스프레드 소진인지 판별 + 조기경보 tripwire",
        "book·05_Production 무변경. L-AR-20260714_191441 / WT-D20260714_006"))
  ),
  charts = c(file.path(WT,"charts/r30_panel.png"))
)
cat("TG_DONE\n")
