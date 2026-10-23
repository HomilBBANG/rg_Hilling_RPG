# 새 세션 인수인계 (2026-10-23)

> 새 Claude Code 세션은 **이 문서를 가장 먼저** 읽는다. 그다음 `docs/GDD.md`(v10.6), `notes/IMPLEMENTATION_ASSUMPTIONS.md`, `README.md` 순서.
> 이 문서는 지금까지 한 세션에서 이어 온 작업(커밋 100여 개)의 상태와 작업 방식을 정리한 것이다.

---

## 1. 저장소와 브랜치

| 항목 | 값 |
|---|---|
| 저장소 | `HomilBBANG/rg_Hilling_RPG` |
| 작업 브랜치 | `claude/gallant-edison-84bkyp` (여기에만 커밋·푸시. PR은 요청이 있을 때만) |
| 게임 이름 | Denial (Godot 프로젝트 이름. GDD에서는 '힐링 RPG') |
| 엔진 | **Godot 4.7.2 stable**, GDScript, Forward+ |
| 사용자 PC | Windows `C:\Game\denial`, Mac `~/Game/denial` — 사용자가 직접 pull해서 Godot 에디터로 열고 `F5`로 실행 |

사용자에게 보고할 때는 마지막에 항상 아래 pull 명령을 붙인다.

**Windows**
```
cd C:\Game\denial
git pull origin claude/gallant-edison-84bkyp
```
**Mac**
```
cd ~/Game/denial
git pull origin claude/gallant-edison-84bkyp
```

---

## 2. 꼭 지킬 작업 규칙 (사용자 지시)

1. **답변은 한국어.** 보고는 무엇을 바꿨는지 → 확인한 방법 → 남은 문제 → pull 명령 순서.
2. **GDD의 [확정] 항목은 사용자가 정하기 전에는 바꾸지 않는다.** [미정]을 임시로 정했거나 사용자가 기획을 바꾸면 `notes/IMPLEMENTATION_ASSUMPTIONS.md`에 기록한다. 사용자 결정은 "사용자 결정/요청", Claude가 정한 건 "[Claude 임시]"로 구분한다.
3. **검증은 정직하게.** 이 작업 환경은 GPU가 없어 xvfb + 소프트웨어 렌더러로 확인한다. 실제 화면 밝기·성능·조작감은 사용자가 직접 확인해야 한다고 밝힌다.
4. **변경은 최소로.** 요청 범위 밖의 리팩터링·기능 추가 금지.
5. **`project.godot`은 커밋하지 않는다**(에디터가 실행할 때마다 바꿈). 커밋 전에 `git checkout project.godot` 또는 `git status`로 확인.
6. **데이터 파일을 고쳤으면 알린다.** `data/dialogues/*.json`·`data/cutscenes/*.json`·`data/monsters.json`·`data/maps/*.json` 등은 사용자가 에디터에서도 고치므로, 내가 고친 파일 목록과 "pull 전에 같은 파일을 고쳤다면 충돌 날 수 있음"을 보고에 적는다.
7. **커밋 전에 headless 에디터 검사**: `Godot --headless --editor --quit --path .` (스크립트 오류·임포트 확인).
8. 커밋 메시지 끝에 저장소 규칙의 공동 작성자 줄을 붙인다. **커밋·문서에 모델 ID를 쓰지 않는다.**
9. 작업이 끝나면 **커밋하고 푸시**한다(작업 트리를 깨끗하게 두기).
10. 사용자는 짧게 요청한다. 수치·세부는 되묻지 말고 임시값으로 만든 뒤 보여 준다. 기획 방향이 갈리는 것만 묻는다.

---

## 3. 작업 환경 준비 (클라우드 컨테이너)

Godot은 저장소에 없다. 새 세션에서 받아 둔다.

```bash
S=<스크래치패드 경로>
mkdir -p $S/godot && cd $S/godot
curl -L -o godot.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip -o godot.zip && chmod +x Godot_v4.7.2-stable_linux.x86_64
GD=$S/godot/Godot_v4.7.2-stable_linux.x86_64

cd /home/user/rg_Hilling_RPG
$GD --headless --editor --quit --path .      # 처음 한 번: 임포트(.godot 캐시 생성) + 스크립트 검사
```

- 화면이 필요한 실행은 `xvfb-run`으로 감싼다(소프트웨어 렌더러).
- 네트워크 정책 때문에 일부 사이트가 막혀 있다(예: `davidhol.land` — 물 셰이더 참고 글). 막히면 사용자에게 환경의 네트워크 설정을 안내한다.

### 자동 투어 (회귀 검사)

게임은 `--tour=<이름>`으로 자동 시나리오를 돌고 `--capture-dir`에 스크린샷을 남긴다. 로그의 `✘`와 `SCRIPT ERROR`가 없어야 통과.

```bash
# regress.sh <투어>  →  "투어 exit=N errors=M"
t=$1; mkdir -p $S/reg/$t
timeout 900 xvfb-run -a -s "-screen 0 1920x1080x24" $GD --audio-driver Dummy --path . \
  --log-file $S/reg/$t.log -- --tour=$t --capture-dir=$S/reg/$t >/dev/null 2>&1
echo "$t exit=$? errors=$(grep -c 'SCRIPT ERROR' $S/reg/$t.log)"; grep -c '✘' $S/reg/$t.log
```

- 동시에 **3개까지만** 병렬(`xargs -P3`). `save`·`preset`은 저장 파일을 쓰므로 **혼자 순서대로**.
- `pkill -f "tour=..."`는 쓰지 말 것 — 명령 줄이 같은 셸까지 죽인다(exit 144). 필요하면 PID로 끈다.
- 투어 목록: `shots styles rawframes walk_d hd sprites night_outline walk p1 p2 gear items shop quest region dungeon rift life craft save run dialogue cutscene world camper king dragonroad dragon wish upgrades drive drivegta preset collide monsterai water beasts catmeet expressions statui invui skillui minimap maps wind catfollow p1input facing interior`
- 바꾼 부분과 관련된 투어 + `p1 p2 region dialogue cutscene save preset` 정도는 늘 돌린다. 마지막 전체 회귀(2026-10-23): 전부 exit=0, 오류 0.
- **이 컨테이너의 소프트웨어 렌더러에서는 구운 스프라이트(주인공·고양이 등)가 연한 실루엣(유령)으로만 찍힌다**(2026-10-23 확인, 이전 커밋도 같음 — 환경 문제. 깊이 쓰기가 안 되어 가려짐 실루엣 패스만 보임). 스프라이트 자체는 `--tour=sprites`가 내보내는 `sheets/*.png`로 확인한다. `--tour=facing` = 주인공 8방향 보행 캡처(등불 끔/켬).
- 투어 코드는 `scripts/core/bootstrap.gd`의 `_tour_*` 함수들. 도움 함수: `_talk_through(picks, prefix)`, `_key`, `_p1_shot`, `_place_player`, `_wait_travel`, `_walk_to`, `_drive_to_gate()`.

### 대화 에디터 자체 검사

```bash
DIALOGUE_EDITOR_SELFTEST=$S/editor xvfb-run -a $GD --editor --path . --audio-driver Dummy
# 로그에 "[editor] done: 0 failed checks"
```

---

## 4. 프로젝트 구조

```
scripts/core/      bootstrap.gd(게임 흐름·지역 이동·저장 시점·자동 투어), game.gd(전역 상태·키·region_locked),
                   save_manager.gd, save_presets.gd(슬롯 3 '1챕터 클리어'), settings.gd, phys_layers.gd(충돌 층)
scripts/world/     visual_lab.gd(지역 씬 조립: 지형·물·바다·NPC·몬스터·이야기 장소), terrain_field.gd, escape_sequence.gd 등
scripts/actors/    prototype_player.gd, slime_monster.gd(몬스터 기본), beast_monster.gd(초원 짐승), dragon_boss.gd,
                   cat_companion.gd, npc.gd, *_rig.gd(절차적 3D 모델 → 8/16방향 픽셀 스프라이트로 굽기)
scripts/game/      player_state.gd(능력치·HP·중독), inventory.gd, item_db.gd, combat.gd, dice.gd, monster_ai.gd(AI 그래프),
                   quest_manager.gd, quest_db.gd, map_db.gd(지도 소유), shop_db.gd, recipe_db.gd, life_db.gd,
                   camper_upgrades.gd, narrative_state.gd(진행 단계 A/B/C·이야기 플래그)
scripts/dialogue/  dialogue_data/runner/context, cutscene_data/runner (에디터와 게임이 같이 씀)
scripts/ui/        game_hud.gd(창들), dialogue_box.gd, dialogue_portrait.gd, minimap.gd, world_map.gd, title_screen.gd, pause_menu.gd
scripts/vehicle/   camper_vehicle.gd(운전), camper_exterior.gd(외장)
scripts/visuals/   카메라·픽셀 렌더·낮밤·스타일 머티리얼
shaders/           terrain/foliage/rock/grass/outline/grade, water_stylized.gdshader(물·바다)
data/              regions/ monsters.json ai/ dialogues/ cutscenes/ quests/ maps/ story.json speakers.json
                   camper_upgrades.json recipes.json life.json
addons/dialogue_editor/  Godot 에디터 플러그인 — 탭: 대화 · 컷씬 · 몬스터 AI · 지도 · 퀘스트
assets/portraits/  대화 초상화(사용자 제공 그림, <화자ID>_<표정>.png)
docs/              GDD.md(v10.6) 와 기획 핸드오프들(이 문서 포함)
notes/             IMPLEMENTATION_ASSUMPTIONS.md(임시값·사용자 결정 기록), DRIVING.md, DIALOGUE_EDITOR.md,
                   VISUAL_DIRECTION.md, SPRITE_PIPELINE.md, PLAYER_MODEL.md
tools/             초상화 배경 제거 등 보조 스크립트
```

- 조작법·해 볼 수 있는 것 전체는 `README.md`의 표에 있다(가장 최신으로 유지 중). 기능을 바꾸면 README 표도 같이 고친다.
- 기본 화면은 카메라 스타일 **D**(디오라마형 3D 픽셀풍), 픽셀 고정 정사영 카메라. 회전 금지.
- 에디터 탭에서 "게임에서 실행"하거나 자동 투어로 시작하면 진행 단계 C(캠핑카+고양이)로 시작한다. 새 게임은 단계 A.

---

## 5. 지금 게임 상태

**챕터 1(튜토리얼 섬) 이야기가 끝까지 만들어져 있다.**

1. 새 게임 → 인트로·오프닝 컷씬 → 혼자 시작(단계 A), 퀘스트 "왕을 만나라"
2. 왕도 → 알현실에서 왕 → "드래곤 토벌" 수락, 잿빛 산길 지도를 받음
3. 초원 길가에서 검은 고양이를 만나는 장면 + 대화 → 동행(단계 B)
4. 고원 북쪽 → 잿빛 산길 → 드래곤의 둥지
5. 드래곤은 무적. **대화로 설득**(틀린 답이면 화가 나 22초 공격 → 진정 뒤 `E`로 다시 대화). 성공하면 비늘 한 장(`dragon_token`)을 남기고 바다 쪽으로 떠남
6. 왕에게 보고 → 소원 "캠핑카" → 성 앞 광장의 의식 → **하늘에서 떨어진 캠핑카에 왕이 깔림**(`cutscene.camper_wish`, 단계 `camper_drop`)
7. 수배 → 퀘스트 "왕도 탈출": 운전석에서 시작, 경비병 6명 추격, 남문에 닿으면 탈출 컷씬(`cutscene.escape`) → 초원 북쪽 길 끝. 왕도·알현실은 잠김(`Game.region_locked()`; 플래그 `story.king_dead`)
8. **섬 전체의 사냥**(2026-10-23 사용자 요청): 남문을 나온 순간부터(`story.escaped`) 모든 NPC(로사·브론·고원 마을·왕도 밖의 모든 주민)가 **곤봉을 들고**(`npc_rig.gd` armed, 시트 `npc_<look>_armed`) 주인공을 쫓아 때린다(`npc.gd` `set_hostile`: 도보 = d20 공격 1d4, 운전 중 = 캠핑카 내구도 −3/1.4초). 거래·대화 불가. `Game.npcs_hostile()`
9. 드래곤의 둥지(캠핑카는 둥지 입구에 세움, `no_vehicle`) → 드래곤이 잠들어 있던 자리의 **포탈**(`visual_lab.gd` `_build_portal`, `story.dragon_left`면 생기고 `story.escaped` 뒤에 열림) → `E` → `cutscene.portal` → 플래그 `story.portal_entered`·`chapter1_done`, 퀘스트 완료 → "챕터 1 끝". 그 뒤 주민들은 무기를 내려놓음(임시 — 챕터 2가 없어 섬을 계속 돌아다닐 수 있게)

이야기 플래그: `story.dragon_met / dragon_angry / dragon_left / king_dead / wanted / escaped / portal_entered / chapter1_done / chapter1_note / camper_received`.
슬롯 3의 준비된 세이브(`save_presets.gd` `_chapter1()`)는 9번이 끝난 상태(둥지의 포탈 옆, 캠핑카는 둥지 입구)다.

### 만들어진 시스템 (요약 — 자세한 건 README)

전투(클릭 1회 공격, 접촉 → d20 명중 → 주사위 피해, 전투 로그 3단계) · 시체 조사 · 중량(착용 장비 포함) · 사망/복귀(체크포인트/캠핑카, 고블린 손실) ·
EXP 수동 레벨업·능력치(확정 버튼·호버 설명)·기본 스킬 · 장비(등 슬롯 포함, 무작위 옵션, 교체 동작) · 소모품·퀵슬롯·마법 ·
상점·대장간 강화·재입고 · 퀘스트(NPC·게시판·현장 사건, 저널, 에디터 퀘스트 탭) · 대화·초상화·표정 · 컷씬 · 지역 이동(초원·고원·왕도·잿빛 산길·둥지·알현실) ·
고정 던전(이끼 동굴)·랜덤 던전(변덕의 미궁) · 채집·낚시·요리·제작 · 캠핑카(운전 GTA식, 실내·창고·수면, 연료·내구도·수리, 개조 6분야·마법 방·소품 배치, 주차 반응, 들이받기) ·
고양이(만남 장면, 추종, 실내 쓰다듬기·간식 호감도) · 지도 수집(이어진 지도·세계 지도·핀·빠른 이동)·미니맵 · 저장 3슬롯·타이틀·설정 ·
몬스터 AI 그래프(슬라임 비선공, 초원 짐승 3종, 중독) · 물·바다 셰이더.

---

## 6. 사용자가 정한 것 (GDD v10.6에 반영됨)

| 주제 | 결정 |
|---|---|
| 이야기 | 드래곤은 싸워서 못 이김 → 대화로 설득해 내보냄, 다른 대륙에서 재회. 소원 캠핑카가 떨어져 왕 사망 → 수배 → 탈출. 탈출 뒤 왕도 못 감. **탈출 뒤 섬의 NPC 전체가 무기를 들고 공격, 캠핑카로 드래곤의 둥지까지 달려 드래곤이 떠난 자리의 포탈로 들어가면 챕터 1 끝** (2026-10-23). 지금 맵 = 챕터 1 튜토리얼 섬(오래 머물지 않음), 챕터 2 = 다른 대륙 |
| 지도 | 처음엔 없음. 사거나·받거나·주워야 그 지역이 공개(가 보는 것만으로는 안 열림). 이어진 평면 지도, M = 내 위치 중심 확대, 세계 지도 = 지형·이름만 + 지도 없는 곳은 구름 |
| 몬스터 | 모든 슬라임 비선공, 비선공은 같은 종이 불러도 안 끼어듦. AI는 데이터 그래프(에디터 탭). 초원 짐승: 식충식물(독액)·늑대(물기·할퀴기)·고슴도치(가시 돌진) |
| 인벤토리 | 착용 장비 무게 포함. 소지품+장비 한 창(탭), 등 슬롯. 스킬 창 K. 능력치 확정 버튼·호버 설명 |
| 미니맵 | 오른쪽 위, NPC 노랑, 캠핑카 파랑, 고양이 표시 안 함 |
| 대화 | 주인공 왼쪽·상대 오른쪽, 말 안 하는 쪽 50%, 그림은 사용자 제공, 대화 중 HUD 숨김 |
| 운전 | GTA식(W 가속, S 제동→후진, A/D는 굴러갈 때만, 후진 시 실제 차 방향). 몬스터 들이받기 가능(내구도 크게 깎임) |
| 충돌 | 사람·몬스터·고양이·큰 돌·나무·건물·캠핑카는 통과 불가 |
| 저장 | 슬롯 3개, 슬롯 하나 = 캐릭터 하나, 타이틀 메뉴(새 게임·불러오기·설정·종료) |
| 그림 | 물·바다·배경은 레퍼런스(청록 픽셀 물, 둘레 바다). 땅·바위만 레퍼런스 색, **나무·풀은 그대로**. **밀도**(2026-10-23, 돌 원형 극장 레퍼런스): 외곽선은 검정이 아니라 주변색의 진한 톤, 윗모서리 하이라이트, 접지 그림자, 두세 톤 디더 바닥 — `notes/VISUAL_DIRECTION.md` 맨 위 절 |

[Claude 임시]로 정한 것(드래곤 대화 선택지, 의식 장소, 탈출 규칙, 지도 가격·배치, 짐승 수치·배치, 중독 규칙 등)은 `notes/IMPLEMENTATION_ASSUMPTIONS.md` 각 절에 있다. 사용자가 바꾸라고 하면 그 표를 고친다.

---

## 7. 알려진 한계 · 남은 일

**아직 없는 것**
- 챕터 2(다른 대륙) 전체 — 지역·이야기·건너가는 방법 모두 [미정]. 사용자가 정하기 전에 만들지 말 것
- 마법 부여(15.3), 고유 장비, 손에 드는 횃불·별똥별 광원(10.3), 야행성 몬스터(10.2), NPC 제작 의뢰(15.4)
- 사운드 전부, 아이템 그림 아이콘(지금은 이름 글자), 등 슬롯에 맞는 장비 아이템, 해독 아이템
- 대화 에디터의 내보내기·로컬라이제이션·일괄 치환·대화 재사용 노드
- 퀘스트 탭의 새 목표 종류(조사·전달·생활·캠핑카·시간 조건·호위) — 지금은 모으기·처치·횟수·플래그 4종

**제안했지만 사용자가 아직 고르지 않은 것** (2026-10-23, 퀘스트 밀도 질문에 대한 답)
- 퀘스트 에디터 탭(**2026-10-23 완료** — `addons/dialogue_editor/quest_editor_panel.gd`, 목표 4종·보상·결과 분기·시작 조건·검증·쓰이는 곳) → 새 목표 종류(조사·전달·생활·캠핑카·시간 조건, 그다음 호위) → 지역 연작·NPC 개인사·현장 사건 묶음.
- 그 뒤 사용자가 "챕터 1은 오래 머물지 않는 튜토리얼"이라고 했으므로, 밀도 작업은 **챕터 2 대륙에 쓰는 것**이 맞다. 챕터 1에 퀘스트를 많이 늘리기 전에 확인할 것.

**검증상 주의**
- 모든 시각 확인은 소프트웨어 렌더러 스크린샷 기준. 물 셰이더(깊이·화면 텍스처 사용)는 실제 GPU에서 색이 조금 다를 수 있다.
- 운전 조작감·전투 난이도는 투어 수치로만 확인했다.

---

## 8. 자주 만지는 곳 빠른 안내

| 하고 싶은 것 | 볼 곳 |
|---|---|
| 지역에 몬스터·장소 추가 | `data/regions/<지역>.json` (+ `visual_lab.gd`가 읽음) |
| 몬스터 수치·전리품·AI | `data/monsters.json`, `data/ai/*.json`, 에디터 `몬스터 AI` 탭 |
| 대사·선택지 | `data/dialogues/*.json`, 에디터 `대화` 탭. 대화 액션은 `dialogue_data.gd`의 허용 목록 + `game_dialogue_context.gd` |
| 컷씬 | `data/cutscenes/*.json`, 에디터 `컷씬` 탭. 단계 종류는 `cutscene_data.gd` / `cutscene_runner.gd` |
| 이야기 장소·인물 배치 | `data/story.json` (wish_ceremony, escape_guards, 새 게임 컷씬 순서) |
| 퀘스트 | `data/quests/*.json`, 에디터 `퀘스트` 탭(`quest_editor_panel.gd`), 검증·저장 규칙은 `quest_db.gd`, 진행은 `quest_manager.gd` |
| 지도 표시물·얻는 곳 | `data/maps/*.json`, 에디터 `지도` 탭, `map_db.gd` |
| 화자·초상화 | `data/speakers.json`, `assets/portraits/` |
| 아이템 | `scripts/game/item_db.gd` |
| 키 바인딩 | `scripts/core/game.gd` `ACTIONS` |
| 저장 항목 추가 | `save_manager.gd` (옛 저장에 없는 항목은 기본값으로 채우기) + `save_presets.gd` |
