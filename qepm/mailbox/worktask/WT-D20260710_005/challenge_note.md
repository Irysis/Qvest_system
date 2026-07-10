# Self-Adversarial Challenge — WT-D20260710_005 (공시-품질 비-가격 신호군)

**Agent**: QEPM Alpha Research. **When**: finalize 직전 (2026-07-10). **Method**: Opus 4.8 native adversarial (v8.2 — 외부 Codex Round 없음). AX-008 3-source 중 1.
**Verdict 요약**: H-a(정정공시 빈도/강도) = **measured-NEGATIVE** (exploitable alpha 부재, exclusion은 size-proxy로 book 훼손). H-b(악재유형 flag) = **redundant-by-construction** (Q-Lead 종결). 데이터 depth·PIT는 우수하나 신호 부재 — 공시-품질 축의 정직한 negative 지도.

---

## 자기 비평 concern (≥3) + 분류

### C1 [REBUTTAL] "restatement 정의(grepl 정정)가 과도하게 넓다 — 첨부/기타정정 포함, 진짜 기재정정만 봐야"
- **근거 반박**: strict 버전 `q_rates24`(`^\[기재정정\]` 접두만, 44,011건)도 동일 null — rank-IC full t=0.38, 2017+ t=0.28, sp3 t=-0.06. 정의를 좁혀도 신호 없음. 정의 breadth는 결과를 구제하지 못한다(아래 C3 size-proxy 지배가 정의 무관).
- **인용/L-code/data 3축**: Palmrose-Richardson-Scholz 2004 JAE(restatement→하락은 event-time short-window, 본건 monthly cross-section와 상이) · L-AR-20260706(직교 novel도 전이벽) · 실측 q_rates24 full/2017+/sp3 3-구간 전부 |t|<0.4.

### C2 [PARTIAL→REBUTTAL] "공시 제도 시대별 변경(불성실공시 제도·XBRL 2009·공정공시 진화)이 정정 count의 시계열 의미를 오염 — pre-2009 vs post-2015 비교 불가"
- **부분 인정**: 정정공시 절대 count의 시계열 level은 제도 변경에 민감(맞음). 
- **반박(설계가 이미 방어)**: 본 신호는 **월별 횡단면 rank/threshold**(같은 달 내 상대) — 시계열 level shift는 매월 차분되어 중립화됨. IS(2005-2018)·OOS(2019-2026) 양 구간 negative 방향 일관(ex_any IS-4.82/OOS-2.76, ex_cnt3 IS-4.29/OOS-2.95) → 제도-era 무관하게 동일 mechanism(size-proxy). 시대 confound가 결론을 뒤집지 못함.
- **3축**: 제도사(불성실공시법인 지정제 2002~·공정공시 2002~) · 횡단면 설계(per-month lm/frank) · IS/OOS 부호 지속.

### C3 [ACCEPT-partial → 추가측정으로 CLOSE] "size와 governance를 혼동했다 — 정정 빈도 = 대형주 공시량 proxy일 뿐, size-중립화하면 진짜 governance 신호가 살아있을 수 있다"
- **인정**: 이것이 핵심 confound. 실측 spearman(cnt_24, logSize)=**+0.299**, top-25 中 cnt≥3 firm의 size-pctile 0.54 vs cnt<3 0.38, 최다 정정 = 삼성(A005930)·SK하이닉스(A000660)·고려아연(A010130) = mega-cap 모멘텀 리더. count-based exclusion(-4.5)의 harm은 순수 governance 아닌 mega-cap 제거 효과(ex_cnt3가 book의 **88.5%** 제거).
- **추가측정으로 CLOSE (self-rationalization 회피 — "미미하니 OK" 금지, 실측으로 판정)**: rate를 log(Size)에 월별 residualize한 **size-neutral** 신호 재측정 → rank-IC mean 0.0070 **t=0.91**(null), 2017+ t=0.69; size-neutral top-quintile exclusion book-marginal **NWt=-1.28**(IS-1.66/OOS+0.34, 부호 비일관). **size 혼동을 제거해도 신호 부재** → governance 신호가 size에 가려진 게 아니라 애초에 없다. 이 축은 진짜 negative.
- **3축**: You-Zhang 2025(integration>two-stage, but 여기선 신호 자체 부재) · [[reference-kr-2025-megacap-semi-regime]](mega-cap이 공시·수익 양쪽 지배) · size-neutral rank-IC/book-marginal 실측 2종.

### C4 [REBUTTAL] "primary rate-form(ex_q80)은 IS-1.66→OOS-0.15로 약화 = 사실상 null인데 왜 negative라 하나 / lag1 -1.98은 look-ahead 아닌가"
- **반박**: 정확히 그렇게 보고함 — rate-form은 **null**(placebo emp_p=0.275, q95=2.00 내), count-form만 강하게 negative(=size-proxy). 종합 verdict = "어느 방향도 usable alpha 없음". lag1(-1.98)은 **negative 방향 유지** = look-ahead면 lag1이 null/positive로 무너져야 하는데 유지됨 → 오히려 PIT clean + 방향(size-proxy harm) 견고함의 증거(faith/BearProb 동월-누출 케이스와 반대 패턴).
- **3축**: measurement-graduation §3(rate-IC advisory·placebo null) · overlay_pit_guard 원리(lag1 붕괴=누출 신호, 본건 무붕괴) · IS/OOS/placebo/lag1 4중 실측.

## Self-rationalization auto-detection
- 사용 표현 점검: "미미/관행적/실무적/보수적이면 OK/대부분 동일" → **미사용**. C3에서 "size 효과 미미하니 무시" 유혹을 **실측(size-neutral 재측정)으로 대체** — 합리화 아닌 측정으로 close.

## Q-Lead escalate trigger 점검
- HIGH severity ≥5? 아니오(신호 부재는 negative-map, 위반 아님). AX axiom hard FAIL ≥3? 아니오. PIT C1(lockbox/lookahead) 위반? 아니오(rcept_dt PIT + lag1 견고). → **escalate 불요**. 정상 negative 종결.

## 잔여 미봉(정직)
- LLM 텍스트(H-d)·공시 빈도 규칙성(H-c)은 Q-Lead 판단 보류(본 WT 미착수). 
- 본 negative는 **exclusion/quality-long 형태 한정** — 정정공시의 event-time short-window(개별 정정 직후 3~5일 drift) 및 정정 *유형별*(실적정정 vs 형식정정) 세분은 미측정(document.xml 파싱 필요 = insider 크롤과 동일 heavy 벽, 본 WT scope 밖). 이는 방향 판결이 아닌 구성-scoped negative(INV-7).
