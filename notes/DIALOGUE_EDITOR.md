# 대화 에디터 (Dialogue Editor) — 사용법과 구조

`docs/DIALOGUE_EDITOR_HANDOFF.md`(v10.5)에 따라 만든 **노드형 대화 에디터**입니다. 대사·선택지·조건·액션·컷씬
호출을 코드 없이 작성하고, 에디터 안에서 미리보기·검증하고, 실제 게임에서 바로 실행할 수 있습니다.
UI 형태(Godot `EditorPlugin` + `GraphEdit`), 데이터 포맷, 단축키는 핸드오프의 **제안안을 구현한 개발용 초기안**이며
사용자 승인 전입니다.

![대화 에디터](../captures/dialogue_editor/editor_03_preview_choice.png)

## 여는 법

1. Godot 4.7 에디터로 프로젝트를 엽니다: `Godot.exe --path C:/Game/denial -e` (또는 프로젝트 매니저에서 열기).
2. 화면 위쪽 **2D · 3D · Script · Game … 옆의 `Dialogue`** 탭을 누릅니다.
   - 탭이 안 보이면: 프로젝트 → 프로젝트 설정 → 플러그인 → **Dialogue Editor** 사용 체크.

## 작업 흐름 (핸드오프 5장)

| 단계 | 방법 |
|---|---|
| 새 대화 / 열기 | `새 대화` → `dialogue_id`(예: `dialogue.npc.rosa.rain`)와 제목 입력. 왼쪽 목록에서 클릭해 열기. 검색창은 ID·제목·태그·화자 이름·**대사 본문**까지 찾음. 목록 아래에 화자별 대화 수 |
| 노드 추가 | 위쪽 `대사 / 선택지 / 조건 / 액션 / 컷씬 호출 / 종료` 버튼 — **선택한 노드의 빈 출력에 자동으로 이어 붙음**. 그래프 오른쪽 클릭, 출력 점에서 빈 곳으로 선을 끌어 놓아도 추가 |
| 연결 | 출력 점(오른쪽) → 입력 점(왼쪽)으로 끌기. 출력 하나에는 대상 하나(다시 연결하면 교체). 끊기: 입력 쪽 선 끝을 오른쪽 클릭으로 끌기 |
| 편집 | 노드를 클릭하면 **오른쪽 속성 패널**에서 편집(그래프에는 1~2줄 미리보기만). 대사는 여러 줄 입력·붙여넣기 가능, 화자·퀘스트·아이템·컷씬은 목록에서 고름(오타 방지). 노드 ID는 바꿔도 연결 유지 |
| 미리보기 | `▶ 미리보기`(처음부터) / `▶ 선택 노드부터`. 아래 미리보기 탭에서 대사 진행·선택지 클릭, 현재 노드는 그래프에서 **노란색으로 강조**, 지나온 경로와 액션 기록 표시. 오른쪽 **테스트 상태**(퀘스트 상태·플래그·골드·소지품)를 바꿔 조건별 결과 확인 — 실게임·세이브에는 영향 없음 |
| 검증 | `검증` → 검증 탭. 항목을 클릭하면 해당 노드로 이동. 오류가 있는 노드는 제목에 ⚠ |
| 저장 | `저장` / **Ctrl+S** → `res://data/dialogues/<dialogue_id>.json`. 오류가 있으면 확인 후 저장 가능(작성 중 초안). 덮어쓰기 전 이전 내용을 `user://dialogue_backups/<id>/`에 백업(최근 20개), 파일이 에디터 밖에서 바뀌었으면 덮어쓰기 전에 물어봄 |
| 게임에서 실행 | `▶ 게임에서 실행` → 저장 후 게임을 켜고, 로딩이 끝나면 그 대화를 **실제 대화창·실제 게임 상태**로 재생 |
| NPC에 연결 | `data/speakers.json`의 `"talk"` 값을 대화 ID로 바꾸면 그 NPC에게 `R`로 말을 걸 때 열림 — **GDScript 수정 불필요** |

단축키: Ctrl+S 저장 · Ctrl+Z / Ctrl+Y(또는 Ctrl+Shift+Z) 실행 취소·다시(입력 칸 밖에서) · Delete 노드 삭제 ·
Ctrl+C / Ctrl+V 복사·붙여넣기(내부 연결 유지, 새 ID) · Ctrl+D 복제 · `정렬` 자동 배치 · 드래그로 다중 선택.

## 노드 7종

| 노드 | 하는 일 | 출력 |
|---|---|---|
| 시작 | 진입점, 그래프당 하나(지울 수 없음) | 다음 |
| 대사 | 화자 + 대사 (게임에서 자동 줄바꿈) | 다음 |
| 선택지 | 선택지별 분기. 선택지마다 "조건이 맞을 때만 보이기" 가능 | 선택지마다 하나 |
| 조건 | 상태를 **조회만** 해서 분기: 플래그 / 퀘스트 상태 / 아이템 개수 / 골드 / 이벤트 완료 | 참 · 거짓 |
| 액션 | 허용 목록만: `set_flag`, `quest_accept`, `quest_advance`, `quest_complete`(보상은 퀘스트 데이터), `mark_event_complete` | 다음 |
| 컷씬 호출 | `data/cutscenes/*.json`의 단계(자막·대기·액터 이동/바라보기·플래그)를 재생하고 끝나면 진행. 카메라는 고정 탑다운 그대로 | 다음 |
| 종료 | 대화를 끝내고 조작 반환. 선택적으로 이벤트 완료 기록(재생해도 한 번만) | — |

대사·조건·사용자 입력을 코드로 실행(`eval`/`Expression`)하는 경로는 없습니다. 같은 퀘스트 수락·보상은 다시 재생해도
중복 적용되지 않습니다(QuestManager가 상태로 막음).

## 데이터 (버전 1, UTF-8 JSON)

```
data/dialogues/<dialogue_id>.json   대화 (version, dialogue_id, metadata{title,tags,notes}, start_node_id, nodes, connections, editor_positions)
data/quests/<quest_id>.json         퀘스트 (목표·보상·결과 분기·시간 제한·반복·현장 사건 트리거)
data/cutscenes/<cutscene_id>.json   컷씬 단계
data/speakers.json                  화자 ID → 표시 이름, NPC가 여는 대화(talk), 대화창 초상화 그림 경로(portrait, 생략 시 assets/portraits/<id>.png)
```

- 연결은 `connections`에만 저장하고 노드 ID로 잇습니다(표시 이름·위치를 바꿔도 끊기지 않음).
- 형식 설명은 `scripts/dialogue/dialogue_data.gd`, `scripts/game/quest_db.gd`, `scripts/dialogue/cutscene_runner.gd` 맨 위 주석.
- 내보내기(export) 빌드를 만들 때는 내보내기 설정의 "리소스가 아닌 파일 포함"에 `data/*.json`을 넣어야 합니다(아직 내보내기 설정 없음).

## 구조 — 에디터와 런타임 분리

```
addons/dialogue_editor/        에디터 전용 (빌드에서 필요 없음)
  plugin.gd                    EditorPlugin: Dialogue 메인 화면, '게임에서 실행' 파일 전달
  dialogue_editor_panel.gd     목록·그래프·속성·미리보기·검증·저장·실행 취소
  editor_selftest.gd           자동 점검 시나리오
scripts/dialogue/              런타임 (에디터 미리보기와 게임이 같은 코드 사용)
  dialogue_data.gd             파일 읽기/쓰기, 스키마, 검증기, 조건 판정
  dialogue_runner.gd           대화 실행기 (start / next / choose)
  dialogue_context.gd          미리보기용 샌드박스 상태
  game_dialogue_context.gd     실게임 상태 연결 (NarrativeState, QuestManager, 소지품, 골드)
  cutscene_runner.gd           게임 안 컷씬 단계 재생
scripts/ui/dialogue_box.gd     게임 대화창
```

## 검증 방법과 결과

- **실제 Godot 4.7.2 에디터 안에서** 플러그인을 띄워 자동 점검(`DIALOGUE_EDITOR_SELFTEST=<캡처 폴더>` 환경 변수로 에디터 실행):
  열기 → 속성 → 미리보기(퀘스트 '받지 않음'이면 의뢰 분기, '목표 달성'이면 보고 분기) → 새 대화를 7종 노드로 작성 →
  오타 퀘스트 ID·연결 없는 선택지를 검증기가 찾음 → 수정 후 오류 0 → 숨김 선택지·컷씬 단계 미리보기 →
  실행 취소/다시 → 복사/붙여넣기 → 노드 이름 변경 후 연결 유지 → 저장 → 다시 열기 후 **노드·연결·문장·위치 동일** →
  한글·줄바꿈 보존 → 밖에서 바뀐 파일은 덮어쓰기 전에 확인. **14개 항목 모두 통과**.
  캡처: `captures/dialogue_editor/`.
- 게임 쪽은 `--tour=quest`로 같은 데이터를 실제 대화창에서 재생(아래 README 캡처 재생성 참고).
- 검증은 클라우드 컨테이너의 소프트웨어 렌더러(xvfb)에서 했습니다. **실제 Windows 에디터에서의 마우스 조작감(드래그·연결)은 직접 확인이 필요합니다.**

## 아직 안 한 것 (핸드오프 P2 품질 개선 중)

CSV/JSON 내보내기, 로컬라이제이션 키, 일괄 치환, 다른 대화 호출(재사용) 노드, 조건 템플릿, 컷씬 타임라인 편집기,
에디터 안 컷씬 실제 재생(현재는 단계 목록만 표시하고 실재생은 '게임에서 실행').
