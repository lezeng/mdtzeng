
require("script/debug")

LuaScienceManager = LuaScienceManager or {}

function LuaScienceManager.init( ... )
	if LuaScienceManager._init then return end
	LuaScienceManager._init = true
end

LuaScienceManager.init()
