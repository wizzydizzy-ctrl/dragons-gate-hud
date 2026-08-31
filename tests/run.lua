local root = arg[0]:match("^(.*)/tests/run%.lua$") or "."
package.path = root .. "/src/?.lua;" .. root .. "/tests/lua/?.lua;" .. package.path

local total, failed = 0, 0
function test(name, fn)
  total = total + 1
  local ok, err = pcall(fn)
  if ok then print("ok " .. total .. " - " .. name) else failed = failed + 1; print("not ok " .. total .. " - " .. name .. "\n  " .. tostring(err)) end
end
function eq(actual, expected)
  if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

dofile(root .. "/tests/lua/test_command_parser.lua")
dofile(root .. "/tests/lua/test_command_collector.lua")
dofile(root .. "/tests/lua/test_navigation.lua")
dofile(root .. "/tests/lua/test_state.lua")
dofile(root .. "/tests/lua/test_settings.lua")
dofile(root .. "/tests/lua/test_sha256.lua")
dofile(root .. "/tests/lua/test_release.lua")
dofile(root .. "/tests/lua/test_runtime.lua")
dofile(root .. "/tests/lua/test_updater.lua")
dofile(root .. "/tests/lua/test_layout.lua")
dofile(root .. "/tests/lua/test_view.lua")
dofile(root .. "/tests/lua/test_chat_parser.lua")
dofile(root .. "/tests/lua/test_chat_history.lua")
dofile(root .. "/tests/lua/test_chat_storage.lua")

print(string.format("%d tests, %d failures", total, failed))
os.exit(failed == 0 and 0 or 1)
