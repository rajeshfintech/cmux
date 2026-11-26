// Workspace tiles: one tile per workspace, laid out as a grid, with every tab
// and its own live agent status. Open it as a pane:
// `cmux sidebar open workspace-tiles`.
// Click a tile to jump to the workspace, or a tab row to jump to that tab.
//
// States, most urgent first: needs (an agent is waiting for input), ready (an
// agent finished and its reply is unread), working, review, done, idle.

func hasAgents(_ w) -> Bool {
  return w.agents != nil && w.agents.count > 0
}

// Live agent sessions hosted by one tab.
func tabAgents(_ w, _ t) {
  if !hasAgents(w) { return [] }
  return w.agents.filter { $0.panelId == t.id && $0.status != "ended" }
}

// needs, working, ready, idle, or none for a tab that hosts no agent.
func tabState(_ w, _ t) -> String {
  let mine = tabAgents(w, t)
  if mine.filter { $0.status == "needs_input" }.count > 0 { return "needs" }
  if mine.filter { $0.status == "working" }.count > 0 { return "working" }
  if t.hasUnread { return "ready" }
  if mine.count > 0 { return "idle" }
  return "none"
}

// Every tab's state, in tab order. Computed once per tile and passed around,
// because the whole view is re-evaluated about once a second.
func tabStates(_ w) {
  return w.tabs.map { tabState(w, $0) }
}

func countIn(_ states, _ state) -> Int {
  return states.filter { $0 == state }.count
}

func stateFrom(_ w, _ states) -> String {
  if countIn(states, "needs") > 0 { return "needs" }
  if w.status == "needs-attention" { return "needs" }
  if countIn(states, "ready") > 0 { return "ready" }
  if countIn(states, "working") > 0 { return "working" }
  if w.status == "working" { return "working" }
  if w.status == "review" { return "review" }
  if w.status == "done" { return "done" }
  return "idle"
}

func stateOf(_ w) -> String {
  return stateFrom(w, tabStates(w))
}

func tintOf(_ state) -> String {
  if state == "needs" { return "#FF9F0A" }
  if state == "ready" { return "#40C8E0" }
  if state == "working" { return "#0A84FF" }
  if state == "review" { return "#BF5AF2" }
  if state == "done" { return "#30D158" }
  return "#8E8E93"
}

func labelOf(_ state) -> String {
  if state == "needs" { return "Waiting for you" }
  if state == "ready" { return "Reply unread" }
  if state == "working" { return "Working" }
  if state == "review" { return "In review" }
  if state == "done" { return "Done" }
  return "Idle"
}

func shortLabelOf(_ state) -> String {
  if state == "needs" { return "waiting" }
  if state == "ready" { return "unread" }
  if state == "working" { return "working" }
  return "idle"
}

func iconOf(_ state) -> String {
  if state == "needs" { return "hand.raised.fill" }
  if state == "ready" { return "envelope.badge.fill" }
  if state == "working" { return "bolt.fill" }
  if state == "review" { return "eye.fill" }
  if state == "done" { return "checkmark.circle.fill" }
  if state == "none" { return "terminal" }
  return "moon.zzz.fill"
}

// The workspace that only holds this tile view has nothing to report.
func isTileHost(_ w) -> Bool {
  return w.tabCount == 1 && w.tabs[0].title == "workspace-tiles"
}

func agoLabel(_ mins) -> String {
  if mins < 1 { return "now" }
  if mins < 60 { return "\(mins)m" }
  if mins < 1440 { return "\(mins / 60)h" }
  return "\(mins / 1440)d"
}

// How long a tab's agent has been waiting or working, when cmux knows.
func tabSince(_ w, _ t, _ state, _ nowEpoch) -> String {
  if state != "needs" && state != "working" { return "" }
  let wanted = state == "needs" ? "needs_input" : "working"
  let hits = tabAgents(w, t).filter { $0.status == wanted && $0.sinceEpoch != nil }
  if hits.count == 0 { return "" }
  return agoLabel((nowEpoch - hits[0].sinceEpoch) / 60)
}

func statusBand(_ w, _ state) -> some View {
  HStack(spacing: 6) {
    Image(systemName: iconOf(state)).font(.system(size: 12))
    Text(labelOf(state)).font(.system(size: 13)).fontWeight(.bold).textCase(.uppercase)
    Spacer()
    if w.tabCount > 1 {
      Text("\(w.tabCount) tabs").font(.system(size: 12, design: .monospaced)).fontWeight(.semibold)
    }
    if w.unread > 0 {
      Text("\(w.unread)")
        .font(.system(size: 11, design: .monospaced)).bold()
        .foregroundColor(tintOf(state))
        .padding(4)
        .background { Circle().foregroundColor("#FFFFFF") }
    }
  }
  .foregroundColor(state == "idle" ? "#D0D0D6" : "#FFFFFF")
  .padding(8)
  .frame(width: 300, alignment: .leading)
  .background { Rectangle().foregroundColor(tintOf(state)).opacity(state == "idle" ? 0.30 : 0.92) }
}

func chip(_ n, _ state) -> some View {
  HStack(spacing: 4) {
    Circle().frame(width: 7, height: 7).foregroundColor(tintOf(state))
    Text("\(n) \(shortLabelOf(state))").font(.system(size: 11)).fontWeight(.semibold).foregroundColor(tintOf(state))
  }
}

// One line that counts a multi-tab workspace's tabs by state.
func tabSummary(_ states) -> some View {
  HStack(spacing: 10) {
    if countIn(states, "needs") > 0 { chip(countIn(states, "needs"), "needs") }
    if countIn(states, "ready") > 0 { chip(countIn(states, "ready"), "ready") }
    if countIn(states, "working") > 0 { chip(countIn(states, "working"), "working") }
    if countIn(states, "idle") + countIn(states, "none") > 0 { chip(countIn(states, "idle") + countIn(states, "none"), "idle") }
    Spacer()
  }
}

func tabRow(_ w, _ t, _ state, _ nowEpoch) -> some View {
  HStack(spacing: 7) {
    Image(systemName: iconOf(state))
      .font(.system(size: 11))
      .foregroundColor(tintOf(state))
      .opacity(state == "idle" || state == "none" ? 0.6 : 1.0)
      .frame(width: 16)
    Text(t.title)
      .font(.system(size: 13))
      .fontWeight(state == "needs" || state == "ready" ? .semibold : .regular)
      .foregroundColor(state == "idle" || state == "none" ? .secondary : .primary)
      .lineLimit(1).truncationMode(.tail)
    Spacer()
    if state == "needs" || state == "ready" || state == "working" {
      Text("\(shortLabelOf(state)) \(tabSince(w, t, state, nowEpoch))")
        .font(.system(size: 10, design: .monospaced)).fontWeight(.semibold)
        .foregroundColor(tintOf(state))
        .fixedSize()
    }
  }
  .padding(3)
  .background {
    RoundedRectangle(cornerRadius: 5)
      .foregroundColor(tintOf(state))
      .opacity(state == "needs" || state == "ready" ? 0.18 : 0.0)
  }
  .onTapGesture { cmux("surface.focus", surface_id: t.surfaceId, workspace_id: w.id) }
}

// The tabs in one state, in tab order.
func tabRows(_ w, _ states, _ state, _ nowEpoch) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    for i in 0..<states.count {
      if states[i] == state {
        tabRow(w, w.tabs[i], state, nowEpoch)
      }
    }
  }
}

func tile(_ w, _ nowEpoch) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    let states = tabStates(w)
    let state = stateFrom(w, states)
    let quiet = countIn(states, "idle") + countIn(states, "none")

    statusBand(w, state)
    VStack(alignment: .leading, spacing: 6) {
      Text(w.title)
        .font(.system(size: 15)).fontWeight(.semibold)
        .lineLimit(2).truncationMode(.tail)
      if w.pr != nil && w.pr.label != nil {
        Text(w.pr.label).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
      }
      if w.pr == nil && w.branch != nil && w.branch != "" {
        Text(w.branch).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
      }
      if w.tabCount > 1 {
        tabSummary(states)
      }
      // The workspace-level status can come from a signal cmux does not tie
      // to a tab; say so instead of leaving every tab looking idle.
      if w.tabCount > 1 && (state == "needs" || state == "working") && countIn(states, state) == 0 {
        Text("cmux did not report which tab")
          .font(.system(size: 11)).italic()
          .foregroundColor(tintOf(state))
      }
      // A single-tab workspace has room for its last message. Skip
      // machine-generated notices; they are markup, not something to read.
      if w.tabCount == 1 && w.latestMessage != nil && w.latestMessage != "" && !w.latestMessage.hasPrefix("<") && !w.latestMessage.hasPrefix("[") {
        Text(w.latestMessage)
          .font(.system(size: 12)).foregroundColor(.secondary)
          .lineLimit(2).truncationMode(.tail)
      }
      Divider()
      // Tabs that need you first, then unread, then working. Quiet tabs are
      // listed only while the tile has room for all of them.
      if countIn(states, "needs") > 0 { tabRows(w, states, "needs", nowEpoch) }
      if countIn(states, "ready") > 0 { tabRows(w, states, "ready", nowEpoch) }
      if countIn(states, "working") > 0 { tabRows(w, states, "working", nowEpoch) }
      if w.tabCount <= 6 && countIn(states, "idle") > 0 { tabRows(w, states, "idle", nowEpoch) }
      if w.tabCount <= 6 && countIn(states, "none") > 0 { tabRows(w, states, "none", nowEpoch) }
      if w.tabCount > 6 && quiet > 0 {
        Text("+\(quiet) quiet tabs").font(.system(size: 11)).foregroundColor(.tertiary).padding(2)
      }
      Spacer()
    }
    .padding(10)
    .frame(width: 300, height: 256, alignment: .topLeading)
    .background { Rectangle().foregroundColor(tintOf(state)).opacity(state == "idle" ? 0.06 : 0.14) }
    .opacity(state == "idle" ? 0.75 : 1.0)
  }
  .frame(width: 300, height: 290, alignment: .topLeading)
  .clipShape(RoundedRectangle(cornerRadius: 10))
  .overlay {
    RoundedRectangle(cornerRadius: 10)
      .stroke(w.selected ? "#FFFFFF" : "#8E8E93", lineWidth: w.selected ? 2 : 1)
      .opacity(w.selected ? 0.9 : 0.3)
  }
  .onTapGesture { cmux("workspace.select", workspace_id: w.id) }
}

func grid(_ ws, _ cols, _ nowEpoch) -> some View {
  VStack(alignment: .leading, spacing: 10) {
    for r in 0..<((ws.count + cols - 1) / cols) {
      HStack(alignment: .top, spacing: 10) {
        for c in 0..<cols {
          if r * cols + c < ws.count {
            tile(ws[r * cols + c], nowEpoch)
          }
        }
      }
    }
  }
}

func countPill(_ n, _ state) -> some View {
  HStack(spacing: 5) {
    Circle().frame(width: 9, height: 9).foregroundColor(tintOf(state))
    Text("\(n) \(labelOf(state).lowercased())").font(.system(size: 13)).fontWeight(.semibold)
  }
}

VStack(alignment: .leading, spacing: 10) {
  // Bound the live render: every tile is re-evaluated about once a second.
  let ws = workspaces.filter { !isTileHost($0) }.prefix(48)

  let wsStates = ws.map { stateOf($0) }

  HStack(spacing: 12) {
    Text("Workspaces").font(.system(size: 18)).bold()
    Text("\(ws.count)").font(.system(size: 13, design: .monospaced)).foregroundColor(.tertiary)
    countPill(countIn(wsStates, "needs"), "needs")
    countPill(countIn(wsStates, "ready"), "ready")
    countPill(countIn(wsStates, "working"), "working")
    countPill(countIn(wsStates, "idle"), "idle")
    Spacer()
    Text(clock.time).font(.system(size: 12, design: .monospaced)).foregroundColor(.tertiary)
  }
  Divider()

  // Each candidate is a full render, so offer only a few column counts.
  ViewThatFits(in: .horizontal) {
    grid(ws, 5, clock.epoch)
    grid(ws, 3, clock.epoch)
    grid(ws, 2, clock.epoch)
  }
  Spacer()
}
.padding(12)
