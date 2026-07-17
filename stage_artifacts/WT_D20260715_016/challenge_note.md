# R47 Self-Adversarial Challenge (WT-D20260715_016)

Finalize 직전 자가 적대검증 — 4월 사고 재발·백필 무결성·해석 3표면.

## Challenge ① 유니버스 행 감소 / 실데이터 삭제 사고 재발?
**의심**: 4월 사고는 리빌드가 유니버스 실데이터 ~72k행을 삭제한 것. 이번 병합이 같은 사고를 냈나?
**검증**:
- 병합 방식 = **APPEND-ONLY**(full-rebuild 아님). fill_set(진짜 부재 (Ticker,Date))로 inner-join 제한 → collision gate = 0(기존 행 후보에서 원천 배제).
- 행수 정확 가드: post 14,018,480 = pre 14,009,624 + fill 8,856 (정확). g2 삭제 0. g5 min Date 1990-01-05 불변(꼬리 소실 0).
- **유니버스 행 K200|KQ150==1: 2,370,544 → 2,370,544 불변**(g3). Parity P3: 유니버스 행 백업==NEW max|ΔRet|=0.
- Parity P1: 백업 14,009,624행 전량 max|ΔClose|=max|ΔRet|=0.
**결론**: 삭제·감소 0. 4월 사고와 정반대(그때=full-rebuild 재인제스트가 삭제, 이번=interior append만). 사고 징후 없음.

## Challenge ② KRX 시세 vs stored Ret 정합 (백필값이 틀렸나?)
**의심**: KRX 무수정주가로 채운 Close가 기존 stored 시임 Ret과 어긋나면 오염 주입.
**검증**:
- seam-end(07-02) stored Ret은 원래 KRX 07-01 Close 대비로 계산돼 있었음(미영속). 5-샘플 실측: implied prevClose(=Close07-02/(1+storedRet)) == KRX 07-01 Close **5/5 정확 일치**.
- 전수: 216 April-cluster 07-02 recompute(Close07-02/Close07-01−1)==stored Ret **216/216 match**(mismatch 0). → KRX 채움값이 stored 시임과 완전 정합(둘 다 KRX 원천).
- 물리불가 방어: 채운 8,856행 中 |Ret|>0.31 = 0(정지-재개 2행 NA 후). Close 참값 보존.
**결론**: KRX 시세 = stored 정합. 오염 주입 0. (2행 정지-재개는 firewall 규칙대로 Ret NA·Close 보존 — Vol=0→Vol>0 halt 지문 실증.)

## Challenge ③ 잔여 구멍 (덜 채웠나 / 숨긴 실패 있나)
**의심**: "parity 회복" 주장이 잔여를 숨긴 건 아닌가.
**검증**:
- 잔여 source-seam = **2**(A150840·A208340). 이는 penny microcap(128~172원)이 03-30~04-29 **실제 미거래**(KRX Close 부재) → 채울 데이터가 없음. fabricate 금지(정직 잔여 hole = illiquidity, seam 아티팩트 아님).
- 잔여 27 = 1999~2023 상폐/재상장 gap(source_seam=FALSE) — R47 표적 아님(정당 delisting).
- 즉 **표적(216 fillable)은 100% 해소**, 미해소 2는 데이터 부재로 물리적 미충족(숨김 아님·명시 보고).
**결론**: 표적 전량 해소, 잔여는 데이터 부재의 정직 노출. next_probe로 KRX 대체소스(Naver/월간) 재시도 등재.

## 종합
4월-사고 방어 3표면(삭제·정합·잔여) 전부 통과. append-only + 가드 5종 + parity 4종 = mechanical 방어. verdict = capability_established (데이터 무결성 근원수리 능력 확립).
