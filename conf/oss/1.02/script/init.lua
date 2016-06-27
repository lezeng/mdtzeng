--
-- Author: JasonTai(taijcjc@gmail.com)
-- Date: 2015-02-11 19:24:07
--
function preload()
	require("script/ConfigParse")
	require("script/utils")
	require("script/extern")
	require("script/TextArea")
	
	require("script/ConfigManager")

	require("script/LuaSoldierManager")
	require("script/LuaMapManager")
	require("script/LuaFormationManager")
	require("script/TaskManager")
	require("script/LuaCDManager")
	require("script/LuaResBattleManager")
	require("script/LuaCountManager")
	require("script/LuaItemManager")
	require("script/LuaDropManager")
	require("script/LuaEveryDayManager")
	require("script/LuaUITavern")
	require("script/LuaArenaManager")
	require("script/LuaGirlManager")
	require("script/LuaRushManager")
	require("script/resBattle/ResBattleReportManager")
	require("script/LuaMarketManager")
	require("script/LuaEquipUpManager")
	require("script/LuaActivityManager")
	require("script/LuaVipManager")
	require("script/LuaSignManager")
	require("script/LuaChallengeManager") 
	require("script/Game")
end

xpcall(preload, __G__TRACKBACK__)


--require("script/LoadLevyCoinConfig")
