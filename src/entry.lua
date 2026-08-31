local previous=rawget(_G,"DGHUD")
local userSettings=previous and previous.user_settings
if previous and previous.shutdown then pcall(previous.shutdown) end
local moduleNames={"defaults","command_parser","command_collector","chat_parser","chat_history","chat_storage","chat_controller","navigation","state","settings","sha256","release","events","layout","view","mudlet_adapter","main","updater"}
for _,name in ipairs(moduleNames) do package.loaded[name]=nil end
DGHUD = {}
local defaults=require("defaults")
local Settings=require("settings")
local Adapter=require("mudlet_adapter")
local Main=require("main")
local Updater=require("updater")
local Storage=require("chat_storage")
local resolvedSettings,migratedSettings=Settings.resolve(defaults,userSettings or {})
DGHUD.user_settings=migratedSettings
DGHUD.settings=resolvedSettings
DGHUD.chatStorageApi=Storage.mudletApi()
DGHUD.controller=Main.new(Adapter.new(),DGHUD.settings)
DGHUD.updater=Updater.new(DGHUD.controller.adapter,DGHUD.settings)
DGHUD.controller.updater=DGHUD.updater
Main.installChatApi(DGHUD)
function DGHUD.start() return DGHUD.controller:start() end
function DGHUD.shutdown() return DGHUD.controller:shutdown() end
function DGHUD.reload() return DGHUD.controller:reload() end
function DGHUD.healthCheck() return DGHUD.controller:healthCheck() end
DGHUD.start()
