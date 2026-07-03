# Qvest 아키텍처 전면 감사 — 알파 발굴 시스템 관점 (2026-07-03)

**방법**: 10개 서브시스템 병렬 감사 (71 agents, 1,107 tool calls) → P0/P1 발견 60건 전수 적대검증 (반증 0건) → 종합 판정.
**감사 원칙**: 모든 주장 file:line 증거 의무, "룰이 주장하는 것" vs "코드가 실제 하는 것" 괴리 최우선 탐지.

## 종합: 4.5/10

> Qvest는 현재 '알파를 찾아내는 기계'가 아니라 '가짜 알파를 정직하게 기각하는 기계'다 — 기각 근육(측정·라벨·수동 거버넌스)은 진짜지만 자동 강제 계층의 대부분은 침묵 사망 상태이고, 새 알파를 조준·학습·공급하는 신경계는 문서로만 존재한다.

## 차원별 채점

| 차원 | 점수 | 요지 |
|---|---|---|
| 측정 무결성 | 6.5 | 계산 코어(PORT_t NW lag-3·oos v2·holdout falsification·fabrication 탐지)는 문서-코드 1:1로 이 시스템 최강 부위 — 단 metric_type/contract_pass/hash가 전량 자기신고라 '정직한 runner에게만' 완벽 (MC-01~06) |
| 강제(enforcement) 실효성 | 2.5 | python3 스텁으로 하드블록 훅 42/57 fail-open 실측(05_Production 보호·graduation 게이트 포함), 역할경계·lockbox 훅은 marker writer 부재로 한 번도 발화한 적 없음, HARD 3종 중 훅 배선은 PORT_t 1종뿐 — '하네스가 막는다'는 헌법 주장 대부분이 현재 paper rule (HOOK-P0-1, AGT-01, MC-01) |
| 가설 생성력 | 6 | 발굴 엔진 자체(fe_*.R 1개+1콜 전자동, 논문 파이프 실가동, 선언형 팩터 온보딩)는 우수하나 연료가 고갈 — 논문풀 95% 소진·라우터 alpha 수율 0/38·가설 dedup 인덱스 부재·유일한 신규 원천(DART insider)은 백필 시작조차 안 됨 (AS-03, AS-09, SC-05) |
| 발굴→자본 전달 | 4 | 정직 라벨층(quarantine 450건·allowlist·FR registry 차단)은 실가동하나, graduation 훅 사문 + ΔIR 게이트는 신세대 모듈에 영구 DEFER 기계 + screen_route 3개 중 2개 소비자 0 + FR 루프 20일 정지 — 실제 자본 전달은 전부 수동 (CAP-P0-1/2, CAP-P1-1/3/5) |
| 학습 루프 | 3 | L-code 적립 596건·주간 파이프라인은 돌지만 승격 깔때기가 데이터 모델상 구조적 0%(4주 0건, RAMP는 승격 시 hard crash), 강제·주입 훅 사망 — 엔진화된 학습은 공회전이고 실질 학습은 전부 MEMORY.md 수동 관리 (GOV-01/06, AXM-01/02) |
| 데이터 신뢰성 | 4.5 | 사고→가드 전환 실적(IKS200 이중가드, temp-rename)은 진짜이나 감시가 신선도 단일축이라 BM_Ret +581% 손상이 7월 factor DB에 이미 반영(59팩터 결손, 라이브 북 M08 포함)되는 걸 아무 가드도 못 잡음 + vintage pinning 미코드화 (DATA-P0-1, DATA-P1-1/3) |
| 전략적 정합성 | 4.5 | 가짜를 죽이는 규율(FaithTrend 하루 만에 적발·settled-negative 원장화)은 탁월하나 조준 계층 부재 — SR 2.5 vs 실증 천장 1.1의 도달 경로 미정의, stale gap vector가 실증 사망 방향(core_alpha)을 지시, 탐색 어젠다가 세션 메모리에만 존재 (SC-01/05/06) |

## 영역별 점수

| 영역 | 점수 |
|---|---|
| constitution | 6 |
| measurement | 6.5 |
| hooks | 3.5 |
| agents | 5 |
| generation | 6.5 |
| consumption | 4.5 |
| knowledge | 3.5 |
| data | 5.5 |
| hygiene | 3.5 |
| strategy | 4.5 |

## 실증된 강점 (Top 5)

1. 측정 계산 코어의 문서-코드 1:1 정합 — PORT_t NW lag-3 / oos_retention v2 3분할 / holdout 사전등록 falsification / audit의 frequency-fabrication 탐지가 전부 함수 단위로 실재하며, 16-cycle proxy 사건(FLOW 3.55→2.35)의 재발 방지가 '계산 제공' 레벨에서는 완결됨
2. 정직 라벨링·격리 계층 실가동 — module_quarantine 450건 실격리, build_module_performance allowlist 강제, factor_rotation_registry의 proxy 등재 하드 차단, live_track holdout 사전등록(overwrite 거부 포함)이 코드로 집행됨
3. 자기교정의 실증 이력 — look-ahead 오염 FaithTrend를 자본 편입 하루 만에 clean 재심으로 적발·제거하고 전체 감사이력 보존, IKS200 벤치 사고 후 이중 sanity 가드, 훅 fail-open 결함의 fail-closed 수리(v8.1.2) 등 사고가 실제로 가드로 전환되는 문화
4. 실패의 체계적 원장화 — settled-negative ~15건(DPL·예측 ONSET·max-cash·시장타이밍 4중 부정·KNS 재시도 금지)이 재현 증거와 함께 기록되고 §6 '확립된 전략 진실'로 헌법화 — 수동(MEMORY.md)이지만 실제로 작동하는 학습이며 자기 천장을 정직하게 공식화한 드문 사례
5. 발굴 엔진의 낮은 한계비용 — 신규 횡단면 가설이 fe_*.R 1개 + run_alpha_search() 1콜로 PIT검사→계약 bt_result→등급→권위재측정→FR승격→L-code까지 전자동, 논문 유입 파이프(라우터+dedup+큐)가 스케줄러에서 실가동 중

## 확정 약점 (근본원인 클러스터, 심각도순)

### 1. 강제 계층의 침묵 사망 — AX-002('하네스 내 성과만 유효')를 하네스 자신이 위반

python3 = Windows Store 스텁으로 하드블록 훅 42/57이 fail-open(05_Production 보호와 자본 졸업 게이트에 should-block payload를 넣어도 '{}' allow — 라이브 재현), 역할경계·lockbox 훅은 production marker writer가 존재한 적이 없어 발화 이력 0, HARD 3종 중 oos_retention·calmar는 훅/config에 키 자체가 없고, Bash/Rscript 경유 쓰기는 전 게이트 자연 우회. 지금까지 사고를 막아온 건 훅이 아니라 R 계약 + 도훈 수동 confirm + 에이전트 정직성이며, CLAUDE.md v8.2가 'python3 환경 FAIL'을 기록한 채 3일+ 방치한 것이 가장 나쁜 신호.

근거 발견: HOOK-P0-1, CAP-P0-1, AXM-02, AGT-01, HOOK-P0-2, MC-01, HOOK-P0-3, HOOK-P1-1, HOOK-P1-2, MC-07

### 2. 데이터 값-무결성 무감시 + 라이브 손상 현실화

RAWDATA BM_Ret +581% 손상이 canonical 캐시에 살아있고 7월 factor DB 빌드에 이미 반영되어 59개 팩터 결손 — 라이브 북 {Q07/M08/Q25}의 M08 포함. 감시는 신선도(mtime/max Date) 단일축이라 손상 캐시가 'FRESH' 판정을 받고, 역대 값-손상 발각은 전부 인간(도훈/리서치)이었지 시스템이 아님. vintage pinning도 07-02 tipping 사고 후 수동 파일복사 수준으로만 존재.

근거 발견: DATA-P0-1, DATA-P1-1, DATA-P1-2, DATA-P1-3

### 3. 자가발전 엔진 공회전 — 승격 깔때기 구조적 0%

v8.x 정체성인 '각 모드 자가발전'이 4주간 승격 0건: Falsification 축은 채우는 생산자가 전무(전 코퍼스 0건), External 축은 oos_months 하드코딩 None으로 영구 불충족 — 데이터 모델상 도달 불가. RAMP는 .MODE_PREFIX 누락으로 승격 시도 시 hard crash 확정. axiom 강제·주입 훅도 사망 상태라 594건 L-code가 매주 클러스터링→전원 탈락을 반복하는 트레드밀이며, 실질 학습은 전부 Q-Lead 세션 메모리 품질에 의존.

근거 발견: GOV-01, AXM-01, GOV-06, AXM-06, AXM-03, AXM-04, SC-02

### 4. 버전관리 3주 붕괴 + 게이트 코드 회귀 테스트 0건

auto-commit이 973회 연속 abort하며 06-12 이후 커밋 0 — 게이트 2계층·v8.2·비용모델 v2.4 등 헌법·계약 변경 전체가 무보호(OneDrive 롤백 1회면 유실되는 단일 장애점, bisect 불가). 동시에 essence_score/canonical_screen_bt/register_module 등 Grade 권위 코드에 고정 픽스처 테스트가 0건이라 반복 수정 중인 게이트 로직의 회귀를 잡을 수단이 없음.

근거 발견: HYG-01, HYG-05, HYG-06, HYG-02

### 5. 발굴→자본 전달 배관 단절 — 공급 0에 소비층 과잉투자

3개월간 graduation 통과 0/191인데 아키텍처 투자는 배합 계층(RCMA·FR·RAMP Gate 0~11)에 집중. codified ΔIR 게이트는 alpha_search 262건 후보에게 구조적 작동불능(mailbox 3-package 요구 → 영구 DEFER) + 경로 버그, screen_route 3개 중 2개(OVERLAY_CANDIDATE·DPL_FEATURE)는 라벨만 생산되고 소비자 0, FR 소비 루프는 20일 정지 — 2-tier 게이트 개혁의 알파 회수 효과가 실질 0.

근거 발견: CAP-P0-2, CAP-P1-1, CAP-P1-3, CAP-P1-5, SC-04, CAP-P1-2

### 6. v8.2 마이그레이션 미완 sweep + 문서-현실 드리프트 만연

FR/RAMP 오케스트레이터와 workflow 2종이 삭제된 skill·폐지된 Codex 절차를 '의무'로 지시, promote_global/axiom-engine.md/role_permissions에 stale codex 잔존, judge에 폐기된 DSR 휴리스틱, optimizer에 폐지된 20종 기준, pit-validation.md는 존재하지 않는 차단 훅을 '자동 차단'으로 주장. 개별로는 P2지만 총체적으로 '문서가 주장하는 시스템'과 '실제 시스템'의 신뢰 격차를 만들며 — 이 드리프트가 바로 python3 사고가 3일간 방치된 배경.

근거 발견: GOV-02, GOV-03, GOV-04, GOV-05, AGT-02, AGT-03, AGT-04, AGT-06, DATA-P0-2, MC-05

### 7. 전략 조준 계층 부재 — 유일한 신규 원천은 좌초, 죽은 방향은 조향 중

'무엇을 통과시킬지'는 3중 4중인데 '무엇을 시도할지'는 계층 자체가 없음. stale gap vector(06-13, n_strategies=0)가 실증 사망한 core_alpha standalone을 1차 조향 입력으로 지시하고, 시스템 스스로 최우선 지목한 DART insider는 mandate 3일 후에도 백필 체크포인트 0파일, 가설 dedup·어젠다 기계화 부재로 탐색 예산 배분이 세션 연속성에 종속.

근거 발견: SC-01, SC-05, SC-06, AS-03, AS-09

## 확정 발견 전체 (60건, 적대검증 통과)

| ID | 심각도 | 확신도 | 제목 |
|---|---|---|---|
| constitution/GOV-01 | P2 | high | 자가발전 axiom 엔진 승격 산출 0건 — 헌법 핵심 선언('각 모드 자가발전')이 4주째 실가동 안 됨 |
| constitution/GOV-02 | P2 | high | FR/RAMP 오케스트레이터가 삭제된 skill(qvest-codex-round)과 폐지된 Codex Round를 '의무'로 명시 — 소비 계층의 적대검증이 공백 |
| constitution/GOV-03 | P2 | high | 활성 workflow 2종이 spawn prompt에 폐지된 'Codex Round 5단계 의무'를 주입 — dossier(자본 직전) 경로 포함 |
| constitution/GOV-04 | P2 | high | promote_global.R의 AX-008 verification 소스에 여전히 codex — global 승격이 코드 수준에서 사실상 2/2 요구로 조여짐 |
| constitution/GOV-05 | P2 | high | Python 자체합성 탐지 강제 공백 — 약속된 훅 .py 확장 미이행 상태에서 임시 백스톱(Codex Round)만 제거됨 |
| constitution/GOV-06 | P1 | high | axiom 엔진 SOT가 3-mode만 정의 — RAMP(4번째 모드) L-code의 승격 경로가 규정 부재 |
| measurement/MC-01 | P1 | high | HARD 3종 중 oos_retention·calmar가 block 계층(hook+config)에 완전 부재 — 문서상 'HARD (block)'는 PORT_t 1종만 실제 차단 |
| measurement/MC-02 | P1 | high | audit 미실행 bt_result(integrity=PENDING)가 registry 등재 가능 + 등재 hook은 Bash/Rscript 쓰기에 무풍 — 미감사 수치의 공식 계보 오염 경로 존재 |
| measurement/MC-03 | P1 | high | metric_type='backtested' 라벨이 provenance 비검증 자동 스탬프 — 라벨은 강제가 아니라 '어떤 함수를 불렀나'의 부산물 |
| measurement/MC-04 | P2 | high | DSR sweep 게이트 2중 구멍: DSR 미보고 시 sweep이어도 skip + chain 자격요건(IS-only 선택 등) 기계검증 전무·라벨 하드코딩 |
| measurement/MC-05 | P2 | high | cost_model_version이 bt_result manifest·backtest_registry에 미기록 — v2.3 flat/v2.4 delta 혼용 감별이 계약 산출물에서 불가능 |
| measurement/MC-06 | P1 | high | register_module 계약 floor가 전량 자기신고 — contract_pass/frozen/backtested/hash 어느 것도 실물 crosscheck 없음 |
| hooks/HOOK-P0-1 | P0 | high | python3 = Store 스텁 → 하드블록 훅 42/57 전면 fail-open (실측 입증) |
| hooks/HOOK-P0-2 | P1 | high | 역할경계·lockbox 훅 = 생산 경로에 marker writer 부재 + 미수리 ps 버그 → 상시 allow (python3와 무관) |
| hooks/HOOK-P0-3 | P1 | high | graduation HARD 3종 중 oos_retention·calmar가 훅 계층에 미배선 |
| hooks/HOOK-P1-1 | P2 | high | 구조적 사각: 훅은 Claude의 Write/Edit 도구만 감시 — R/Python(Bash) 경유 산출물 쓰기는 전 게이트 자연 우회 |
| hooks/HOOK-P1-2 | P2 | high | axiom_enforcement_hook = 사실상 dead code: 동적 엔진 0건 매칭 + AX-001 블록은 legacy 파일명만 |
| hooks/HOOK-P1-3 | P1 | high | python-policy §5의 '.py 확장' 미이행 — Python 리서치 산출물은 자체합성·회피표현 무감시 |
| hooks/HOOK-P1-4 | P2 | high | 라우터 전환 3주+ 방치 — Write당 ~34 프로세스 spawn 부하 + 'selftest PASS'의 오도 |
| agents/AGT-01 | P1 | high | 역할 경계 + lockbox 오염 차단 훅이 상시 no-op — agent 식별 marker의 production writer가 존재하지 않음 |
| agents/AGT-02 | P2 | high | v8.2 Codex 제거로 final-write 게이트가 passthrough化 — Self-Adversarial 대체 강제는 wt_advance 시 파일 존재 체크뿐 |
| agents/AGT-03 | P2 | high | dispatch-orchestrator / ramp-orchestrator가 삭제된 skill(qvest-codex-round)과 폐지된 Codex Critic Round를 의무로 참조 |
| agents/AGT-04 | P2 | high | judge 정의에 폐기된 DSR 휴리스틱(n_trials>1=sweep) 잔존 — 판정자와 게이트 SOT 불일치 |
| agents/AGT-05 | P2 | high | sequence/lockbox 훅의 WT ID regex가 WT-S/WT-H 타입을 누락 — 4종 wt_type 중 2종이 순서 강제·감사 밖 |
| agents/AGT-06 | P2 | high | optimizer-research 정의의 Hard Constraint 자기검열 기준이 폐지된 max_names 20 — 헌법 25와 불일치 |
| agents/AGT-07 | P2 | high | "_shared_prefix 모든 agent autoload" 주장은 허구 — 실제 자동 주입은 75자 절단 axiom 요약뿐, 본문은 2-hop 자발 Read 의존 + 6개 파일 verbatim 중복 |
| generation/AS-01 | P1 | high | module_catalog에 batch_434 codegen 오염 엔트리 잔존 — 발굴 이력 레코드의 가설라벨≠실행신호 |
| generation/AS-02 | P1 | high | 외부 파이프라인 생성 팩터(fe_ml류)의 PIT 강제 공백 — warn-only인데 FR-eligible 자동 승격 경로는 열려 있음 |
| generation/AS-03 | P2 | high | 가설 수준 중복실험 방지 인덱스 부재 — 687회 실험의 '이미 시도됨' 판정이 LLM 메모리 의존 |
| generation/AS-04 | P2 | high | 제1원칙(논문 완전 복제)과 run_alpha_search 표현공간의 구조 충돌 — 충실 복제마다 1회용 오케스트레이터 fork |
| consumption/CAP-P0-1 | P1 | high | graduation HARD 게이트 훅이 현 머신에서 완전 사문 (fail-open 라이브 재현) |
| consumption/CAP-P0-2 | P1 | high | book-marginal ΔIR≥0.05 admission 코드가 proxy 기반 + 구조적 도달불가 + 경로 버그 — 실제 admit은 전부 수동 우회 |
| consumption/CAP-P1-1 | P2 | high | screen_route 3개 중 2개(OVERLAY_CANDIDATE·DPL_FEATURE)는 소비자 코드 0건 — 라벨만 붙고 방치 |
| consumption/CAP-P1-2 | P1 | high | frozen/hash/contract_pass floor가 전부 caller-assertion — 소비 시점 검증 부재 |
| consumption/CAP-P1-3 | P2 | high | FR 소비 루프 20일 정지 — '모듈 자동흐름/신선도 자동인식'은 코드만 있고 구동 주체 부재 |
| consumption/CAP-P1-4 | P2 | high | pg1_admission 실질 체크 전부 fail-open — 신세대 후보에게 governor 권고는 양방향 노이즈 |
| consumption/CAP-P1-5 | P2 | medium | graduation 통과 공급 0/191 — 소비층 정교화가 공급 현실 대비 과잉투자, binding 레버 배관은 부재 |
| knowledge/AXM-01 | P1 | high | 승격 깔때기 구조적 0%: Falsification·External 축이 데이터 모델상 영구 불충족 — 엔진 가동 4주간 mode-local 승격 0건 |
| knowledge/AXM-02 | P1 | high | axiom hook 2종(enforcement+context_inject) 런타임 완전 사망 — python3 WindowsApps 스텁. live test로 무차단·무주입 실증 |
| knowledge/AXM-03 | P2 | high | enforcement 스키마 불일치: active JSON은 전부 string, hook은 dict만 처리 — python3 수리해도 동적 강제는 영구 0매치 |
| knowledge/AXM-04 | P2 | high | 실패 지식의 hypothesis-time 자동 대조 지점 부재 — 594건 corpus가 새 가설 생성 시 소비되지 않음 |
| data/DATA-P0-1 | P0 | high | RAWDATA.parquet BM_Ret가 지금 이 순간 +581% 손상값을 담고 있고, 값-무결성 가드가 0개 — factor DB 빌더가 이 컬럼을 직접 소비 |
| data/DATA-P0-2 | P0 | high | PIT 런타임 차단 게이트가 orphan 상태인데 문서는 '자동 차단'을 주장 — ad-hoc 리서치(현재 주력 경로)는 detect_lookahead를 아예 안 거침 |
| data/DATA-P1-1 | P1 | high | 캐시 vintage pinning이 사고 후에도 미코드화 — bootstrap이 세션 시작과 동시에 백그라운드 refresh를 돌려 '세션 중 캐시 변이'를 설계로 내장 |
| data/DATA-P1-2 | P2 | high | staged 인제스트 컬럼 strip 사고의 원인 코드가 그대로 — sanitize_rawdata()는 여전히 K200/KQ150 등 7컬럼을 무조건 strip |
| data/DATA-P1-3 | P1 | high | 무결성 모니터링 = 신선도 단일축: 값·행수·스키마 감시 전무 + daily_refresh 전 단계 fail-soft로 부분실패가 '완료'로 보고 |
| data/DATA-P1-4 | P1 | high | Python 파이프라인 PIT 사각 + 보상통제(Codex Round) 제거로 무보호 구간 발생 |
| data/DATA-P1-5 | P1 | high | OneDrive-canonical + .cache 동거 구조 위험이 개별 패치로만 대응됨 — 구조적 완화 장치 부재 |
| hygiene/HYG-01 | P0 | high | 버전관리 3주 정지 — auto-commit 훅이 매 세션 abort, 헌법·게이트 변경 전체가 무보호 누적 |
| hygiene/HYG-02 | P1 | high | 실제 연구 결과가 NA/ 디렉토리로 미스라우팅 — hybrid_commit R0 저장소 경로 후보에 현행 canonical root 부재 |
| hygiene/HYG-03 | P2 | high | qw_refresh 인제스트 상태 파일이 루트 쓰레기 파일명으로 기록 — canonical 상태 파일 부재 |
| hygiene/HYG-04 | P2 | high | 산출물 조회 인덱스 부재+부패 — 687 alpha_search 런·754 stage_artifacts 엔트리·6,827 04_Research 파일이 비인덱스 |
| hygiene/HYG-05 | P2 | high | 권위 레지스트리가 git-ignored — backtest_registry.csv 등 CSV 상태 전체가 버전관리 밖 |
| hygiene/HYG-06 | P1 | high | 핵심 계약 코드 회귀 테스트 0건 + e2e 배터리는 dead 경로 참조 |
| strategy/SC-01 | P2 | medium | 목표(SR 2.5) 재조정 메커니즘 부재 + stale gap vector가 가설 발굴을 실증 사망 방향(core_alpha standalone)으로 조향 |
| strategy/SC-02 | P2 | high | 시스템이 확립한 최상위 실증 법칙(post-2017 감쇠·SR 천장·standalone-dead)이 agent 주입 컨텍스트·axiom 시스템에 부재 — 자가발전 루프가 문서상으로만 닫힘 |
| strategy/SC-03 | P2 | medium | 자동화 강도가 실증 EV와 역상관: 죽은 방향(standalone 알파)은 완전자동, 유일하게 열린 레버(overlay)는 전담 모드·자동 소비 모두 부재 |
| strategy/SC-04 | P2 | high | screen_route 라우팅(OVERLAY_CANDIDATE/DPL_FEATURE/FR_RCMA) = 라벨 생산만 있고 소비자 0 — '버릴 후보와 다르게 쓸 후보의 구분'이 실행되지 않음 |
| strategy/SC-05 | P1 | high | 유일한 미개척 데이터 우위 원천(DART insider)이 인제스트 단계에 좌초 — 팩터화·알파 소비 배선 0, 완료 강제장치 없음 |
| strategy/SC-06 | P2 | high | '다음에 뭘 탐색할지' 결정 계층이 제도화되지 않음 — 탐색 예산 배분이 Q-Lead 세션 메모리와 도훈 mandate에만 존재 |

## 강화 로드맵 A — Mechanical (본 세션 실행)

1. **HYG-01, HYG-05**: 수리 착수 전 git milestone 수동 분할 커밋(.claude/ + 02_Infrastructure/ + 00_Lawbook/ + qepm/memory/ + 06_Registry JSON 선별 스테이징으로 3주치 헌법·게이트 변경 확보) → auto_commit_on_stop.sh:77 abort를 '코어 경로 선별 커밋 + 나머지 skip'으로 강등 + abort 시 Telegram alert 배선 → .gitignore에 '!qepm/registry/backtest_registry.csv' 예외 추가

2. **DATA-P0-1, DATA-P1-2, DATA-P1-3**: RAWDATA BM_Ret 손상 수리: `python 02_Infrastructure/data/build_index_cache.py --update-rawdata` 실행 → factor_db_202607 재빌드(M08 등 59팩터 복구) → 값-무결성 가드 신설: cache_freshness_audit.R에 값-sanity 섹션(RAWDATA |BM_Ret|>0.15 건수·K200/KQ150 존재·benchmark parity, 위반 시 CRITICAL) + rawdata_sanitize.R core_cols에 K200/KQ150 등 Layer2 7컬럼 추가 + BM_Ret merge 직후 stopifnot(max abs<0.2) + cache_registry.json에 값 선언 필드

3. **HOOK-P0-1, AXM-02, AGT-01, AGT-05, HOOK-P1-2**: 훅 계층 일괄 소생: _shared_parse.sh에 PY 절대경로 fallback(QVEST_PY → .venv_qvest_ml/Scripts/python.exe) 1회 구현 + hooks/ 내 bare python3 직접호출 훅 전수 치환(axiom_enforcement_hook.sh·axiom_context_inject.sh·safety_guard.sh 등, discovery_graduation_gate.sh는 항목 4에서 처리) + selection_contamination_detector.sh:32·lockbox_audit_trail.sh:19의 `ps -o ppid=`→`$PPID` 이식 + WT regex `WT-[DP]`→wt_type-aware `[DPSH]` 확장 → 수리 후 bootstrap 카나리아 + hook_e2e_battery 재검증(잔여 FAIL 허용 금지)

4. **CAP-P0-1, MC-01, HOOK-P0-3, MC-04**: discovery_graduation_gate.sh 전면 완성(단일 파일 1회 수정): python3→QVEST_PY 절대경로 + hard_fail에 oos_retention<0.7·calmar<0.64 fail-closed 추가(PORT_t 처리와 동일 패턴, 미산출=block) + is_sweep인데 DSR None이면 block + constraint_defaults.json tier_graduation에 min_oos_retention=0.7·min_calmar=0.64 severity hard 등재 → should-block selftest로 확인

5. **GOV-02, GOV-03, GOV-04, GOV-05, AGT-02, AGT-03, GOV-10**: v8.2 Codex 잔재 sweep 완결: dispatch-orchestrator.md·ramp-orchestrator.md frontmatter에서 qvest-codex-round 제거 + Codex Round 절을 judge.md:97-98 Self-Adversarial 문안으로 교체, strategy-implementer.md:38-39 정정, workflow 2종(.js)의 'Codex Round 5단계 의무' 문자열 교체 + stale 주석 수정, promote_global.R:7,:23 codex→self_adversarial rename, role_permissions.json:104 문구 교체, python-policy.md §5 'Codex Round 보강' 현실화, qlead_spawn_template.md v8.2 기준 재작성 또는 DEPRECATED 스탬프

6. **GOV-06, AXM-01, AXM-06, AXM-08, GOV-01**: Axiom 승격 배관 수리: promote.R:27 .MODE_PREFIX에 ramp="RAMP" 추가(hard crash 해소) + External hurdle을 이미 실값 465건 보유한 oos_retention/oos_effect_vs_is 기반으로 재정의, cluster_extractor.py:277 oos_months 하드코딩 None을 실값 매핑으로 교체, axiom-engine.md를 4-mode(AS/QPM/FR/RAMP) + INV-5 Codex→Self-Adversarial로 갱신 → 수리 후 pending 후보에 promote.R 1회 구동해 승격 첫 사례 또는 잔여 hurdle 진단 확보

7. **CAP-P0-2, AXM-01, MC-04**: run_alpha_search.R 국소 수리 묶음: :1388 book_state 경로를 qepm/mailbox/governor/book_state.json으로 수정(incumbent 공백 버그 1줄) + 이미 산출 중인 placebo/lag-stress 검증 결과를 L-code metrics의 falsification_attempts로 emit 배선(항목 6 승격 깔때기의 공급측) + selection_type=chain 하드코딩에 iteration 근거 기록 필드 추가

8. **MC-02, HOOK-P1-3, GOV-05**: 계약 등재 강화: registry_writer.R:60 block 조건을 integrity %in% c('FAIL','PENDING') + NA로 확장(audit 사실상 의무화), backtest_contract_audit.sh를 strategy_id-scoped rds 검사 + 미발견 시 fail-closed로 수정 + TARGET_PATTERN/자체합성 regex에 .py 및 Python idiom(np.prod(1+r)·.cumprod()·(w*r).sum) 추가, answer_principles_grep.sh 동일 .py 확장

9. **CAP-P1-2, AS-01, CAP-P2-3, SC-04**: 모듈 소비 신뢰 수리: build_module_performance.R 로드 루프에 tools::md5sum(sim_path) vs catalog module_hash 대조(불일치=skip+quarantine 로그) 추가 + module_catalog.json의 batch_434 오염 엔트리(PATCHED_DIRECT_COMBO/UNMAPPED_SPEC 접미사 16건+관련) 일괄 label_contaminated=true + executed_signal 분리 기록 스크립트(수치는 실측이므로 보존, 라벨만 정정)

10. **DATA-P0-2, DATA-P1-4**: PIT 사각 정직화+축소: pit-validation.md의 'forge_code_guard 자동 차단' 허위 문구 즉시 정정(존재하지 않는 방어선 신뢰가 최악) + lookahead_detector.R에 .py 패턴 포트(shift(-H)·pct_change 방향·merge_asof direction·full-sample fit→transform 등 regex 이식, 대상 확장자에 .py 추가)

11. **AGT-04, AGT-06, AGT-09**: agent 정의 stale 동기화: judge.md:56,58을 measurement-graduation §3 selection-operator 현행 문안 + essence_score selection_type 파라미터 명시로 교체, optimizer-research.md:76 max_names>20→25, blender.md:51 20→25, governor.md/judge.md 헤더의 모델 표기(Sonnet 4.6/Opus 4.7) 삭제

12. **HYG-02, HYG-03, HYG-08**: 위생 일괄: NA/qepm/research/results/TO1099 → canonical 이관 후 NA/ 삭제 + hybrid_mode.R:29 후보에 OneDrive canonical 추가 + NA 시 stop() 가드, 루트 Hashtable 상태 3파일 최신본을 .cache/qw_refresh_state.json으로 이관 후 삭제 + qw_refresh.ps1 Save-State에 .json 경로 가드, 루트 셸사고 파일('(no'·'1)'·'max'·'surface'·supp_out.txt·Rplots.pdf) 삭제

## 강화 로드맵 B — Governance (도훈 confirm 필요, 미실행)

1. **강제 계층의 헌법-현실 정합 원칙 결정: ① 게이트급 훅(graduation/safety/contract) 한정 fail-closed 전환(ERR trap 시 block + 로그, harness.md '전 훅 fail-open' 원칙 개정) ② agent marker 방식 공식 폐기 후 lockbox를 fail-closed(식별 불능=deny) 또는 문서 정직화(CLAUDE.md·pit.md의 'Hook L3 자동 차단' 주장을 실커버리지 경계로 정정) ③ QVEST_SKIP_* 우회 사용 시 git-tracked 감사로그 의무**
   - 근거: AX-002('하네스 내 성과만 유효')의 자기 위반 상태 해소. 훅이 못 막는 것을 막는다고 주장하는 것이 python3 사고 3일 방치의 근본 원인 — 강제와 서사 중 하나는 반드시 움직여야 하며 이는 헌법 변경(위반=AX-002 동급 문서들 개정)이라 도훈 confirm 필수 (HOOK-P0-1/P0-2, HOOK-P2-1, AGT-01, MC-07, HOOK-P1-1)

2. **자가발전 승격 요건 개정 승인: Falsification 축을 alpha-search 기산출 placebo/lag-stress 자동 기록으로, External 축을 oos_retention 실값 기반으로 재정의(현행 요건은 데이터 모델상 영구 불충족) + pending candidates 15건 주간 confirm 큐 1회 처리 + methodology_active.md mandate를 실존 SOT(l_code 디렉터리+corpus)로 개정(파일 자체가 repo에 부재 — 미검증이나 확인 시 헌법 문구 수정 필요)**
   - 근거: 헌법 정체성('각 모드 자가발전')이 4주째 산출 0인 이유가 게으름이 아니라 구조적 도달불가 — 요건 완화가 아닌 측정 가능한 요건으로의 교체이며 승격 기준 변경은 도훈 confirm 사안 (GOV-01, AXM-01, AXM-05, AXM-07)

3. **book-marginal ΔIR 컨벤션 단일화: recon NAV 기반 net-active IR 단일 기준을 book_state.json convention 필드로 명문화 + .pg_book_ir가 mailbox 3-package 대신 module_catalog sim_result를 소비하는 어댑터 승인 (현재 gross 1.575/net-active 1.416/geo-active 1.755 3개 혼재 — admission마다 0.05 문턱의 의미가 다름)**
   - 근거: §4 자본 게이트의 재현성·비교가능성 복구. codified 게이트가 alpha_search 262건 후보에게 구조적 작동불능인 상태에서 수동 판정의 기준 통일은 자본 판단 직결이라 도훈 결정 필요 (CAP-P0-2, CAP-P1-4)

4. **SR 2.5 목표의 도달 경로 명시: 목표 자체는 유지(AX-000 정합)하되 §6 레버 3종별 마일스톤(overlay 정교화 잔여 EV / 잔차-직교 sleeve PORT_t 통과 조건 / 비-return 원천)을 헌법에 병기 + gap vector sleeve_needs를 실증-열린 방향 enum으로 재정의(core_alpha standalone은 16/16 FAIL posterior 라벨과 함께 강등) + bootstrap에 gap vector staleness 검사**
   - 근거: 실증 천장 ~1.1과 목표 2.5 사이 격차를 시스템이 어떻게 메울지에 대한 명시적 지도가 없어 조향 신호가 죽은 방향을 가리키는 중 — 목표는 도훈 mandate 사안이므로 조정이 아닌 '경로 명시'로 상정 (SC-01, SC-06)

5. **vintage pinning 규약 명문화: measurement-graduation.md에 'HARD 게이트·다중라운드 A/B 산출은 pinned snapshot 기준, pin tag를 산출물에 기록' 1개 조항 추가 + pin_cache/read_pinned 헬퍼 표준화**
   - 근거: 07-02 실사고(benchmark 재생성→graduation 경계 판정 반전)가 입증한 재현성 결함인데 방어책이 메모리 노트+수동 복사에 의존 — 헌법(Level 0 룰) 조항 추가라 confirm 필요 (DATA-P1-1)

6. **.cache를 로컬 디스크(C:\qm_cache)로 이동 + OneDrive 쪽 junction(mklink /J) — config.R 무수정 투명 적용, pin/backup만 OneDrive 명시 복사**
   - 근거: OneDrive 기인 실측 사고 3건(mmap 1224 halt·페이징 timeout·read HANG)이 전부 per-script 패치로만 대응됨 — 대용량 백테 처리량과 세션 소모를 구조적으로 해소하는 인프라 결정 (DATA-P1-5, HYG-08)

7. **6-agent 미들 스테이지(risk+optimizer) 병합 또는 dossier-pipeline 기본경로 승격 검토 — 확신도 낮음(미검증 overflow): 최근 full run 06-26이 마지막이고 HRP frontier 실측이 '20종 single-cluster book에서 위험기반 배분은 알파 희석'을 시사하나, 실사용률 붕괴 주장 자체는 검증 안 됨**
   - 근거: 고정비(opus xhigh spawn×6 + 이중 산출)와 한계 정보가치의 재평가 — Multi-Agent Summary 헌법 변경이므로 실사용 데이터 확인 후 도훈 결정 (AGT-08 — unverified, 확신도 낮음 표기)

## 강화 로드맵 C — Research 방향 (권고)

1. **DART insider 백필 즉시 착수 + 팩터화 병행 — 백필 실행(체크포인트 0파일, mandate 후 3일간 시작도 안 됨) + fe_insider_*.R 스켈레톤을 fe_buyback_drift.R 패턴으로 선작성(net insider buying ratio·cluster buying, 공시일 PIT lag) + 백필 커버리지를 morning brief 1줄 노출**
   - 근거: 논문풀 95% 소진·327팩터 post-2017 감쇠가 실증된 상태에서 유일하게 새 정보를 담은 고유 수집 원천 — 시스템 스스로 최우선 지목(06-29, 07-02 W3)했으나 완료 강제장치가 없어 표류 중. 현 시점 발굴 EV 최고 (SC-05)

2. **OVERLAY_CANDIDATE 소비 배관 실측 — idle 상태인 auto_regime_overlay_ab.R 하네스에 screen_route 라벨 큐를 배선하고 LH(smartbeta loser-harvest)→overlay A/B를 첫 케이스로 실측(clean-timing +1 lag 스트레스 의무). 단 KR 시장타이밍은 4중 settled-negative이므로 기대치는 낮게 — cheap-kill 우선**
   - 근거: 2-tier 게이트 개혁의 존재 이유(신호 실재하나 MDD로 죽은 후보의 재활용)가 라벨 단계에서 끊겨 알파 회수 효과 0 — 하네스는 이미 존재하고 배선만 없어 한계비용이 낮음. 07-03 메모리에 이미 최우선 큐로 등재된 항목의 실행 (CAP-P1-1, SC-03, SC-04)

3. **graduation-근접 후보(PORT_t 2.2~2.5 대역 3~4건) oos 실패 사유 일괄 라벨링 — §3 규정대로 overfit-pattern vs cohort-decay 분리 후 decay는 screen_route 재배정**
   - 근거: 공급 0/191의 사인 규명 없이는 공급측 투자 방향을 정할 수 없음 — 실패가 전략 고유 과적합이면 발굴 프로세스 문제, cohort decay면 표현공간 문제로 처방이 정반대 (CAP-P1-5)

4. **FR/RAMP 신규 정교화 동결 유지 — '첫 graduation 통과자 발생'을 해제 트리거로 명시. 소비층 리서치 예산을 공급측(1~3번)으로 전량 재배분**
   - 근거: 3개월 졸업 0인 상태에서 배합 계층 고도화는 한계 EV 0에 수렴 — 이미 사실상 동결 상태(06-13/18 이후)이므로 이를 명시적 정책으로 고정해 회귀 방지 (CAP-P1-5)

5. **논문 연료 재충전: 라우터 소스에 SSRN/저널 아카이브(RFS·JF·JFE) 배치 스캔 1회성 백필 추가 — 확신도 중간(AS-09 미검증): 'QEPM 95% 소진'은 자체 컬렉션 기준이지 문헌 전체가 아니며, 최근 라우팅 alpha 수율 0/38은 소스 고갈 신호**
   - 근거: 발굴 기계는 잘 도는데 투입이 arXiv 신간+carried 재부상에 의존 — KR-특화·비-return 데이터원 우선 등 수집 방향은 도훈 confirm 사안 (AS-09 — unverified, 확신도 낮음 표기)

## 냉정 총평

도훈님, 결론부터 말씀드리면 — 이 시스템은 지금 상태로도 '가짜 알파에 속지 않는 능력'은 상위권이지만, '알파를 찾아내는 능력'은 그 절반에 한참 못 미치고, 그 격차의 대부분은 리서치 실력이 아니라 배관 문제입니다. 측정 코어(PORT_t·oos v2·holdout falsification)와 정직 라벨·격리 계층, 그리고 도훈님의 수동 confirm — 이 세 개가 지난 석 달간 실제로 사고를 막아온 전부이고, 헌법이 주장하는 자동 강제 계층은 대부분 죽어 있었습니다. python3 스텁 하나로 하드블록 훅 42/57이 fail-open이고, 05_Production 보호와 자본 졸업 게이트에 차단 payload를 넣어도 통과하며, 역할경계 훅은 애초에 한 번도 발화한 적이 없습니다. 더 나쁜 건 v8.2 검증 라인에 'python3 환경 FAIL'이 기록된 채 방치됐다는 점 — 문서와 현실의 드리프트가 이 정도로 만연하면 다음 사고도 시스템이 아니라 사람이 발견하게 됩니다. 실제로 지금 이 순간 RAWDATA BM_Ret에 +581% 손상값이 살아 있고 7월 factor DB가 이미 그걸 먹어 라이브 북의 M08이 결측된 상태인데, 신선도만 보는 감시는 이걸 'FRESH'로 판정하고 있습니다. 자가발전 엔진도 마찬가지입니다 — 4주간 승격 0건은 게으름이 아니라 Falsification·External 축이 데이터 모델상 영구 불충족이고 RAMP는 승격 시도 시 크래시가 확정된 구조적 문제라, 594건의 L-code가 매주 헛도는 트레드밀이며 실질 학습은 전부 MEMORY.md 수동 관리가 떠받치고 있습니다. 그리고 발굴 관점에서 가장 아픈 지점: 게이트는 3중 4중인데 '무엇을 시도할지'를 정하는 계층이 없어서, stale gap vector가 실증 사망한 방향(core_alpha standalone)을 조향하고, 스스로 최우선이라 지목한 DART insider는 3일째 백필이 시작도 안 됐으며, 졸업 0/191인 상태에서 투자는 배합 계층에 몰려 있었습니다. 즉 근본 문제는 두 개입니다 — 첫째, 강제·학습·전달의 '자동'이 전부 종이 위에 있어 시스템 신뢰가 도훈님 개인의 정직성과 기억력에 과적합돼 있다는 것, 둘째, 발굴 확률을 실제로 올리는 한계 투자처(새 데이터 원천·overlay 소비 배관·근접 후보 사후분석)가 비어 있다는 것. 다만 이건 재설계감이 아니라 수리감입니다 — 이번 세션의 기계 수리 12건(커밋 확보→데이터 수리→훅 소생→게이트 완성)으로 신뢰 기반의 상당 부분이 복구되고, 그 다음은 리서치 예산을 소비층에서 공급측으로 돌리는 결정의 문제입니다. SR 2.5는 현 레버 구성으로는 도달 경로가 정의돼 있지 않으니, 목표를 내리자는 게 아니라 레버별 마일스톤을 명시해 조향 신호부터 살리는 걸 권합니다. 종합 4.5점 — 기각 기계로는 7점, 발굴 기계로는 3점이고, 그 사이를 메우는 건 코드 몇 백 줄과 우선순위 재배분이지 새 아키텍처가 아닙니다.

---
생성: Q (Claude Fable 5), 아키텍처 감사 워크플로우 wf_37f4718b-94b. 상세 발견 원본: 세션 scratchpad confirmed_findings.json.
---

## 진행 상태 / 재개 가이드 (2026-07-03 22:53 기준, 세션 1ba51a8d)

### 완료
- [x] **감사 완료**: 10영역 71-agent 감사, 발견 60건 전수 적대검증 통과 (반증 0). 기계가독 원본: `04_Research/architecture_audit_20260703_data/confirmed_findings.json` + `synth_roadmaps.json`
- [x] **Milestone 커밋 3건 + push**: `0ee02018`(헌법·에이전트·스킬) / `918dcbc0`(인프라·계약·훅) / `861782f3`(axiom·레지스트리) → origin/main 반영 완료. 3주치 무보호 변경 해소.
- [x] **Mechanical 수리 6/10 그룹** (상세: `_data/fix_results_partial_run1.json`):
  - `graduation-gate`: discovery_graduation_gate.sh에 oos_retention·calmar HARD fail-closed + sweep-DSR block 배선, constraint_defaults.json v2.5. should-block 7종 실측 PASS.
  - `docs-sync`: v8.2 Codex 잔재 sweep + agent stale 동기화 12파일 (judge DSR 현행화, 20→25, 구 모델 표기 삭제).
  - `alpha-search-fix`: run_alpha_search.R book_state 경로 + falsification_attempts emit 배선 + chain 자격 기록.
  - `contract-enforce`: registry_writer PENDING/NA 차단 확장, backtest_contract_audit·answer_principles_grep .py 확장.
  - `pit-honesty`: pit-validation.md 허위 '자동 차단' 문구 정정, lookahead_detector.R .py 포트.
  - `hygiene-ops`: auto_commit_on_stop abort→선별커밋 강등, 루트 쓰레기 `.trash_20260703/` 이동, NA/ 실데이터 → qepm/research/results/TO1099 이관, qw_refresh 상태 .cache/qw_refresh_state.json화, hybrid_mode.R canonical 경로.

### 완료 (2차분, 2026-07-03 23:2x — resume 재실행 wf_9b0e4635-7b1 완주 + 메인 후속)
- [x] `hooks-resurrect`: _shared_parse.sh QVEST_PY_BIN 해석 체인(QVEST_PY→venv→fallback) + 핵심 훅 7개 python3 치환 + $PPID 이식 + WT regex [DPSH] 확장. 기능 12테스트 PASS (AX-001 하드블록·역할경계 블록·lockbox 감사로그 실측 발화).
- [x] `data-integrity`: RAWDATA BM_Ret는 이미 청정(07-03 20:40 선수리) — 실피해는 factor_db_202607 60팩터 결손이었고 재빌드로 BM 의존 43팩터(라이브 북 M08 포함) 복구. 값-무결성 가드 3축(|BM_Ret|>0.15·required_cols·benchmark parity) 신설 + 음성케이스 CRITICAL 발화 실증. 백업 `.cache/pin_backup_20260703/`. 잔여 결손 17팩터 = 7월 QuantiWise 미인제스트(별개 이슈).
- [x] `module-trust`: 해시검증(.verify_module_hash)+오염 16건 라벨은 auto-commit c2babc75에 기반영 확인 — 249모듈 md5 전수 대조 mismatch 0 (frozen 계약 실성립 입증).
- [x] `axiom-pipeline`: promote.R ramp crash 해소 + cluster_extractor oos median 매핑 + codex→self_adversarial(back-compat). 진단 구동: pending 15건 crash 0 완주·승격 0 — 병목 = 입력 생산자(Falsification attempts 15/15 결측).
- [x] **[메인 후속 1] 훅 37개 bare python3 잔여 청소** — 전 훅 QVEST_PY_BIN 블록 삽입+치환. **hook_e2e_battery 라이브 기본 셸 11/11 PASS** (수리 전 7/11 — agent_role_guard/wt_constraint/tg_guard FAIL 해소). 감사 1위 약점(훅 42/57 fail-open) 종결.
- [x] **[메인 후속 2] lcode_harvester.py pass-through 갭 봉합** — oos_months·oos_effect_vs_is·portfolio_alpha_t 추가. 재구동 실증: corpus 594건 중 portfolio_alpha_t 11건 유입(수리 전 0) → global 승격 구조적 불가 해소. External 축은 생산자 적립 시작 시 자동 흐름.
- [x] 사후 검증: 구문검사 전 파일 PASS / bootstrap 카나리아 BOOT_FAILS 0 / router selftest OK / should-block 3종(graduation·05_Production·AX-001) 실측 block.
- [x] 최종 커밋 + push (아래 참조).

### 남은 것 (다음 세션)
- [ ] **Governance 7건 도훈 confirm** (로드맵 B) — ① 게이트급 훅 fail-closed 원칙 ② axiom 승격요건(Falsification·External 축) 측정가능 재정의 ③ ΔIR 컨벤션 단일화 ④ SR 2.5 레버별 마일스톤 ⑤ vintage pinning 헌법화 ⑥ .cache 로컬디스크+junction ⑦ 6-agent 미들 병합 검토.
- [ ] Falsification 축 생산자 배선 마무리 — run_alpha_search falsification_attempts emit은 배선됨(1차분), 신규 런 적립 후 promote.R 재진단으로 첫 승격 확인.
- [ ] Research 로드맵 C: DART insider 백필 착수(최우선) / OVERLAY_CANDIDATE 소비 배관(LH 첫 케이스) / graduation-근접 후보 oos 실패 사유 라벨링.
- [ ] 7월 QuantiWise 인제스트 후 factor_db 잔여 17팩터 자동 해소 확인.

