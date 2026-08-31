local Settings = require("settings")
local defaults = require("defaults")

test("merges nested overrides without changing defaults", function()
  local defaults={schema=1,theme={accent="#aa8844",panel="#111111"},github={owner="OWNER"}}
  local merged=Settings.merge(defaults,{theme={accent="#00ff00"},custom="keep"})
  eq(merged.theme.accent,"#00ff00"); eq(merged.theme.panel,"#111111"); eq(merged.custom,"keep"); eq(defaults.theme.accent,"#aa8844")
end)

test("migrates schema zero while preserving unknown keys", function()
  local migrated,changed=Settings.migrate({schema=0,auto_update=true,personal="untouched"})
  eq(changed,true); eq(migrated.schema,1); eq(migrated.update.auto_apply,false); eq(migrated.personal,"untouched")
end)

test("chat settings retain defaults around migrated user overrides",function()
  local user={schema=0,auto_update=true,personal="untouched",chat={height_percent=.25,personal_option="keep"}}
  local migrated,changed=Settings.migrate(user)
  local merged=Settings.merge(defaults,migrated)
  eq(changed,true); eq(merged.chat.enabled,true); eq(merged.chat.height_percent,.25); eq(merged.chat.target_height,240)
  eq(merged.chat.min_height,160); eq(merged.chat.max_height,320); eq(merged.chat.visible_limit,1000)
  eq(merged.chat.dedupe_seconds,3); eq(merged.chat.timestamps,true); eq(merged.chat.personal_option,"keep")
  eq(merged.personal,"untouched"); eq(user.chat.personal_option,"keep")
end)

test("resolves migrated chat settings without discarding user keys",function()
  local resolved,migrated,changed=Settings.resolve(defaults,{schema=0,chat={timestamps=false,personal_option="keep"},personal="untouched"})
  eq(changed,true); eq(resolved.chat.timestamps,false); eq(resolved.chat.visible_limit,1000)
  eq(migrated.chat.personal_option,"keep"); eq(resolved.personal,"untouched")
end)
