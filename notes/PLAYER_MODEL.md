# 주인공 모델 — Meshy AI 모델 적용

사용자가 준 Meshy AI 모델(`Meshy_AI__1021103547_texture_1.glb`)을 주인공으로 씁니다. 원본에는 뼈대가 없어서,
Blender에서 게임용으로 다듬고 뼈대를 넣은 뒤 기존 `PlayerRig`(걷기·공격·사용 동작, 장비 표시, 스프라이트 베이크)에 연결했습니다.
지난 원형들(v1 절차적 모델, v2·v3 Blender 원형)은 이 모델로 대체되었습니다.

## 파일

| 파일 | 내용 |
|---|---|
| `art_src/player_meshy/meshy_source.glb` | 사용자가 준 원본 그대로 (정적 메시, 삼각형 47만 개, 2K PBR 텍스처 3장, 뼈대 없음) |
| `art_src/player_meshy/player.blend` | 손질 + 뼈대 + 웨이트까지 들어간 Blender 파일 |
| `art_src/player_meshy/renders/rig_test_*.png` | 웨이트 확인용 기본 자세 / 시험 포즈(칼팔 앞으로 75°, 걸음) 렌더 |
| `assets/characters/player/player.glb` | 게임이 읽는 모델 (삼각형 1만 6천 개, 기본색 텍스처 1024 px, 뼈 16개) |
| `tools/blender/player_meshy_prepare.py` | 원본 → 게임 모델 변환 스크립트 |
| `scripts/actors/player_rig.gd` | 뼈대를 코드로 움직이는 주인공 리그 |

원본 모델을 바꿨을 때 다시 만드는 명령 (프로젝트 폴더에서):

```bat
blender -b -P tools/blender/player_meshy_prepare.py -- art_src/player_meshy/meshy_source.glb art_src/player_meshy assets/characters/player/player.glb
:: Blender가 없으면: pip install bpy  후  python tools/blender/player_meshy_prepare.py (같은 인수 3개)
```

이 작업 환경에서는 PyPI의 `bpy` 5.2.2(Blender를 파이썬 모듈로 만든 공식 패키지)로 실행했습니다.

## 변환 단계

1. **크기·위치**: 키를 1.74 m(이전 게임 모델과 같은 키)로 맞추고, 발바닥을 0에 두고 가운데로 옮김. 방향은 그대로(정면 = glTF +Z)
2. **정점 용접**: 원본은 UV 경계마다 정점이 갈라져 있어서, 그대로 뼈대를 붙이면 움직일 때 옷·얼굴이 찢어짐. 같은 자리 정점을 합침(UV는 면 모서리 단위라 유지됨)
3. **삼각형 줄이기**: 47만 → 1만 6천 개. 스프라이트 베이커가 25동작 × 8방향 = 200벌을 한 번에 그리기 때문
4. **재질**: 기본색 텍스처만 1024 px로 남기고, 금속·거칠기·노멀 맵은 버림. 게임에서는 다른 모델과 같은 툰 셰이딩(`ProtoMesh` 2단 명암, 스페큘러 없음)으로 그림
5. **뼈대**: hips · spine · chest · head · upper_arm/forearm/hand (좌우) · thigh/shin/foot (좌우). 관절 위치는 원본 메시를 높이별로 잘라서 잼
6. **웨이트**: Blender 자동 웨이트(열 확산 방식)

## 게임 쪽 연결 (`PlayerRig`)

- 기존 리그와 같은 함수(`pose`, `pose_action`, `pose_column`, `set_gear`, `set_lantern`, `lantern_anchor`)를 그대로 두어서, 플레이어·스프라이트 베이커 코드는 바꾸지 않았습니다.
- 예전 팔다리 노드 대신 같은 각도로 뼈를 돌립니다. 회전은 리그 축 기준이고, 아래팔은 위팔을 따라갑니다.
- 걸음에는 뒤로 빠진 다리의 무릎 굽힘을 더했습니다. 대기 자세에서는 팔꿈치를 덜 굽혀 큰 주먹이 배 옆에 자연스럽게 내려오게 했습니다.
- 칼은 오른손 뼈, 방패는 왼쪽 아래팔 뼈, 물약·빵은 왼손 뼈, 등불은 엉덩이 뼈에 붙습니다(왼쪽 허리, 내린 팔 조금 뒤).
- 스프라이트 베이커는 각 사본을 트리에 넣기 전에 포즈를 잡는데, Skeleton3D는 트리 밖에서 바꾼 포즈를 스킨에 반영하지 않습니다. 그래서 `_ready()`에서 뿌리 뼈를 한 번 건드려 다시 계산하게 했습니다. 이게 없으면 시트의 모든 칸이 기본 자세로 구워집니다.

## 확인한 것 (xvfb 소프트웨어 렌더러)

- `--tour=sprites`: 8방향 × 21칸 시트에 대기·걷기 8칸·공격 5칸·마시기·먹기·시전이 모두 다른 자세로 구워짐. 낮·밤·근접·실내 캡처 정상
- 기존 투어 전체 회귀 확인 (결과는 커밋 메시지·보고에 기록)

## 알려진 한계

- 웨이트가 자동이라, 팔을 크게 드는 동작(공격)에서 셔츠 앞자락이 팔 쪽으로 조금 끌려갑니다. 게임 화면 크기에서는 거의 보이지 않습니다.
- 손가락·얼굴 표정 뼈는 없습니다(주먹 쥔 손 그대로).
- 체크무늬는 텍스처를 줄여서 게임 크기에서 조금 자글자글합니다.
