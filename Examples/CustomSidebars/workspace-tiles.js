// workspace-tiles: one tile per workspace, laid out as a grid, with every tab
// and its own live agent status.
//   cmux sidebar open workspace-tiles
// Click a tile to jump to the workspace, or a tab row to jump to that tab.
// Click a status in the header to show only the tiles in that state; click it
// again (or "All") to show everything. "Columns" sets how many tiles per row.
// The x on a tile closes that workspace after a second, confirming click;
// right-click a tile or a tab row for the same without the extra step.
//
// States, most urgent first: needs (an agent is waiting for input), ready (an
// agent finished and its reply is unread), working, review, done, idle.

const META = {
  needs: { label: "Waiting for you", short: "waiting", tint: "#FF9F0A", icon: "hand.raised.fill" },
  ready: { label: "Reply unread", short: "unread", tint: "#40C8E0", icon: "envelope.badge.fill" },
  working: { label: "Working", short: "working", tint: "#0A84FF", icon: "bolt.fill" },
  review: { label: "In review", short: "review", tint: "#BF5AF2", icon: "eye.fill" },
  done: { label: "Done", short: "done", tint: "#30D158", icon: "checkmark.circle.fill" },
  idle: { label: "Idle", short: "idle", tint: "#8E8E93", icon: "moon.zzz.fill" },
  none: { label: "Idle", short: "idle", tint: "#8E8E93", icon: "terminal" },
};
const RANK = { needs: 0, ready: 1, working: 2, idle: 3, none: 4 };
const FILTERS = ["needs", "ready", "working", "idle"];
const TILE_WIDTH = 300;
const TILE_HEIGHT = 290;
const MAX_TABS = 6;

const [filter, setFilter] = signal("all");
const [cols, setCols] = signal(5);
// The workspace whose x was clicked and is waiting for the confirming click.
const [armed, setArmed] = signal(null);

function closeWorkspace(id) {
  setArmed(null);
  cmux("workspace.close", { workspace_id: id });
}

const epoch = () => data.clock()?.epoch ?? 0;

function ago(secs) {
  const m = Math.floor(Math.max(0, secs) / 60);
  if (m < 1) return "now";
  if (m < 60) return m + "m";
  if (m < 1440) return Math.floor(m / 60) + "h";
  return Math.floor(m / 1440) + "d";
}

// needs, working, ready, idle, or none for a tab that hosts no agent.
function tabInfo(w, t) {
  const mine = (w.agents ?? []).filter((a) => a.panelId === t.id && a.status !== "ended");
  const waiting = mine.find((a) => a.status === "needs_input");
  const working = mine.find((a) => a.status === "working");
  let state = "none";
  if (waiting) state = "needs";
  else if (working) state = "working";
  else if (t.hasUnread) state = "ready";
  else if (mine.length) state = "idle";
  const since = (waiting ?? working)?.sinceEpoch ?? null;
  return { id: t.id, title: t.title, surfaceId: t.surfaceId, workspaceId: w.id, state, since };
}

function workspaceState(w, tabs) {
  const has = (s) => tabs.some((t) => t.state === s);
  if (has("needs") || w.status === "needs-attention") return "needs";
  if (has("ready")) return "ready";
  if (has("working") || w.status === "working") return "working";
  if (w.status === "review") return "review";
  if (w.status === "done") return "done";
  return "idle";
}

// The workspace that only holds this tile view has nothing to report.
function isTileHost(w) {
  const tabs = w.tabs ?? [];
  return tabs.length === 1 && tabs[0].title === "workspace-tiles";
}

const tiles = computed(() => {
  const out = [];
  for (const w of data.workspaces() ?? []) {
    if (isTileHost(w)) continue;
    const tabs = (w.tabs ?? []).map((t) => tabInfo(w, t));
    const state = workspaceState(w, tabs);
    const count = (s) => tabs.filter((t) => t.state === s).length;
    // Tabs that need you first; the sort is stable, so tab order holds within a state.
    const ordered = tabs.slice().sort((a, b) => RANK[a.state] - RANK[b.state]);
    const message = w.latestMessage ?? "";
    const chips = [];
    if (tabs.length > 1) {
      for (const s of ["needs", "ready", "working"]) {
        if (count(s)) chips.push({ key: s, text: count(s) + " " + META[s].short, tint: META[s].tint });
      }
      const quiet = count("idle") + count("none");
      if (quiet) chips.push({ key: "idle", text: quiet + " idle", tint: META.idle.tint });
    }
    const details = [];
    const ref = w.pr?.label ?? w.branch ?? "";
    if (ref) details.push({ key: "ref", text: ref });
    if (chips.length) details.push({ key: "chips", text: "" });
    // The workspace-level status can come from a signal cmux does not tie to a tab.
    if (tabs.length > 1 && (state === "needs" || state === "working") && count(state) === 0) {
      details.push({ key: "note", text: "cmux did not report which tab" });
    }
    // A single-tab tile has room for its last message. Machine-generated
    // notices are markup, not something to read.
    if (tabs.length === 1 && message && !message.startsWith("<") && !message.startsWith("[")) {
      details.push({ key: "message", text: message });
    }
    out.push({
      key: w.id,
      w,
      state,
      tabs: ordered.slice(0, MAX_TABS),
      hidden: Math.max(0, ordered.length - MAX_TABS),
      chips,
      details,
    });
  }
  return out;
});

const countOf = (state) => tiles().filter((t) => t.state === state).length;
const visible = computed(() => (filter() === "all" ? tiles() : tiles().filter((t) => t.state === filter())));

// Rows keep their index as identity, so tiles update in place as states change.
const rows = computed(() => {
  const n = Math.max(1, cols());
  const list = visible();
  const out = [];
  for (let i = 0; i < list.length; i += n) out.push({ key: "row" + i / n, cells: list.slice(i, i + n) });
  return out;
});

// Left-align one view inside a VStack.
const lead = (view) => HStack({ spacing: 0 }, [view, Spacer({ minLength: 0 })]);

function tabRow(t) {
  const meta = () => META[t().state];
  const loud = () => t().state === "needs" || t().state === "ready";
  const quiet = () => t().state === "idle" || t().state === "none";
  return HStack({ spacing: 7 }, [
    Image(() => meta().icon).font(11).color(() => meta().tint).opacity(() => (quiet() ? 0.6 : 1))
      .frame({ width: 16 }),
    Text(() => t().title).font(13)
      .weight(() => (loud() ? "semibold" : "regular"))
      .color(() => (quiet() ? "secondary" : "primary"))
      .lineLimit(1).truncation("tail"),
    Spacer({ minLength: 0 }),
    Text(() => (quiet() ? "" : meta().short + (t().since ? " " + ago(epoch() - t().since) : "")))
      .font(10).monospaced().weight("semibold").color(() => meta().tint)
      .fixedSize().layoutPriority(2),
  ])
    .paddingHorizontal(4).paddingVertical(3)
    .cornerRadius(5)
    .background(() => (loud() ? meta().tint + "2e" : null))
    .hoverBackground("#7f7f7f33")
    .cursor("pointer")
    .contextMenu([
      Button("Close Tab", () => {
        if (t().surfaceId) cmux("surface.close", { surface_id: t().surfaceId, workspace_id: t().workspaceId });
      }).destructive(),
    ])
    .onTap(() => {
      cmux("workspace.select", { workspace_id: t().workspaceId });
      if (t().surfaceId) cmux("surface.focus", { surface_id: t().surfaceId, workspace_id: t().workspaceId });
    });
}

// One line under the title. The template runs once per key, so the key picks the shape.
function detail(c, d) {
  const key = d().key;
  if (key === "chips") {
    return HStack({ spacing: 10 }, [
      ForEach({ items: () => c().chips, key: (x) => x.key }, (x) =>
        Text(() => x().text).font(11).weight("semibold").color(() => x().tint).fixedSize()),
      Spacer({ minLength: 0 }),
    ]);
  }
  if (key === "ref") return lead(Text(() => d().text).font(11).monospaced().color("secondary").lineLimit(1));
  if (key === "note") {
    return lead(Text(() => d().text).font(11).italic().color(() => META[c().state].tint).lineLimit(1));
  }
  return lead(Text(() => d().text).font(12).color("secondary").lineLimit(2).truncation("tail"));
}

function tile(c) {
  const meta = () => META[c().state];
  const idle = () => c().state === "idle";
  const w = () => c().w;
  return VStack({ spacing: 0 }, [
    // Status band.
    HStack({ spacing: 6 }, [
      Image(() => meta().icon).font(12),
      Text(() => meta().label.toUpperCase()).font(13).weight("bold").lineLimit(1).fixedSize().layoutPriority(2),
      Spacer({ minLength: 0 }),
      Text(() => ((w().tabCount ?? 0) > 1 ? w().tabCount + " tabs" : "")).font(12).monospaced().weight("semibold").lineLimit(1).fixedSize(),
      Text(() => (w().unread > 0 ? String(w().unread) : ""))
        .font(11).monospaced().bold().color(() => meta().tint)
        .paddingHorizontal(() => (w().unread > 0 ? 6 : 0)).paddingVertical(1)
        .background(() => (w().unread > 0 ? "#FFFFFF" : null)).cornerRadius(8),
      Image("xmark").font(10).weight("bold")
        .padding(4).cornerRadius(9)
        .background("#00000033").hoverBackground("#FF453Acc")
        .cursor("pointer")
        .onTap(() => setArmed(armed() === c().key ? null : c().key)),
    ])
      .color(() => (idle() ? "#D0D0D6" : "#FFFFFF"))
      .padding(8)
      .frame({ maxWidth: "infinity" })
      .background(() => meta().tint + (idle() ? "4d" : "eb")),

    // Shown only after the x was clicked: closing ends the workspace's sessions.
    ForEach({ items: () => (armed() === c().key ? [{ key: "confirm" }] : []), key: (e) => e.key }, () =>
      HStack({ spacing: 8 }, [
        Text(() => "Close this workspace" + ((w().tabCount ?? 0) > 1 ? " and its " + w().tabCount + " tabs?" : "?"))
          .font(12).weight("semibold").color("#FFFFFF").lineLimit(1),
        Spacer({ minLength: 0 }),
        Text("Close").font(12).weight("bold").color("#FFFFFF")
          .paddingHorizontal(9).paddingVertical(3).cornerRadius(6)
          .background("#00000059").hoverBackground("#000000a6")
          .cursor("pointer").fixedSize().layoutPriority(2)
          .onTap(() => closeWorkspace(c().key)),
        Text("Keep").font(12).weight("semibold").color("#FFFFFF")
          .paddingHorizontal(9).paddingVertical(3).cornerRadius(6)
          .hoverBackground("#00000059")
          .cursor("pointer").fixedSize().layoutPriority(2)
          .onTap(() => setArmed(null)),
      ])
        .paddingHorizontal(8).paddingVertical(6)
        .frame({ maxWidth: "infinity" })
        .background("#FF453A")
    ),

    VStack({ spacing: 6 }, [
      lead(Text(() => w().title).font(15).weight("semibold").lineLimit(2).truncation("tail")),
      ForEach({ items: () => c().details, key: (d) => d.key }, (d) => detail(c, d)),
      Divider(),
      ForEach({ items: () => c().tabs, key: (t) => t.id }, (t) => tabRow(t)),
      ForEach({ items: () => (c().hidden ? [{ key: "more", n: c().hidden }] : []), key: (m) => m.key }, (m) =>
        lead(Text(() => "+" + m().n + " more tabs").font(11).color("tertiary"))),
      Spacer({ minLength: 0 }),
    ]).padding(10),
  ])
    .frame({ width: TILE_WIDTH, height: TILE_HEIGHT })
    .background(() => meta().tint + (idle() ? "12" : "26"))
    .cornerRadius(10)
    .borderColor(() => (w().selected ? "#FFFFFF" : c().state === "needs" ? meta().tint : "#8E8E934d"))
    .borderWidth(() => (w().selected || c().state === "needs" ? 2 : 1))
    .opacity(() => (idle() ? 0.8 : 1))
    .cursor("pointer")
    .contextMenu([
      Button("Close Workspace", () => closeWorkspace(c().key)).destructive(),
    ])
    .onTap(() => {
      setArmed(null);
      cmux("workspace.select", { workspace_id: c().key });
    });
}

// A header status: shows its count and filters the grid to that state.
function filterPill(key, label, tint, count) {
  const active = () => filter() === key;
  return HStack({ spacing: 6 }, [
    Circle({ size: 9 }).fill(tint),
    Text(() => count() + " " + label).font(13).weight("semibold"),
  ])
    .paddingHorizontal(10).paddingVertical(5)
    .cornerRadius(13)
    .background(() => (active() ? tint + "59" : "#7f7f7f1f"))
    .borderColor(() => (active() ? tint : "#00000000"))
    .borderWidth(1.5)
    .hoverBackground("#7f7f7f3d")
    .cursor("pointer")
    .onTap(() => setFilter(active() && key !== "all" ? "all" : key));
}

sidebar(() =>
  VStack({ spacing: 10 }, [
    HStack({ spacing: 10 }, [
      Text("Workspaces").font(18).bold(),
      filterPill("all", "all", "#FFFFFF", () => tiles().length),
      ...FILTERS.map((k) => filterPill(k, META[k].label.toLowerCase(), META[k].tint, () => countOf(k))),
      Spacer({ minLength: 0 }),
      Text("Columns").font(12).color("tertiary"),
      Button("-", () => setCols(Math.max(1, cols() - 1))),
      Text(() => String(cols())).font(12).monospaced(),
      Button("+", () => setCols(Math.min(8, cols() + 1))),
      Text(() => data.clock()?.time ?? "").font(12).monospaced().color("tertiary"),
    ]),
    Divider(),
    ForEach({ items: rows, key: (r) => r.key }, (r) =>
      HStack({ spacing: 10 }, [
        ForEach({ items: () => r().cells, key: (c) => c.key }, (c) => tile(c)),
        Spacer({ minLength: 0 }),
      ])
    ),
    ForEach({ items: () => (visible().length ? [] : [{ key: "empty" }]), key: (e) => e.key }, () =>
      lead(Text("No workspaces in this state.").font(13).color("tertiary"))),
    Spacer(),
  ]).padding(12)
)
