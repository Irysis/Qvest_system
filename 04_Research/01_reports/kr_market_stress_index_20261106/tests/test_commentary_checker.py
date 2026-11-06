# 해설 검사기 양성 대조 + 위반 주입(돌연변이) — 정직한 문장은 통과, 위반 9종은 각각 불통과여야 한다
import sys; import os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import make_commentary as C, make_daily_report as M
meta,d,st,eps,cv,nsr,rob,bm = M.load(); pack = C.build_pack(meta,d,st,eps,cv,nsr); flat,_ = C.flatten(pack)
g, g20 = flat["점수.오늘"], flat["점수.20거래일전"]; n90 = int(sum(a['심각도']>=90 for a in pack['분야']))
fx = flat['분야[원화 · 환율].심각도']
good = (f"오늘 스트레스 점수는 {g:.0f}점으로 2006년 이후 나쁜 순 상위 {pack['역대순위']['나쁜순_상위_퍼센트']}%입니다. "
        f"대형주 시장의 기여도가 {flat['분야[대형주 시장].기여도_점']:.1f}점으로 가장 크고, 20거래일 전 {g20:.0f}점에서 {g-g20:.0f}점 올랐습니다. "
        f"12개 분야 가운데 {n90}개가 심각도 90 이상입니다. 원화 · 환율은 심각도 {fx:.0f}로 평온합니다.")
claims = [{"value": f"{g:.0f}", "source": "점수.오늘"}, {"value": str(pack['역대순위']['나쁜순_상위_퍼센트']), "source": "역대순위.나쁜순_상위_퍼센트"},
          {"value": f"{flat['분야[대형주 시장].기여도_점']:.1f}", "source": "분야[대형주 시장].기여도_점"}, {"value": f"{g20:.0f}", "source": "점수.20거래일전"},
          {"value": f"{g-g20:.0f}", "source": "점수.오늘 - 점수.20거래일전"}, {"value": str(n90), "source": "count(분야.심각도 >= 90)"},
          {"value": f"{fx:.0f}", "source": "분야[원화 · 환율].심각도"}]
T = {"① 정직": (good, claims, True), "② 지어낸 숫자": (good.replace("평온합니다.", "평온하며 외국인 순매도는 57일째입니다."), claims, False),
     "③ 출처 거짓": (good, [dict(c, source="점수.60거래일전") if c["source"]=="점수.20거래일전" else c for c in claims], False),
     "④ 분야 바꿔치기": (good.replace("대형주 시장의 기여도", "원화 · 환율의 기여도"), claims, False),
     "⑤ 예측 표현": (good + " 스트레스는 더 오를 것으로 보입니다.", claims, False),
     "⑥ 고정 수로 위장(출처 생략 20)": (good, claims[:-1], False),
     "⑦ 개수 거짓": (good, [dict(c, value="7") if c["source"].startswith("count") else c for c in claims], False),
     "⑧ 금지 상수": (good, claims + [{"value": "51", "source": "점수.오늘 + 7"}], False),
     "⑨ 마크다운": (good.replace("오늘 스트레스", "**오늘** 스트레스"), claims, False),
     "⑩ 반올림 틀림": (good.replace(f"{g:.0f}점으로", f"{g:.0f}.9점으로"), claims, False)}
bad = 0
for k,(t,c,exp) in T.items():
    ok, why = C.check_claim(t, c, pack); bad += ok != exp
    print(f"{'PASS' if ok==exp else '★WRONG'} {k}: ok={ok} {why[:2]}")
print("검사기 오판", bad); sys.exit(1 if bad else 0)
