return {
  schema = 1,
  package_name = "DragonsGateHUD",
  version = "0.1.0",
  layout = { left_width = 190, right_width = 270, min_console_width = 520 },
  theme = { background="#080b0a", panel="#0d1210", border="#423825", text="#d7d0bf", muted="#75857c", accent="#e0b56c", jade="#79b386", hp="#ba5147", fatigue="#8bad4e" },
  panels = { character=true, vitals=true, room=true, currency=true },
  github = { owner="wizzydizzy-ctrl", repository="dragons-gate-hud", channel="stable" },
  update = { auto_check=false, auto_apply=false, timeout_seconds=30, manifest_limit=65536, package_limit=10485760 }
}
