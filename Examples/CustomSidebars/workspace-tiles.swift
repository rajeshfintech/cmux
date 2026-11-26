// Workspace tiles: one tile per workspace, laid out as a grid, with every tab
// and the live agent status. Open it as a pane: `cmux sidebar open workspace-tiles`.
// Click a tile to jump to the workspace, or a tab row to jump to that tab.

func hasAgents(_ w) -> Bool {
  return w.agents != nil && w.agents.count > 0
}

func agentCount(_ w, _ status) -> Int {
  if !hasAgents(w) { return 0 }
  return w.agents.filter { $0.status == status }.count
}

// One of: needs, working, review, done, idle.
func stateOf(_ w) -> String {
  if agentCount(w, "needs_input") > 0 { return "needs" }
  if w.status == "needs-attention" { return "needs" }
  if agentCount(w, "working") > 0 { return "working" }
  if w.status == "working" { return "working" }
  if w.status == "review" { return "review" }
  if w.status == "done" { return "done" }
  return "idle"
}

func tintOf(_ state) -> String {
  if state == "needs" { return "#FF9F0A" }
  if state == "working" { return "#0A84FF" }
  if state == "review" { return "#BF5AF2" }
  if state == "done" { return "#30D158" }
  return "#8E8E93"
}

func labelOf(_ state) -> String {
  if state == "needs" { return "Waiting for you" }
  if state == "working" { return "Working" }
  if state == "review" { return "In review" }
  if state == "done" { return "Done" }
  return "Idle"
}

func iconOf(_ state) -> String {
  if state == "needs" { return "hand.raised.fill" }
  if state == "working" { return "bolt.fill" }
  if state == "review" { return "eye.fill" }
  if state == "done" { return "checkmark.circle.fill" }
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

// How long the workspace has been in its current agent state, when cmux knows.
func sinceLabel(_ w, _ state, _ nowEpoch) -> String {
  if !hasAgents(w) { return "" }
  let wanted = state == "needs" ? "needs_input" : "working"
  let hits = w.agents.filter { $0.status == wanted && $0.sinceEpoch != nil }
  if hits.count == 0 { return "" }
  return agoLabel((nowEpoch - hits[0].sinceEpoch) / 60)
}

func statusBand(_ w, _ state, _ nowEpoch) -> some View {
  HStack(spacing: 6) {
    Image(systemName: iconOf(state)).font(.system(size: 12))
    Text(labelOf(state)).font(.system(size: 13)).fontWeight(.bold).textCase(.uppercase)
    Spacer()
    if sinceLabel(w, state, nowEpoch) != "" {
      Text(sinceLabel(w, state, nowEpoch)).font(.system(size: 12, design: .monospaced)).fontWeight(.semibold)
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
  .frame(width: 290, alignment: .leading)
  .background { Rectangle().foregroundColor(tintOf(state)).opacity(state == "idle" ? 0.30 : 0.92) }
}

func tabRow(_ w, _ t) -> some View {
  HStack(spacing: 7) {
    Circle().frame(width: 6, height: 6)
      .foregroundColor(t.hasUnread ? "#FF9F0A" : (t.focused ? "#0A84FF" : "#8E8E93"))
      .opacity(t.hasUnread || t.focused ? 1.0 : 0.45)
    Text(t.title)
      .font(.system(size: 13))
      .foregroundColor(t.hasUnread ? .primary : .secondary)
      .lineLimit(1).truncationMode(.tail)
    Spacer()
  }
  .padding(2)
  .onTapGesture { cmux("surface.focus", surface_id: t.surfaceId, workspace_id: w.id) }
}

func tile(_ w, _ nowEpoch) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    statusBand(w, stateOf(w), nowEpoch)
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
      // Skip machine-generated notices; they are markup, not something to read.
      if w.latestMessage != nil && w.latestMessage != "" && !w.latestMessage.hasPrefix("<") && !w.latestMessage.hasPrefix("[") {
        Text(w.latestMessage)
          .font(.system(size: 12)).foregroundColor(.secondary)
          .lineLimit(2).truncationMode(.tail)
      }
      Divider()
      ForEach(w.tabs.prefix(4)) { t in
        tabRow(w, t)
      }
      if w.tabCount > 4 {
        Text("+\(w.tabCount - 4) more").font(.system(size: 11)).foregroundColor(.tertiary).padding(2)
      }
      Spacer()
    }
    .padding(10)
  }
  .frame(width: 290, height: 250, alignment: .topLeading)
  .background { Rectangle().foregroundColor(tintOf(stateOf(w))).opacity(stateOf(w) == "idle" ? 0.06 : 0.14) }
  .clipShape(RoundedRectangle(cornerRadius: 10))
  .overlay {
    RoundedRectangle(cornerRadius: 10)
      .stroke(tintOf(stateOf(w)), lineWidth: w.selected || stateOf(w) == "needs" ? 2 : 1)
      .opacity(w.selected || stateOf(w) == "needs" ? 1.0 : 0.35)
  }
  .opacity(stateOf(w) == "idle" ? 0.75 : 1.0)
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

  HStack(spacing: 12) {
    Text("Workspaces").font(.system(size: 18)).bold()
    Text("\(ws.count)").font(.system(size: 13, design: .monospaced)).foregroundColor(.tertiary)
    countPill(ws.filter { stateOf($0) == "needs" }.count, "needs")
    countPill(ws.filter { stateOf($0) == "working" }.count, "working")
    countPill(ws.filter { stateOf($0) == "idle" }.count, "idle")
    Spacer()
    Text(clock.time).font(.system(size: 12, design: .monospaced)).foregroundColor(.tertiary)
  }
  Divider()

  ViewThatFits(in: .horizontal) {
    grid(ws, 6, clock.epoch)
    grid(ws, 5, clock.epoch)
    grid(ws, 4, clock.epoch)
    grid(ws, 3, clock.epoch)
    grid(ws, 2, clock.epoch)
    grid(ws, 1, clock.epoch)
  }
  Spacer()
}
.padding(12)
