# MusicGram — UI/UX Specification

## 1. Product intent

Build a thumb-first, one-handed music player in Flutter for Android first, with adaptive Windows/Linux layouts and future iOS support.

Music sources are **Telegram via TDLib** and **local audio files only**.

The reference screenshot is a visual design target, not proof of every control's behavior.

## 2. Design principles

- **One-hand operation:** frequent actions live within the lower thumb-reachable region; avoid forcing a reach to the top for routine playback.
- **Right-hand and left-hand modes:** equivalent feature access and gestures, with a mirrored control cluster.
- **Function over decoration:** curved controls must be accessible, precise, and responsive.
- **Offline-first local library:** local tracks remain available without login or network.
- **Responsive:** retain the mobile interaction concept on phones; use a desktop-appropriate layout on wide screens.
- **Accessible:** semantic labels, keyboard alternatives, scalable text, sufficient contrast, and reduced-motion support.

## 3. Screenshot decomposition (portrait reference, 864 × 1536)

Coordinates below are approximate **screenshot pixels**, not Flutter logical pixels; adapt proportionally and account for system insets.

| Element | Approximate location / appearance | Behavior |
| --- | --- | --- |
| Background | Dark blue-gray (`#263240` approximate) | Full content canvas |
| Accent | Hot pink (`#F52955` approximate) | Active controls and primary actions |
| Left accent strip | Thin pink line along far left | Decorative or navigation cue; verify intent |
| Settings | Top-right pink circle with white gear, center ~ (806,144) | Open settings |
| Blue outline arrow | Right edge, center ~ (821,427) | **Unconfirmed**; do not assign a final action without validation |
| Search | Lower-middle, placeholder "Search your Song"; underline and large pink search circle at ~ (778,755) | Search the unified library |
| Song title | White bold text beneath search, "Song Name Place here" | Display current track |
| Artist | Shadowed rounded dark card with person icon | Show artist metadata/filter |
| Album | Shadowed rounded dark card with album icon | Show album metadata/filter |
| Files | Left lower area with folder icon | Open local/Telegram source browsing |
| Repeat, Shuffle | Muted gray controls below Files | Toggle repeat/shuffle; use explicit active states |
| Curved volume slider | Pink curved arc from ~ (345,1325) toward ~ (608,922), gray remainder, pink thumb | **Confirmed:** controls audio volume |
| Speaker | Right of volume arc, near (786,903) | Volume indicator; tap action TBD |
| Play | Pink circular button, center ~ (778,1042) | Play/pause |
| Next | Gray circular button, center ~ (547,1104) | Next track |
| Previous | Gray circular button, center ~ (489,1334) | Previous track |
| Circular timer | Bottom-right, center ~ (700,1258), white segmented arcs and pink `00:00` center | Displays playback time; **seek-by-rotation is a hypothesis pending confirmation** |
| Android system bars | Status bar top, 3-button navigation bottom | Respect safe areas; do not draw over system UI unintentionally |

**Important:** The curved pink arc is a **volume seekbar**, not the track progress seekbar. Never confuse these two concepts in code or tests.

## 4. Mobile layout

### Portrait

- Keep title, artist, album, and source access on the left half when possible.
- Anchor the primary playback cluster to the lower-right for right-handed mode, above the system navigation safe area.
- Volume arc wraps the outside/left of the playback cluster, with a generous invisible hit region.
- Search stays above the playback controls, with no overlap at common phone sizes.
- Use relative constraints rather than fixed screenshot coordinates. Prefer `LayoutBuilder`, `SafeArea`, `Stack`, `Positioned`, and `CustomPainter`.
- On small screens, allow metadata to truncate gracefully, shrink decorative whitespace, and keep essential controls visible.

### Landscape and tablets

- Separate library/navigation from player controls.
- Keep primary controls together in the user's selected hand zone.
- Never stretch circular controls into ellipses.

## 5. Left-handed mode — REQUIRED

Add a setting: **Settings → Playback & Controls → Hand preference**:

- `Right-handed` (default, matches reference screenshot)
- `Left-handed`
- Optional future `Follow system / automatic` only if a reliable preference source exists; do not infer handedness from device orientation.

### Mirroring rules

- Mirror the **interactive player composition** horizontally around its container center: play, next, previous, circular time control, curved volume track/thumb, speaker icon, and nearby utility controls.
- Move the thumb-focused playback cluster from bottom-right to bottom-left.
- Rebalance search, metadata, Files, Repeat, and Shuffle to prevent collisions and preserve readable order.
- Mirror **positions and gesture geometry**, not text glyphs, time values, music artwork, or familiar semantic icons such as play/pause.
- Maintain logical next/previous meaning and correct accessibility traversal order after mirroring.
- Settings and navigation may remain conventional where that improves usability; do not blindly mirror the entire application.
- Persist preference across launches; changing it updates the UI immediately without interrupting playback.
- Support both LTR and RTL locales independently of hand preference. RTL language direction must **not** automatically change hand preference.

### Left-hand gesture correctness

- Convert pointer coordinates into the active layout's local coordinate system before calculating arc position.
- Ensure dragging direction corresponds to the displayed min/max values after mirroring.
- Test minimum, midpoint, maximum, drag across endpoints, and cancellation for both hand modes.
- Prevent accidental activation of overlapping buttons when adjusting volume.

## 6. Curved volume slider specification

- Build a reusable `ArcVolumeSlider` with `value: double` in `[0,1]`, `onChanged`, and optional `onChangeEnd`.
- Render inactive track in muted gray, active track in accent pink, and draggable pink circular thumb.
- Gesture input: map touch position to angle around a defined center; clamp the angle to the rendered arc range and normalize to `[0,1]`.
- Preserve continuity across angle wrap boundaries; avoid sudden jumps near the arc endpoints.
- Offer touch targets around the arc of at least ~44–48 logical pixels where feasible, without intercepting neighboring controls.
- Support tap-to-set and drag-to-adjust, plus accessibility increment/decrement actions.
- Debounce/throttle OS volume writes if required, but update the visual thumb smoothly.
- Bind to the actual audio output volume exposed by the selected playback engine. Document platform limitations (app volume vs system volume).
- Add visual and screen-reader feedback such as `Volume 65%`.

## 7. Circular time / playback control

- Display elapsed time in `mm:ss` (or `hh:mm:ss` for long tracks), centered in the pink circle.
- Render the decorative/functional circular arcs faithfully to the screenshot.
- **Open product question:** is the circular ring a seek control? If confirmed, implement `CircularTrackSeekBar` with drag, tap, elapsed/total time, and seek previews; otherwise render as a time/progress indicator and expose a separate accessible seek control.
- Never make the only seek mechanism a precision circular gesture without an accessible alternative.

## 8. Interaction states

- **No track:** placeholder title/artist/album, disabled next/previous and seek, local library accessible.
- **Playing:** play button becomes pause; time/progress updates; media session active.
- **Paused:** progress retained; play resumes.
- **Buffering Telegram audio:** progress indication and nonblocking controls.
- **Offline Telegram track not cached:** show clear unavailable state; local playback remains functional.
- **Repeat/shuffle:** visibly distinct enabled/disabled states and accessible labels.
- **Proxy disconnected:** show Telegram-only connection issue; never disable local music controls.
- **Empty search / no results / permission denied:** actionable empty states.

## 9. Screens and navigation

1. Player / Home (reference-inspired one-handed layout)
2. Unified Library (Telegram / Local / All filters)
3. Search (tracks, artist, album, source)
4. Playlists & Favorites (mixed-source playlists)
5. Downloads & Cache
6. Telegram Sign-in and Connection Status
7. Proxy Manager (MTProto / SOCKS5 / HTTP; manual and supported Telegram links)
8. Settings (including hand preference)
9. Cast Device Picker and Active Cast Session

Keep login optional for local playback. Proxy configuration must be reachable before Telegram login.

## 10. Adaptive desktop UI

- Windows/Linux: sidebar navigation, resizable library, persistent player panel, mouse wheel, hover states, keyboard shortcuts, media keys when supported.
- Preserve the visual identity and volume arc where useful, but don't force a phone-only thumb layout onto a desktop window.
- Respect platform window resizing, minimum usable dimensions, file selection, and drag/drop if implemented.

## 11. Flutter component plan

```text
PlayerScreen
 ├── PlayerBackground
 ├── SettingsButton
 ├── SearchBar
 ├── TrackMetadata (title, artist, album)
 ├── SourceAndModeActions (Files, Repeat, Shuffle)
 └── OneHandControlCluster(handPreference)
      ├── ArcVolumeSlider
      ├── SpeakerIndicator
      ├── PlayPauseButton
      ├── NextButton
      ├── PreviousButton
      └── CircularTimeControl
```

Suggested implementation:

- `CustomPainter` for arcs and rings.
- `GestureDetector` or lower-level pointer handling for precise arc interaction.
- `Semantics`, focus actions, and keyboard alternatives for accessibility.
- Riverpod for persisted hand preference, player state, volume, track progress, and source filters.
- Keep widget layout separate from the playback engine, TDLib, and local file indexer.

## 12. Design tokens (starting approximations)

| Token | Suggested value |
| --- | --- |
| `background` | `#263240` |
| `accent` | `#F52955` |
| `primaryText` | `#FFFFFF` |
| `mutedText` | `#92959E` (verify against screenshot) |
| `inactiveControl` | `#747D8C` (verify) |
| `accentBlue` | `#5B82CC` (verify) |
| `buttonShape` | Circular |
| `metadataCardShape` | Rounded rectangle with subtle shadow |
| `touchTarget` | Minimum 48 × 48 logical pixels for key actions |

Colors are visual estimates, not sampled brand specifications. Maintain adequate contrast in production.

## 13. Validation / acceptance checklist

- [ ] Right-hand portrait layout visually resembles reference at comparable aspect ratio.
- [ ] Left-hand mode mirrors the interactive cluster without mirrored text or reversed play/skip semantics.
- [ ] Hand preference survives restart and can change while music plays.
- [ ] Volume arc adjusts the intended volume smoothly in both modes, with no jumps or hitbox conflicts.
- [ ] Local tracks can be searched and played offline without Telegram authentication.
- [ ] Telegram tracks can be browsed and played when authenticated and connected via direct connection or configured TDLib proxy.
- [ ] Search, Files, Repeat, Shuffle, Play/Pause, Next, Previous have correct enabled/disabled states.
- [ ] Layout works with status/navigation bars, small screens, large font settings, and RTL text.
- [ ] Screen readers and keyboard users can access all essential playback operations.
- [ ] Desktop builds use adaptive layout and verified platform audio integrations.

## 14. Questions to resolve before final visual parity

1. Is the bottom-right circular timer also a rotational seekbar, or only a progress/time display?
2. What does the blue outlined left-pointing arrow on the right edge do?
3. What is the meaning of the thin pink stripe at the far left?
4. Does tapping the speaker icon mute/unmute, or only label the volume arc?
5. Should the search action query only indexed music or also trigger Telegram message discovery?

Until confirmed, implement these as explicit assumptions or non-destructive placeholders; do not invent behaviors.

## 15. UPnP/DLNA casting UX — mobile and desktop

**Purpose:** Let users play either Telegram music or local tracks on a compatible DLNA/UPnP renderer (e.g., supported smart TVs or speakers) over a reachable local network. Casting is optional; ordinary local/Telegram playback remains fully functional without it.

### Entry points and thumb-first placement

- Add a recognizable `Cast to device` action in the Now Playing controls and optionally in the track overflow menu.
- On mobile, place the Cast touch target within comfortable thumb reach **without covering** the pink arc-shaped volume seekbar, Play/Next/Previous cluster, or circular time control. Prefer a small action adjacent to the metadata/actions region or a reachable bottom sheet trigger; validate on actual device sizes.
- In right-hand mode, position the reachable Cast entry on the right-side interaction zone; in left-hand mode, mirror **its position**, not the Cast icon glyph or text.
- Minimum interactive hit target: 48×48 logical pixels; maintain sufficient spacing from the volume arc gesture hitbox.
- On desktop, provide Cast in the persistent player bar or toolbar; use the same device/session model.

### Device picker

- Open a bottom sheet on mobile (dialog/popover on desktop) titled `Play on a device`.
- Show `This device` first, then discovered DLNA renderers with device name, device-type icon, availability and optional capability note.
- Show scanning progress, `No devices found`, retry action, and a concise hint: `Connect to the same Wi-Fi; some networks block device discovery.`
- Clearly identify that DLNA is distinct from Chromecast/Google Cast; do not show unsupported receivers as selectable.
- Confirm connection state with `Connecting…`, `Playing on [device]`, or actionable errors.

### Active cast session

- Display an unobtrusive active-device indicator near the player title/controls.
- Play/Pause/Stop, track change, and seeking act on the TV when supported; unsupported actions should be visibly unavailable with explanation.
- **Pink curved volume seekbar:** when casting, it controls the remote renderer's volume if `RenderingControl` supports it. Show a small `TV volume` label or speaker/device cue so users do not confuse it with phone volume. If remote volume cannot be controlled, disable the arc with an explanatory message rather than silently adjusting phone volume.
- **Circular time control:** preserve the existing unresolved gesture specification; do not invent rotational seeking behavior. If time seeking is later confirmed, route it to remote AVTransport during casting when supported.
- Show buffering, renderer busy, unsupported codec, unreachable file, and disconnection states distinctly.
- Offer `Stop casting` and `Play on this device`; for handoff, resume locally near the remote position if supported, otherwise state that position could not be restored.
- Keep queue/favorites/search available during casting; local files still work without Telegram login.

### Accessibility, privacy, and feedback

- Use screen-reader labels such as `Cast to device`, `Connected to living room TV`, `TV volume 45 percent`, and `Stop casting`.
- Cast selection and device name are UI state; never expose Telegram credentials, proxies, private chat URLs, or original filesystem paths to the renderer.
- Provide clear notification when a local HTTP media endpoint is running and close it after casting.
- Honor both hand modes, RTL text, safe areas, screen scaling, and accessible font sizes.

### Casting UX acceptance checklist

- [ ] Device picker works in both hand modes and does not overlap core gestures.
- [ ] Discovery, connecting, active, disconnected, unsupported-format, and empty states are designed.
- [ ] Both Telegram-downloaded and local songs have the same Cast entry point.
- [ ] Volume arc targets TV volume only when supported; no accidental phone-volume change.
- [ ] Play/pause/track change reflect actual remote state rather than optimistic permanent success.
- [ ] Switching back to phone playback is explicit and predictable.
- [ ] Desktop presentation adapts without forcing the mobile bottom sheet layout.

## 16. Updated Flutter component map

```text
PlayerScreen
 ├── TrackMetadata
 ├── CastEntryButton (hand-aware position)
 ├── CastDevicePicker (bottom sheet / desktop dialog)
 ├── CastSessionIndicator
 └── OneHandControlCluster(handPreference)
      ├── ArcVolumeSlider (local or supported renderer volume)
      ├── PlayPause / Next / Previous
      └── CircularTimeControl (behavior pending confirmation)
```

Use a shared `PlaybackTarget` state (`localDevice` / `dlnaRenderer`) to route commands and render the correct labels/disabled states. Never assume UPnP supports every remote action.
