# Qvest 브랜드 로고

도훈 제공 콘셉트 이미지(빛나는 Q 링 + 사선 꼬리 + QVEST + 손글씨 태그라인)를 **픽셀 단위로 실측**해 벡터(SVG)로 다시 그린 로고 패키지입니다(2026-11-24).
SVG 가 정본이고 PNG 는 그 렌더입니다. 글자는 전부 외곽선(path)이라 폰트 설치 없이 어디서나 똑같이 보입니다.
★PNG 는 저장소 규칙(`.gitignore` 의 `*.png`)상 git 에 올라가지 않습니다 — git 에는 SVG 정본 · 생성기만 있고, PNG 는 아래 '다시 만들기'로 렌더하면 같은 파일이 나옵니다.

## 파일 · 용도

| 파일 | 크기 | 쓰는 곳 |
|---|---|---|
| `qvest_logo.svg` · `.png` | 1024² · PNG 2048² | 대표 로고(정사각 · 어두운 배경 · 발광) — 표지 · 프로필 · 발표 첫 장 |
| `qvest_banner.svg` · `.png` | 1280×640 | 가로 배너 — GitHub social preview · README 머리 · 텔레그램 채널 커버 |
| `qvest_icon.svg` · `.png` | 1024² | 심볼만(발광) — 텔레그램 봇 · 앱 아이콘 등 **원형으로 잘리는 아바타**(가장 먼 점 = 원 반지름의 90%) |
| `qvest_logo_light.svg` · `.png` | 1400×532 · PNG 2800×1064(투명) | 밝은 배경용 평면 로고 — 보고서 · 문서 · 흰 슬라이드 |
| `qvest_symbol_flat.svg` · `.png` | 512² · PNG 1024²(투명) | 평면 심볼 — 파비콘 · 64px 이하 작은 자리(발광판은 작아지면 뭉갠다) |

고르는 법: 배경이 어두우면 발광판(logo · banner · icon), 밝으면 평면판(light · symbol_flat), 64px 이하면 `qvest_symbol_flat`.

## 구성 — 레퍼런스에서 잰 비율

심볼 치수는 레퍼런스(1254px)의 링 바깥 반지름 R = 307px 단위입니다(링 중심 (627, 470)).

| 요소 | 실측 | 로고 값 |
|---|---|---|
| 유리 띠(바깥 링) | 안쪽 가장자리 222px | 0.723R ~ 1.0R |
| 안쪽 얇은 링 | 190px | 0.619R |
| 꼬리 슬래브 | 양 긴 변 46.1° · 45.9° · 가로 폭 156px · 위 끝 +33px · 아래 끝 +318~320px | **45°** · 가로 폭 0.508R · 위 +0.107R · 아래 +1.04R(양 끝 수평) |
| 빛줄기 | 코어 → 섬광 −26.2° ~ −28.8° | −28.5° |
| 워드마크 | 글자 높이 0.091W · 글자 폭 Q 1.65 · V 1.38 · E 1.16 · S 1.19 · T 1.29(× 글자 높이) · 획 0.17 | 같은 비율로 기하 구성 |

- **QVEST 워드마크는 폰트가 아니라 기하 구성**입니다(`src/geom.py` · 글자 높이 100 단위 격자). Q 의 꼬리는 심볼 꼬리와 같은 45° 평행사변형이고, 볼을 끊는 틈(knockout)도 심볼과 같은 방식입니다 — 심볼과 워드마크가 한 언어를 씁니다.
- 평면판의 틈은 도형 차집합으로 뚫어 실제로 투명합니다(흰색으로 덮은 것이 아님). 어떤 배경 위에 올려도 틈이 배경색으로 보입니다.
- 발광판의 코어 필라멘트 · 띠 안 네트워크 점 · 꼬리 회로선은 시드 고정 난수라 다시 만들어도 같은 그림이 나옵니다.

## 색

| 이름 | HEX | 쓰임 |
|---|---|---|
| Navy | `#0A1F5C` | 평면판 띠 · 워드마크 |
| Brand Blue | `#1F6FFF` | 평면판 꼬리 · 안쪽 링 · 별 · 태그라인 |
| Ice | `#EAF7FF` | 발광판 테두리 · 워드마크 윗면 |
| Cyan | `#7FD2FF` | 발광판 링 · 필라멘트 |
| Glow Blue | `#2F86FF` | 발광 번짐 |
| Background | `#020823` → `#0B2C8C` | 발광판 배경(방사형) |

## 글꼴 · 라이선스

- 태그라인 *The Quant Research System* = **Allison**(Copyright 2020 The Allison Project Authors · SIL Open Font License 1.1) 을 HarfBuzz 로 조판한 뒤 외곽선으로 바꿔 넣었습니다. OFL 은 로고 · 이미지 안 사용과 외곽선 변환을 허용하며, 폰트 파일 자체는 이 폴더에 넣지 않았습니다.
- 워드마크 · 심볼은 자체 기하 구성이라 외부 라이선스가 없습니다.

## 다시 만들기

```bash
# 1) 태그라인 폰트 (npm 레지스트리 · OFL)
mkdir -p /tmp/qvest_fonts && cd /tmp/qvest_fonts && npm pack @fontsource/allison && tar -xzf fontsource-allison-*.tgz
mkdir -p sel && cp package/files/allison-latin-400-normal.woff sel/
# 2) 의존성
pip install fonttools uharfbuzz shapely
# 3) SVG 생성 → PNG 렌더 (Playwright Chromium)
cd 02_Infrastructure/docs/brand
python src/build_logo.py /tmp/qvest_fonts/sel .
node src/render.js qvest_logo.svg        qvest_logo.png        1024 1024 0 2
node src/render.js qvest_icon.svg        qvest_icon.png        1024 1024 0 1
node src/render.js qvest_banner.svg      qvest_banner.png      1280 640  0 1
node src/render.js qvest_logo_light.svg  qvest_logo_light.png  1400 532  1 2
node src/render.js qvest_symbol_flat.svg qvest_symbol_flat.png 512  512  1 2
```

`render.js` 인자 = 입력 SVG · 출력 PNG · 너비 · 높이 · 투명 배경(1) · 배율. 위 명령으로 이 폴더의 PNG 와 픽셀 단위로 같은 결과가 나옵니다(@fontsource/allison 5.3.0 기준).
