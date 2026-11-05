# OpenHuman client

The Flutter client is the person's side of OpenHuman: where messages from
someone else's tool (Claude Code, Cursor, WorkBuddy, …) arrive, and where
they answer. It runs on Windows, Android, iOS-size phones, tablets and the
web from one code base.

The one rule behind every screen: **this is two people talking.** The
other side is a person who writes from their own tool, never "an AI". The
console leads with names and faces, keeps the tool as a small `经由 Cursor`
tag, and folds protocol details (ids, tool schemas, system prompts) away
until someone asks for them. A widget test (`test/no_ai_words_test.dart`)
fails the build if the word "AI" appears anywhere the console draws.

## Screens

| Screen | Where | What it does |
|---|---|---|
| Sign-in | `features/auth/auth_screen.dart` | Server address + key, remembered; reconnects on launch |
| Conversation list | `features/chat/conversation_sidebar.dart` | Direct chats and groups, search (Ctrl K), per-row turn state |
| Stream | `features/chat/stream/*` | Messages, runs, task cards, attachments, rich text, retry |
| Composer | `features/chat/room_composer.dart` | Send, `@` mentions in groups, files for open tasks, 发送完毕 |
| Details (Ctrl I) | `features/chat/details_panel.dart` | The person or the group; remark name; technical details folded |
| 让别人联系你 | `features/chat/share_sheet.dart` | Address, key and model to give a friend; copyable note |
| 文件库 | `features/files/file_library.dart` | Every file the account holds: open, save, delete, upload |
| 回收站 | sheet in `conversation_sidebar.dart` | Restore or permanently delete conversations |
| 更多群设置 | `features/chat/room_panel.dart` | Room caller keys, connected tools, speaking rules (owner) |

### Layout by width (`app/adaptive.dart`)

| Width | Class | Layout |
|---|---|---|
| < 640 | compact | One pane at a time: list → stream; details as a bottom sheet |
| 640–1100 | medium | List + stream; details slide over the stream |
| ≥ 1100 | expanded | List, stream and details side by side; both side panes resizable |

### The list row

Each row answers "do I need to do something here?" without opening it:

- the person's name (or the group's title and size), and a time;
- the last word: theirs as is, mine as `你：…`, a reply that never left as
  `未发出：…` in red, or — before anything was said — `经由 Cursor`;
- an **unread pill** (apricot when they are also waiting, grey otherwise)
  or an apricot **等你回复** tag once read but unanswered.

The list endpoint has no previews, so after it loads the client fetches the
newest message of each row (`limit=1`, six at a time, up to 40 rows). The
row and the open conversation's header use the same rule for whose turn it
is: the newest message is theirs.

### The header's turn state

`在等你回复` (apricot) · `等对方回复` · `你的回复没发出去` (red) ·
`这一轮你说完了`. The tray's hover text on Windows carries the same
information: `OpenHuman · 2 人在等你回复`.

### Keyboard

| Keys | Action |
|---|---|
| Ctrl/⌘ K | Search conversations (↑ ↓ Enter, Esc) |
| Ctrl/⌘ B | Show / hide the list |
| Ctrl/⌘ I | Show / hide details |
| Enter / Shift Enter | Send / new line |
| Ctrl/⌘ Enter | 发送完毕 — end my turn (`end.turn`) |

## Server coverage

Every endpoint the Dart SDK wraps, and where the console uses it.

### HTTP

| Endpoint | SDK | Console |
|---|---|---|
| `GET /v1/conversations` | `fetchConversations` | List |
| `GET /v1/conversations?deleted=true` | `fetchTrash` | 回收站 |
| `GET /v1/conversations/:id/messages` | `fetchMessages` | Stream history; list previews (`limit=1`) |
| `POST /v1/conversations/:id/save` | `saveConversation` | Row menu, details |
| `DELETE /v1/conversations/:id` | `deleteConversation` | 移到回收站 |
| `POST /v1/conversations/:id/restore` | `restoreConversation` | 回收站 → 恢复 |
| `DELETE /v1/conversations/:id/permanent` | `deleteConversationPermanently` | 回收站 → 彻底删除 |
| `PATCH /v1/agents/:id` | `renameAgent` | 改备注名 (keeps `via <tool>`) |
| `POST /v1/rooms` | `createRoom` | 新建群聊 |
| `GET /v1/rooms/:id` | `getRoom` | Group header, members, ownership |
| `PATCH /v1/rooms/:id` | `updateRoomSettings` | 更多群设置 |
| `POST /v1/rooms/:id/invites` | `mintInvite` | Details → 生成邀请码 |
| `DELETE /v1/rooms/:id/invites/:code` | `revokeInvite` | Details → 作废 |
| `POST /v1/invites/:code/accept` | `acceptInvite` | List footer → 加入 |
| `POST /v1/rooms/:id/leave` | `leaveRoom` | Details → 退出群聊 |
| `DELETE /v1/rooms/:id/members/:pid` | `removeRoomMember` | Details → 移出 (owner) |
| `POST /v1/rooms/:id/caller-keys` | `mintCallerKey` | 更多群设置 |
| `GET /v1/rooms/:id/callers` | `listRoomCallers` | 更多群设置 → 已接入的工具 |
| `GET /v1/rooms/:id/messages` | `fetchRoomMessages` | — (rooms load through conversation history) |
| `POST /v1/seat/reply` | `answer` | Task cards: answers with files / structured answers |
| `GET /v1/files` | `listFiles` | 文件库 |
| `GET /v1/files/:id` | `fileInfo` | — |
| `GET /v1/files/:id/content` | `fileContent` | 文件库 → open / save |
| `POST /v1/files` | `uploadFile` | 文件库 → 上传 |
| `DELETE /v1/files/:id` | `deleteFile` | 文件库 → 删除 |
| `GET /v1/seat/model-name` (fallback `GET /v1/models`) | `modelName` | 让别人联系你 |
| `POST /v1/seat/model-name` | `setModelName` | 让别人联系你 → 改模型名 (unless pinned) |

### WebSocket

| Event | Direction | Console |
|---|---|---|
| `session.connected` | in | Who I am |
| `message.received` | in | Stream, list row, unread, turn state; `request` carries tasks |
| `reply.delivered` | in | `已送达` under my message |
| `capability.updated` | in | Details → 技术详情 → tools |
| `tool.result` | in | Tool card result |
| `async.invocation.created` | in | Pending task bookkeeping |
| `conversation.started` | in | Origin of a conversation |
| `error` | in | — (kept by the SDK; a failed send shows on the message itself) |
| `reply.send` | out | Send |
| `end.turn` | out | 发送完毕 |
| `tool.invoke` | out | Tool card → 执行 |
| `presence.update`, `capability.manifest` | out | — (not used by the console) |

## State

All network access goes through the SDK; all SDK access goes through
Riverpod providers in `core/sdk_provider.dart`:

- `openHumanClientProvider` — the client, app lifetime
- `connectionStateProvider` — replays the current state, then the stream
- `conversationListProvider` — rows with `unread`, `waiting`, `lastFromMe`,
  `lastFailed`; `markRead`, `markAnswered`, `markFailed`, `markSent`,
  `applyLastMessage`
- `chatControllerProvider` — the open conversation's messages; sending,
  retry, task answers
- `roomInfoProvider(id)` / `roomOwnershipProvider(id)` — a group's detail;
  members are identified by `participant_id`
- `capabilityCacheProvider` — the latest tool report, always subscribed
- `trashListProvider`, `fileLibraryProvider`, `modelNameProvider`

Times are shown on the Beijing clock everywhere (list, stream, files), so a
machine in another zone does not show two clocks at once.

## Design

Tokens live in `app/tokens.dart` (the Darkroom palette): Ink `#16171C`,
Paper `#F7F2EA`, and Apricot `#FF8A5C` — used only for the human signal:
someone is waiting on you, an unread count while they wait, mentions, the
send button of an open task. Everything else stays in the neutral ramp.
Type is Manrope + Geist Mono with Noto Sans SC for Chinese.

## Tests

```bash
cd client
flutter test                                   # unit + widget tests (CI)
OH_SHOT=1 flutter test test/visual --update-goldens   # screenshots
```

The screenshots in `test/visual/shots/` are a visual check, not a golden
gate (fonts render differently per OS): `chat`, `chat_task`, `chat_room`,
`chat_room_details`, `chat_runtime`, `chat_menu`, `share`, `files`, `auth`,
`auth_phone`, `phone_list`, `phone_chat`, `phone_runtime`, `tablet`,
`tablet_runtime`, `empty_offline`. The sample people and content are in
`test/visual/harness.dart`.

On a machine behind an HTTP proxy, set `NO_PROXY=127.0.0.1,localhost`
before `flutter test`: the test runner talks to the tester over a local
websocket.

## Known gaps

Needs the server:

- no endpoint to rotate a key — 让别人联系你 hands out the current one
- file metadata does not say which conversation a file came from
- no presence for group members; no "is typing" signal
- an invite is a code, not a link
- push notification text is written by the server

Client:

- video opens in the system player rather than inline
