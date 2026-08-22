# -*- coding: utf-8 -*-
"""discovery 는 있는데 route 가 없는 **첫 날짜** 하나를 출력한다 (검사 보조).

★검사 본문에 heredoc 을 중첩하지 않으려고 분리한다 — 중첩하면 이스케이프가 접혀
  조용히 다른 코드를 검사하게 된다(2026-08-22 실사고 계통, 3회 발생).
좌초일이 없으면 빈 줄을 낸다(호출자가 '대상 없음' 으로 읽는다).
"""
import glob
import re

d = {re.search(r'discovery_(\d{8})', f).group(1)
     for f in glob.glob('stage_artifacts/paper_recharge/mcp_discovery_*.json')}
r = {re.search(r'route_(\d{8})', f).group(1)
     for f in glob.glob('stage_artifacts/paper_recharge/alpha_search_route_*.json')}
m = sorted(d - r)
print(m[0] if m else '')
