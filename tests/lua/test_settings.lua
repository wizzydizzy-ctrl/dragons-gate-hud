local Settings = require("settings")

test("merges nested overrides without changing defaults", function()
  local defaults={schema=1,theme={accent="#aa8844",panel="#111111"},github={owner="OWNER"}}
  local merged=Settings.merge(defaults,{theme={accent="#00ff00"},custom="keep"})
  eq(merged.theme.accent,"#00ff00"); eq(merged.theme.panel,"#111111"); eq(merged.custom,"keep"); eq(defaults.theme.accent,"#aa8844")
end)

test("migrates schema zero while preserving unknown keys", function()
  local migrated,changed=Settings.migrate({schema=0,auto_update=true,personal="untouched"})
  eq(changed,true); eq(migrated.schema,1); eq(migrated.update.auto_apply,false); eq(migrated.personal,"untouched")
end)
