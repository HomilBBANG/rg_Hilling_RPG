# 대화 초상화

대화창 초상화 그림을 여기에 넣습니다. 파일 이름은 `data/speakers.json`의 화자 ID입니다.

| 파일 | 화자 | 위치 |
|---|---|---|
| `player.png` | 주인공 (기본) | 왼쪽 |
| `player_surprised.png` | 주인공 (놀람) | 왼쪽 |
| `player_thinking.png` | 주인공 (생각·고민) | 왼쪽 |
| `player_angry.png` | 주인공 (화남) | 왼쪽 |
| `player_happy.png` | 주인공 (기대·기쁨) | 왼쪽 |
| `player_sad.png` | 주인공 (실망·슬픔) | 왼쪽 |
| `rosa.png` | 로사 | 오른쪽 |
| `bron.png` | 브론 | 오른쪽 |
| `cat.png` | 검은 고양이 | 오른쪽 |
| `king.png` | 왕 | 오른쪽 |

- 칸은 420×480입니다. 전신 그림은 위쪽 68%(머리~허리)가 칸을 채우도록 확대되고 아래는 화면 밖으로 나갑니다. 이름표는 아래쪽 가운데.
- 표정: `<화자 ID>_<표정>.png`를 넣고 `data/speakers.json`의 그 화자 `"expressions"`에 등록하면 대화 에디터의 대사 노드에서 고를 수 있습니다.
- 배경이 있는 그림은 `python tools/portraits/prepare_portrait.py 원본 결과.png`로 배경을 지우고 잘라 냅니다(원본은 `art_src/portraits/`에 보관).
- 주인공은 오른쪽(상대 쪽), 상대는 왼쪽을 보도록 그리면 됩니다.
- 그림이 없는 화자는 도형 자리표시가 대신 나옵니다.
- 다른 경로를 쓰려면 speakers.json에서 그 화자에 `"portrait": "res://..."`를 넣습니다.
