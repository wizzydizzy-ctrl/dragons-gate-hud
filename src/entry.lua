if DGHUD and DGHUD.shutdown then pcall(DGHUD.shutdown) end
local moduleNames={"defaults","command_parser","command_collector","chat_parser","navigation","state","settings","sha256","release","events","layout","view","mudlet_adapter","main","updater"}
for _,name in ipairs(moduleNames) do package.loaded[name]=nil end
DGHUD = {}
local defaults=require("defaults")
local Settings=require("settings")
local Adapter=require("mudlet_adapter")
local Main=require("main")
local Updater=require("updater")
DGHUD.settings=Settings.merge(defaults,DGHUD.user_settings or {})
DGHUD.controller=Main.new(Adapter.new(),DGHUD.settings)
DGHUD.updater=Updater.new(DGHUD.controller.adapter,DGHUD.settings)
DGHUD.controller.updater=DGHUD.updater
function DGHUD.start() return DGHUD.controller:start() end
function DGHUD.shutdown() return DGHUD.controller:shutdown() end
function DGHUD.reload() return DGHUD.controller:reload() end
function DGHUD.healthCheck() return DGHUD.controller:healthCheck() end
DGHUD.start()
