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
  if state == "needs" { return "#E0AF68" }
  if state == "working" { return "#7AA2F7" }
  if state == "review" { return "#BB9AF7" }
  if state == "done" { return "#9ECE6A" }
  return "#7F849C"
}

func labelOf(_ state) -> String {
  if state == "needs" { return "Needs you" }
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

func statusPill(_ w, _ state, _ nowEpoch) -> some View {
  HStack(spacing: 4) {
    Image(systemName: iconOf(state)).font(.system(size: 9))
    Text(labelOf(state)).font(.system(size: 10)).fontWeight(.semibold)
    if sinceLabel(w, state, nowEpoch) != "" {
      Text(sinceLabel(w, state, nowEpoch)).font(.system(size: 10, design: .monospaced))
    }
  }
  .foregroundColor(tintOf(state))
  .padding(4)
  .background { Capsule().foregroundColor(tintOf(state)).opacity(0.16) }
}

func tabRow(_ w, _ t) -> some View {
  HStack(spacing: 6) {
    Circle().frame(width: 5, height: 5)
      .foregroundColor(t.hasUnread ? "#E0AF68" : (t.focused ? "#7AA2F7" : "#7F849C"))
      .opacity(t.hasUnread || t.focused ? 1.0 : 0.45)
    Text(t.title)
      .font(.system(size: 11))
      .foregroundColor(t.hasUnread ? .primary : .secondary)
      .lineLimit(1).truncationMode(.tail)
    Spacer()
  }
  .padding(2)
  .onTapGesture { cmux("surface.focus", surface_id: t.surfaceId, workspace_id: w.id) }
}

func tile(_ w, _ nowEpoch) -> some View {
  VStack(alignment: .leading, spacing: 6) {
    HStack(alignment: .top, spacing: 6) {
      Text(w.title)
        .font(.system(size: 13)).fontWeight(.semibold)
        .lineLimit(2).truncationMode(.tail)
      Spacer()
      if w.unread > 0 {
        Text("\(w.unread)")
          .font(.system(size: 9, design: .monospaced)).bold()
          .foregroundColor("#1A1A22")
          .padding(4)
          .background { Circle().foregroundColor("#E0AF68") }
      }
    }
    HStack(spacing: 6) {
      statusPill(w, stateOf(w), nowEpoch)
      if w.pr != nil && w.pr.label != nil {
        Text(w.pr.label).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
      }
      if w.pr == nil && w.branch != nil && w.branch != "" {
        Text(w.branch).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
      }
      Spacer()
    }
    // Skip machine-generated notices; they are markup, not something to read.
    if w.latestMessage != nil && w.latestMessage != "" && !w.latestMessage.hasPrefix("<") && !w.latestMessage.hasPrefix("[") {
      Text(w.latestMessage)
        .font(.system(size: 10)).foregroundColor(.secondary)
        .lineLimit(2).truncationMode(.tail)
    }
    Divider()
    ForEach(w.tabs.prefix(4)) { t in
      tabRow(w, t)
    }
    if w.tabCount > 4 {
      Text("+\(w.tabCount - 4) more").font(.system(size: 10)).foregroundColor(.tertiary).padding(2)
    }
    Spacer()
  }
  .padding(10)
  .frame(width: 250, height: 200, alignment: .topLeading)
  .background { RoundedRectangle(cornerRadius: 10).foregroundColor(tintOf(stateOf(w))).opacity(w.selected ? 0.20 : 0.08) }
  .overlay {
    RoundedRectangle(cornerRadius: 10)
      .stroke(tintOf(stateOf(w)), lineWidth: w.selected ? 2 : 1)
      .opacity(w.selected || stateOf(w) == "needs" ? 0.9 : 0.25)
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
  HStack(spacing: 4) {
    Circle().frame(width: 6, height: 6).foregroundColor(tintOf(state))
    Text("\(n) \(labelOf(state).lowercased())").font(.system(size: 11)).foregroundColor(.secondary)
  }
}

VStack(alignment: .leading, spacing: 10) {
  // Bound the live render: every tile is re-evaluated about once a second.
  let ws = workspaces.prefix(48)

  HStack(spacing: 12) {
    Text("Workspaces").font(.system(size: 15)).bold()
    Text("\(workspaceCount)").font(.system(size: 11, design: .monospaced)).foregroundColor(.tertiary)
    countPill(ws.filter { stateOf($0) == "needs" }.count, "needs")
    countPill(ws.filter { stateOf($0) == "working" }.count, "working")
    countPill(ws.filter { stateOf($0) == "idle" }.count, "idle")
    Spacer()
    Text(clock.time).font(.system(size: 10, design: .monospaced)).foregroundColor(.tertiary)
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
