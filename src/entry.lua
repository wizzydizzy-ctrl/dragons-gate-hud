DGHUD = DGHUD or {}
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
