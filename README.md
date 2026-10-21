# Denial — P1 코어 플레이 프로토타입

힐링 판타지 RPG(가칭, Godot 프로젝트명 **Denial**)의 Godot 프로젝트입니다. P0(고정 탑다운 + 3D 픽셀화 렌더,
데드셀풍 D 스타일) 위에 **P1 코어 플레이 루프**를 올렸습니다: 야외 지역 1곳에서 전투 → 시체 조사 → 중량 인벤토리 →
캠핑카 운전·실내·창고·수면 → 사망/복귀 → 검은 고양이 동행·교감. 기획 기준은 [`docs/GDD.md`](docs/GDD.md) **v10.2**와
[`docs/CAT_COMPANION_HANDOFF.md`](docs/CAT_COMPANION_HANDOFF.md)이며, 미정 사항을 임시로 정한 값은
[`notes/IMPLEMENTATION_ASSUMPTIONS.md`](notes/IMPLEMENTATION_ASSUMPTIONS.md)에 모두 적었습니다(정식 규칙 아님).

![P1 전투 · 로그 3단계](captures/p1/p1_04_combat_log3.png)

## P1에서 해 볼 수 있는 것

| 흐름 | 방법 |
|---|---|
| 전투 | 마우스 방향 클릭 1회 = 1회 공격(SP 4). 무기 영역이 닿아야 판정 → d20 명중 → 별도 치명 굴림 → 1d4 피해. 풀밭 슬라임(캠프 동쪽, 비선공)·숲 슬라임(북동쪽 숲, 선공). 한 마리를 치면 근처 같은 종이 합류 |
| 전투 로그 | 좌하단. `G`(또는 클릭)로 1 아이콘 → 2 한 줄 → 3 상세(주사위·계산식) |
| 시체 조사 | 처치한 자리의 시체 앞에서 `E` → 원하는 것만 "가져가기"/"모두"/"전부 가져가기". 게임 시간 60분 뒤 사라짐 |
| 중량 | `Tab` 소지품(게임은 계속 진행). 30kg 초과 시 느려지고 45kg을 넘기는 획득은 거부. 캠프의 **보급 상자**(철광석)로 시험 |
| 캠핑카 | 문 앞 `E` 실내, 운전석(앞바퀴 옆) `E` 운전: **차 머리 기준: `W` 전진, `S` 브레이크→후진, `A`/`D` 머리 좌/우**(키를 놓으면 정지), 멈춘 뒤 `E` 하차. `F` 외부 라이트 ([운전 조작 개선](notes/DRIVING.md)) |
| 실내 | 문 매트 `E` 밖으로, 오른쪽 아래 선반 `E` **창고**(개별/모두/소지품 전체 옮기기), 간이침대 `E` **수면**(1~12시간, HP 10%) |
| 고양이 | 실내에 항상 있음: `E` 쓰다듬기, `R` 간식(소지품의 고양이 간식 1개 → 호감도 +10). 창고에 간식 6개가 있음 |
| 사망/복귀 | 캠핑카 보유(단계 C) → 실내 간이침대 옆에서 기상. 미보유(A/B) → 가장 가까운 안전 체크포인트(캠프 모닥불·갈림길 돌무지·호숫가 쉼터). B에서는 고양이가 곁을 돌다 앉음. 가방의 일부는 고블린이 가져가고 나머지는 쓰러진 자리의 "짐 꾸러미"로 남음 |
| 소모품·퀵슬롯 (P2-3) | `1`~`4` 소모품 퀵슬롯, `5`~`8` 스킬·마법 퀵슬롯. 물약은 0.8초 마시는 동안 천천히 이동, 빵·통조림은 멈춰서 먹음 — 동작이 끝나야 효과, **사용 중 맞으면 중단되고 아이템은 남음**. Tab에서 사용·등록, 보급 상자의 '마법서: 작은 치유'를 읽으면 마법을 배워 5번 칸에 등록(MP 8, 재사용 3초) |
| 장비 (P2-2) | `Tab`에서 장착/해제: 머리·몸통·장갑·신발·목걸이·반지 2·허리띠·주무기/보조 손. 양손 무기(불꽃 장검)는 보조 손을 비움. 교체는 0.6초 동작 뒤 적용(그동안 공격 불가). 방어구가 받는 피해를 줄이고, 일부 드롭 장비에는 무작위 옵션. 등불은 등불 허리띠가 있어야 켤 수 있음. 시험용 장비: 캠핑카 창고·캠프 보급 상자 |
| 성장 (P2-1) | 몬스터 처치 시 일반 EXP. **자동 레벨업 없음**: `C` 능력치 창에서 직접 레벨업(능력치 포인트 +1) → 7종 능력치에 투자, 또는 EXP로 기본 스킬(명중 훈련·급소 노리기·짐 꾸리기 요령) 습득. HUD에 "레벨업 가능" 표시 |
| 진행 단계 | `F9`: A 혼자 → B 고양이 동행 → C 캠핑카+고양이(시작). A에서는 길가의 고양이에게 다가가면 따라오기 시작(→B). `F8` 전체 회복 |

> **비주얼 방향 수정(디오라마형 3D 픽셀풍)과 카메라 A/B/C/D 비교 결과:** [`notes/VISUAL_DIRECTION.md`](notes/VISUAL_DIRECTION.md)
> **3D 모델 → 렌더 → 픽셀 스프라이트 파이프라인(캐릭터·몬스터·캠핑카):** [`notes/SPRITE_PIPELINE.md`](notes/SPRITE_PIPELINE.md)

## 요구 사항

| 항목 | 내용 |
|---|---|
| 엔진 | **Godot 4.7.x 표준판**(.NET 판 불필요). 4.7.2-stable로 작성·검증 |
| 렌더러 | Forward+ (기본). Vulkan을 지원하는 GPU 필요 |
| 저사양 대안 | Compatibility(OpenGL) 렌더러로도 실행 확인됨 (아래 "실행" 참고) |
| 화면 | 기본 창/출력 **1920×1080**. 화면이 작으면 F11 전체 화면 또는 창 크기 조절(비정수 배율로 늘어남) |
| 외부 에셋 | 없음. 모든 모델·재질·셰이더를 코드로 생성. 폰트만 포함(나눔고딕, SIL OFL 1.1, `assets/fonts/LICENSE_NanumGothic.txt`) |

## 설치 (`C:/Game/denial`)

이 저장소의 **루트가 곧 Godot 프로젝트 폴더**입니다(`project.godot`가 루트에 있음).

```bat
cd C:\Game
:: 기존에 에디터로 만든 빈 denial 프로젝트가 있다면 먼저 다른 이름으로 옮겨 두세요.
ren denial denial_old
git clone -b claude/gallant-edison-84bkyp https://github.com/HomilBBANG/rg_Hilling_RPG.git denial
```

그다음 Godot 프로젝트 매니저 → **가져오기(Import)** → `C:/Game/denial/project.godot`을 선택합니다.
처음 열 때 `.godot/` 캐시가 자동 생성됩니다(커밋하지 않음).

## 실행

- **F5**: 메인 씬 `scenes/bootstrap.tscn` 실행 (야외 랩에서 시작).
- **F6**: `scenes/visual_lab.tscn` 또는 `scenes/camper_interior_lab.tscn`을 연 상태에서 실행하면,
  픽셀 렌더 파이프라인과 HUD를 갖춘 bootstrap으로 자동 전환되며 해당 씬에서 시작합니다.
- GPU가 Vulkan을 지원하지 않으면: `Godot.exe --path C:/Game/denial --rendering-method gl_compatibility`

## 조작 (프로토타입 임시 키 — 최종 게임 키가 아님)

| 키 | 기능 |
|---|---|
| `WASD` / 방향키 | 이동 (걷기 SP 0, `Shift` 달리기 SP 8/초) |
| 마우스 왼쪽 클릭 | 기본 공격 1회 (마우스 방향, 누르고 있어도 반복 안 함, SP 4) |
| `E` / `R` | 조사·상호작용(시체·상자·짐 꾸러미·문·운전석·창고·침대·고양이) / 고양이 간식 |
| `Tab` | 소지품 (열어도 게임은 멈추지 않음) |
| `C` | 능력치 창: 일반 EXP로 레벨업(능력치 포인트 +1)·능력치 투자·기본 스킬 습득 (자동 레벨업 없음) |
| `G` | 전투 로그 1 → 2 → 3단계 |
| `1`~`4` / `5`~`8` | 소모품 퀵슬롯 / 스킬·마법 퀵슬롯 |
| `F9` / `F8` / `F10` | 진행 단계 A/B/C / 전체 회복 / 디버그 정보(렌더 상태 등) |
| `F` | 캠핑카 외부 라이트 ON/OFF (캠핑카 7.5m 이내에서만) |
| `V` | **카메라 스타일 A(기존 기능형) → B(개선된 탑다운) → C(기울어진 디오라마) → D(데드셀풍 픽셀)**. 시작은 D |
| `B` | 바람 ON/OFF (풀·수풀·나무 흔들림, 모닥불·연기·불씨·빨래·깃발·나뭇잎, 기본 ON) |
| `O` | 픽셀 외곽선 ON/OFF (**기본 ON**: 실루엣 1픽셀 짙은 선, Forward+ 전용) |
| `Z` | 스프라이트 파이프라인 ON/OFF — 캐릭터·슬라임·캠핑카를 3D 모델에서 구운 픽셀 스프라이트로 그릴지, 실시간 3D로 그릴지 |
| `F1` / `F2` / `F3` / `F4` | **PXL-COARSE 320×180 (×6)** / **PXL-MID 480×270 (×4)** / **PXL-SOFT 640×360 (×3, 기본)** / **3D-NATIVE 1920×1080(픽셀화 OFF)** |
| `M` | 픽셀화 파이프라인 전환: M1 SubViewport 확대 ↔ M2 3D 해상도 스케일링(nearest) |
| `P` | 모드 3: 색 단계 제한 + 4×4 디더 ON/OFF (색보정 셰이더 안의 옵션) |
| `N` | 낮(12:00) ↔ 밤(22:00) |
| `T` | 게임 시계 진행/정지 (현실 1초 = 게임 1분) |
| `L` | 개인 등불(허리띠) ON/OFF |
| `I` | 캠핑카 실내 ↔ 야외 씬 전환 (디버그 순간이동, 캠핑카 보유 시) |
| `K` | 픽셀 스냅 카메라 ON/OFF (떨림 비교용) |
| `F7` | 직교 ↔ 원근 투영 비교 (카메라 **회전은 없음**) |
| `X` | 가림 보조: 실루엣 → 수관 디더 투명화 → 끔 |
| `-` / `=` | 카메라 규모(화면 세로 9~22m) |
| `F12` | 스크린샷 → `user://captures` (Windows: `%APPDATA%\Godot\app_userdata\Denial\captures`) |
| `F11` | 전체 화면 전환 |
| `ESC` | 일시정지 |
| `H` | 도움말 패널 표시/숨김 |

## 렌더 구조 (P1 재사용 대상)

```
bootstrap (Node)
├─ PixelRenderController (Control)        scripts/visuals/pixel_render_controller.gd
│   ├─ SubViewport  ← 3D 월드(야외/실내)가 여기서 저해상도로 렌더
│   └─ TextureRect  ← nearest 필터, 정수 배율 확대, 서브텍셀 오프셋
└─ CanvasLayer → VisualHud                ← 고해상도 UI (픽셀화 영향 없음)
```

- **픽셀 스냅 카메라** (`scripts/visuals/topdown_camera.gd`): 고정 각도(피치 50°) 직교 카메라가 렌더 텍셀
  격자에 위치를 맞추고, 남는 서브텍셀 오차는 TextureRect를 화면 픽셀 단위로 밀어 보정합니다(1텍셀 여백 렌더).
  배경은 떨리지 않고 스크롤은 부드럽게 유지하는 표준 기법입니다.
- **M2**는 Godot 4.7의 `Viewport.scaling_3d_mode = SCALING_3D_MODE_NEAREST`를 사용합니다.
- **픽셀 외곽선** (`shaders/pixel_outline_post.gdshader`): 카메라에 붙은 전체 화면 쿼드가 저해상도 렌더의 깊이·노멀 버퍼를
  읽어, 앞 물체의 경계 텍셀을 어둡게(색 있는 외곽선), 단단한 소품의 볼록 모서리를 밝게 칠합니다. 지형·풀(roughness 1.0)과
  잎·바위(0.93)는 하이라이트에서 제외합니다.
- **색보정** (`shaders/pixel_grade.gdshader`): 업스케일 TextureRect에서 텍셀 단위로 스플릿 토닝·채도·비네트(+선택 디더).
- **스타일라이즈드 재질** (`scripts/world/stylized_materials.gd`): 지형·잎·바위·풀 셰이더와 절차적 노이즈 텍스처.
- 낮/밤: `scripts/visuals/day_night_controller.gd`, 오토로드 `Game`(`scripts/core/game.gd`)이 시계·라이트 상태 보관.
- 가림 실루엣: `shaders/occluded_silhouette.gdshader` (`depth_test_inverted` + 자기 가림 방지 바이어스).

P1에서는 `PixelRenderController`, `TopdownCamera`, `DayNightController`, 실루엣 셰이더를 그대로 가져가고
`visual_lab.gd`/`camper_interior_lab.gd` 같은 월드 스크립트만 교체하면 됩니다.

### 폴더

```
project.godot
scenes/        bootstrap.tscn, visual_lab.tscn, camper_interior_lab.tscn (루트 노드 + 스크립트만)
scripts/core/      game.gd(오토로드), bootstrap.gd, visual_hud.gd
scripts/visuals/   pixel_render_controller.gd, topdown_camera.gd, day_night_controller.gd
scripts/world/     visual_lab.gd, camper_interior_lab.gd, terrain_field.gd, nature_props.gd, proto_mesh.gd,
                   organic_mesh.gd, stylized_materials.gd, ground_cover.gd, camp_props.gd, campfire_flame.gd
scripts/actors/    prototype_player.gd, player_rig.gd, slime_monster.gd(P1 AI), slime_visual.gd, slime_rig.gd,
                   cat_companion.gd, cat_rig.gd (검은 고양이)
scripts/game/      dice.gd, combat.gd, player_state.gd, inventory.gd, item_db.gd, combat_log.gd (P1 규칙·데이터)
scripts/ui/        game_hud.gd (HP/SP/MP, 전투 로그, 조사·소지품·창고·수면 패널)
scripts/world/     interact_point.gd, loot_container.gd (상호작용·시체/상자/짐 꾸러미)
scripts/visuals/   sprite_baker.gd, sprite_sheet.gd, baked_sprite.gd (스프라이트 파이프라인)
scripts/vehicle/   camper_exterior.gd, camper_vehicle.gd(운전), prototype_camper_lights.gd
shaders/           terrain/foliage/rock_stylized, grass_blades, camper_paint, pixel_outline_post,
                   pixel_grade, occluded_silhouette (+ stylized_common.gdshaderinc)
captures/visual_direction/  카메라 A/B/C 비교 (디오라마 방향)
captures/p0_baseline/       P0 테스트 장면 6종 + 렌더 모드 비교 + 이동 영상
captures/sprite_pipeline/   구운 스프라이트 시트(sheets/) + 베이크 vs 실시간 3D 비교
captures/p1/                P1 흐름 검증 캡처 19장 (--tour=p1)
captures/p2/                P2-1 성장(레벨업·능력치·기본 스킬) 캡처 + 철검 스프라이트 시트 (--tour=p2)
notes/             VISUAL_DIRECTION.md, VISUAL_COMPARISON.md, IMPLEMENTATION_ASSUMPTIONS.md
docs/              GDD.md(v10.2), CAT_COMPANION_HANDOFF.md, GRAPHICS_PROTOTYPE.md, CLAUDE_CODE_HANDOFF.md
```

`GRAPHICS_PROTOTYPE.md` 6장의 `actors/*.tscn`, `props/*.tscn`은 별도 씬 파일로 만들지 않고, 같은 역할을
스크립트 클래스(`PrototypePlayer`, `SlimeVisual`, `CamperExterior`, `NatureProps`)로 절차 생성했습니다.

## 캡처 재생성

모든 `captures/` 파일은 아래 자동 투어로 생성되었습니다(같은 카메라 위치에서 모드만 바꿔 촬영).

```bat
:: P1 흐름 검증 19장 (상자·과적·전투·시체·사망→실내·창고·고양이·수면·짐 꾸러미·운전·고양이 합류·체크포인트)
Godot.exe --path C:/Game/denial -- --tour=p1 --capture-dir=C:/Game/denial/captures/p1
:: 같은 흐름을 실제 키 입력 이벤트로 점검 (콘솔에 [input] 결과 출력)
Godot.exe --path C:/Game/denial -- --tour=p1input
:: 카메라 A/B/C 비교 8장
Godot.exe --path C:/Game/denial -- --tour=styles --capture-dir=C:/Game/denial/captures/visual_direction
:: P0 스크린샷 18장
Godot.exe --path C:/Game/denial -- --tour=shots --capture-dir=C:/Game/denial/captures/p0_baseline
:: 14초 이동 영상 (Movie Maker, AVI → 필요 시 ffmpeg로 MP4 변환)
Godot.exe --path C:/Game/denial --write-movie C:/Game/walk.avi --fixed-fps 30 -- --tour=walk
```

## 알려진 문제 / 미검증

- **실제 GPU에서 실행하지 않았습니다.** 검증은 클라우드 컨테이너의 소프트웨어 렌더러(Mesa llvmpipe, Vulkan
  Forward+ 및 OpenGL Compatibility)에서 했습니다. FPS 수치(8~30)는 소프트웨어 렌더 기준이라 의미가 없습니다.
- 픽셀 외곽선은 Forward+ 전용이며 Compatibility에서는 자동으로 꺼집니다(디오라마 버전은 Compatibility에서 미검증).
- 이동 중 픽셀 떨림은 녹화 영상의 프레임으로만 확인했습니다. **실시간 체감은 직접 실행해서 판단**해 주세요.
- Forward+와 Compatibility의 밤 밝기가 다릅니다(Compatibility가 더 밝고 헤드라이트 빔이 더 뚜렷함).
- 창 크기를 1920×1080이 아닌 크기로 바꾸면 `canvas_items` 스트레치 때문에 픽셀이 비정수 배율로 늘어납니다.
- 1080p 전환 이전에 찍은 `captures/` 이미지(p0_baseline, visual_direction, sprite_pipeline)는 1280×720 기준입니다. 최신 화면은 `captures/hd_1080p/`.
- **P1 스프라이트 베이크 시간**: 캠핑카를 16방향으로 구우면서 첫 로딩·렌더 프리셋(F1~F4) 변경 시 소프트웨어
  렌더러에서 약 16초 걸렸습니다(GPU에서는 훨씬 짧을 것으로 예상, 미검증). 그동안 3D 모델이 그대로 보이며,
  한 번 구운 시트는 실내/야외 전환 때 재사용합니다.
- P1 흐름은 자동 투어(직접 호출 + 시뮬레이션 키 입력)로만 확인했습니다. 마우스 조준 감각, 전투 난이도, 운전 조작감은
  직접 플레이해서 판단해 주세요. 주인공에게 무기 모델은 아직 없습니다(외형 변경은 승인 후 진행).
- 자세한 시각 평가와 P0 통과/보류 체크리스트: [`notes/VISUAL_COMPARISON.md`](notes/VISUAL_COMPARISON.md)
- 임시로 정한 값과 미정 사항 처리: [`notes/IMPLEMENTATION_ASSUMPTIONS.md`](notes/IMPLEMENTATION_ASSUMPTIONS.md)
