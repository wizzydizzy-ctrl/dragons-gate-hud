local Events={}
Events.gmcp={"gmcp.Char.Status","gmcp.Char.Vitals","gmcp.Room.Players"}
Events.mapper={room="gmcp.Room.Info",wrong="gmcp.Room.WrongDir",outgoing="sysDataSendRequest",disconnect="sysDisconnectionEvent"}
Events.aliases={"^dghud check$","^dghud update$","^dghud reload$","^dghud config$","^dghud purge$","^dghud chatstatus$","^walkto\\s+(\\d+)$","^walkstop$","^mapcenter$"}
return Events
