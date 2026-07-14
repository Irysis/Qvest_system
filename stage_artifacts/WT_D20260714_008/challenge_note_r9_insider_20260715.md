# R9 insider × 선별 — Self-Adversarial Challenge (FQ-019, 2026-07-15)

**대상**: RAMP R9 insider 확장 패널 × PORT_t-정렬 선별 판정 (Stage A plain 2×2 격자 + Stage B F-1 챔피언 arms).
**규약**: v8.2 Opus 4.8 자체 적대검증 (외부 Codex 없음). 약점 ≥3 자가제기 → ACCEPT/PARTIAL/REBUTTAL → final.
**측정 사실 요약**:
- Stage A (plain, frozen prereg fdb26b8f → 재실행 config_hash 9ad760e8, as_of만 상이): Ppins_W36_K20 cap-w 2.77 / EW-uni 3.91 / oos −0.068 · Pbase 2.67 / 3.88 / −0.056. paired(Ppins vs Pbase) max +0.73 (cap-w). KILL=TRUE.
- Stage B (F-1 champion, level36 진입·rank 퇴출·level36 충원): Ppins_F1_W36_K20 cap-w 2.878 / EW-uni 4.282 / oos +0.018 · Pbase_F1 2.724 / 4.365 / +0.007. paired max +0.71 (cap-w=EW-uni). KILL=TRUE.
- 참여: insider 팩터 pool 선별율 K20 plain 61~70% / F-1 38%(K10) — 참여하나 level36 중위(trailing NW-t +0.98/+1.25).
- graduation: 전 arm cap-w<2.95 · oos≈0<<0.7 · calmar<0.64.

---

## W1 [task ①] 선별-정렬 아크 잔존 frontier가 insider로 열리는가 — **PARTIAL**
- **claim**: 열리지 않는다 — insider 재료로도 아크 벽(cap-w 2.95·oos 0.7) 미돌파. plain·F-1·cap-w·EW-uni 4중 전부 paired<0.73.
- **자가반론**: KILL은 "pool-참여(횡단 팩터 as 선별풀 멤버)" config에 한정된다. insider를 다른 소비면(standalone 오버레이·유니버스 필터·monitoring 신호)으로 쓰면 벽이 다를 수 있다 — 본 측정은 그 면을 다루지 않음.
- **판정 PARTIAL**: pool-참여 frontier는 닫힘(4중 robust). 단 insider 소비면 7종 중 pool-랭킹 1면만 측정 — 나머지는 미측정. → next_probe(오버레이·필터·monitoring)로 전개(답변원칙 §소비처 전개).

## W2 [task ②] insider 신호가 base-102와 직교 참여인가 중복인가 — **PARTIAL**
- **claim**: 참여하나(K20 61~70%) 한계기여 ≈0 (paired cap-w +0.10 / EW-uni +0.03) → 사실상 **중복**(102 풀 존재 시 incremental 정보 거의 0).
- **자가반론**: 근-0 한계기여가 "중복"때문인지, "3 insider 팩터가 20~25 팩터 EW-composite에 희석"돼 신호가 죽은 건지 구분 안 됨. composite 평균이 집중된 insider 엣지를 마스킹했을 수 있다.
- **판정 PARTIAL**: composite 마진에선 중복(both-basis 근0). 단 3/20 EW 희석이 집중 insider 신호를 가릴 여지 → next_probe(insider-가중 또는 insider-only sub-sleeve). 정직 prior: standalone insider는 이미 FQ-001 DEAD_PRELIM(placebo 70pct·EW 음)이라 집중해도 회생 가능성 낮음(보수적).

## W3 [task ③] cap-tier 국소화 재발 — **PARTIAL(base 재발·insider 무관)**
- **claim**: base 신호는 cap-tier 국소화 재발(Pbase_W36_K20 EW-uni 3.88 >> cap-w 2.67 · F-1 base EW-uni oos +0.668 ~0.7 근접). 단 insider **한계기여**는 both-basis 소(Δ cap-w +0.10·EW-uni +0.03)라 insider가 국소화 드라이버 아님.
- **자가반론**: F-1 base EW-uni oos +0.668(≈D3형 문턱 0.7)·Ppins_F1 EW-uni oos +0.643 — EW 기준으론 F-1 base가 D3(벤치-상대 배포성) 재료에 근접. insider 판정이 tier별 insider 효과를 가리는 건 아닌가.
- **판정 PARTIAL**: cap-tier 국소화는 **base(102 선별)**에서 재발(R7/R13 재확인)하나 insider가 그것을 바꾸지 않음(한계 both-basis 소). EW-uni oos ~0.65~0.67 근접은 102-선별 스토리지 insider 스토리 아님. base F-1 EW-oos의 D3 라우팅은 FQ-028 next_probe ②의 별건.

## W4 [자가] F-1 construction parity 미달 — **ACCEPT (paired는 robust)**
- **사실**: Stage B F-1 절대치가 R15 챔피언 재현 실패 — uplift(F-1−plain, 102-base) 측정 +0.055 vs R15 +0.325 (|Δ|0.27 > tol 0.20, parity FALSE).
- **귀속 진단**: 상태머신 R15와 byte-등가 + plain-path Stage A와 정확 일치(Pbase_plain 2.6686=2.67·Ppins_plain 2.774=2.77) → **port 버그 아님**. R15 n_sig=257(2026-05-31) vs 본 n_sig=258(2026-06-30, factor_group_scores +1월) + 07-15 refresh 재산정 returns. plain은 +0.057(2.612→2.669) 상승, F-1은 −0.213(2.937→2.724) 하락 = **F-1 챔피언 cap-w 엣지가 window/vintage-fragile**(1월 확장+refresh에 붕괴). TO 9.4≈9.3(plain), R15도 9.23≈9.27 — F-1 엣지는 회전 아닌 fill 팩터-선택 차이라 window에 민감.
- **판정 ACCEPT**: F-1 **절대치**를 검증된 챔피언 재현으로 주장 불가(라벨 강등). 그러나 insider **한계기여 paired**는 양 arm 동일 construction·동일 vintage라 robust(+0.71). 결론(insider KILL)은 parity 실패에 영향 없음. 부가 발견: F-1 챔피언 +0.325 엣지 비-window-robust(아크 construction 천장 fragile 재확증).

## W5 [자가] vintage 불일치 (panel pre-refresh / measurement post-refresh) — **REBUTTAL/PARTIAL**
- **사실**: 패널 23:56(pre-DailyRefresh) 빌드 · 측정 rawdata 00:07 pin(post-refresh). §7 vintage 분리.
- **자가반론**: 측정 returns가 refresh로 재산정돼 판정이 오염됐을 수 있다.
- **판정 REBUTTAL(paired)/PARTIAL(absolute)**: paired 판정(KILL)은 Ppins·Pbase 동일 RET_DT → return vintage 정확 상쇄(vintage-canceling). 절대 게이트는 post-refresh returns이나 refresh는 tail 1~2월만 재산정(256월 NW-t 무시가능)·판정이 문턱서 크게 멂(cap-w 2.77~2.88<2.95·oos≈0<<0.7 — vintage 소변동이 판정 뒤집을 여지 0). pin(00:07:23) §7 태그 기록·측정 중 mtime 불변 확인(torn-read 부재). 패널 pre-vintage 복구불가(overwrite)이나 paired-canceling으로 무영향.

---

## 종합
- **자기합리화 detect**: "insider가 열 것" 기대에 대한 확증편향 없음 — plain·F-1·both-basis 4중 독립 측정 전부 동일 방향(paired<0.73), 참여 진단(insider 실제 선별됨)까지 대조해 "측정 안 돼서 음성"이 아니라 "참여하나 무기여" 입증.
- **최종**: config-scoped negative(insider pool-참여, plain+F-1). 아크 pool-선별 frontier 닫힘. insider 소비면(오버레이/필터/monitoring)·insider-집중 sub-sleeve는 미측정 frontier(next_probe). 종결 어휘 미사용.
- ACCEPT 2 (W4·W5-absolute) · PARTIAL 3 (W1·W2·W3) · REBUTTAL 1 (W5-paired). 약점 5 ≥ 3 충족.
