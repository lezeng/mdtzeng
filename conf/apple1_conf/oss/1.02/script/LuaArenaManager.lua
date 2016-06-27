
LuaArenaManager = LuaArenaManager or {}

require("script/debug")
require("script/ErrorCodes")

ConquestRankType = {
	"Conquest1",--神将
	"Conquest2",--名将
	"Conquest3",--天师
	"Conquest4",--武魁
	"Conquest5",--歃血
	"Conquest6",--最强
}
ConquestRankType = CreatEnumTable(ConquestRankType, 1)

ConquestSortTable = {
	ConquestRankType.Conquest3,
	ConquestRankType.Conquest4,
	ConquestRankType.Conquest2,
	ConquestRankType.Conquest1,
	ConquestRankType.Conquest5,
	ConquestRankType.Conquest6,
}

RankPlayerData = {
    "Id",       --玩家ID
    "Name",     --玩家名
    "Level",    --玩家等级
    "Cup",      --获得奖杯数
    "Power",    --战力
    "RankNum",	--排名
    "WinArenaPoint",--获胜获取的奖杯数量
    "HeadNum",  --头像
}
RankPlayerData = CreatEnumTable(RankPlayerData, 1)

RankListSpriteInfo ={
	{titleImg="sjb.png", color=ccc3(255,168,0), isShowButton=false},--参数1：排行榜图标；参数2：排行榜颜色；参数3：是否显示配置按钮
	{titleImg="mjb.png", color=ccc3(255,168,0), isShowButton=false},
	{titleImg="tsb.png", color=ccc3(204,0,255), isShowButton=true},
	{titleImg="wkb.png", color=ccc3(204,0,255), isShowButton=true},
	{titleImg="sxb.png", color=ccc3(0,255,255), isShowButton=true},
	{titleImg="qzb.png", color=ccc3(0,255,255), isShowButton=true},
}

PriseRankType = {
	"Arena",
	"Conquest",
}
PriseRankType = CreatEnumTable(PriseRankType, 1)

RadioType = {
    "Con_TianShi_Tactics",
    "Con_WuKui_Tactics",
    "Con_ShaXue_Vow",
    "Con_ZuiQiang_Vow",
}
RadioType = CreatEnumTable(RadioType, 1)

RadioInfoData = {
	"Id",
	"Info",
	"IsFree",	--是否可以免费刷新重置
}
RadioInfoData = CreatEnumTable(RadioInfoData, 1)

function LuaArenaManager.init( ... )
	if LuaArenaManager._init then return end
	LuaArenaManager._init = true

	LuaArenaManager.loadLocalConfig()
	LuaArenaManager.registeEvent()

	LuaArenaManager._rankData = {}
	LuaArenaManager.funIdList = {37020014,37020015,37020016,37020017,37020018,37020019}

	LuaArenaManager._isArenaDataLoaded = false
	LuaArenaManager._arenaRank = 0--竞技场排名
	LuaArenaManager._arenaScore = 0--竞技场积分
	LuaArenaManager._arenaUsedCount = 0--竞技场已挑战次数
	LuaArenaManager._arenaEnemyList = {}--竞技场对手列表
end

function LuaArenaManager.tryToLoadServerData( ... )
	if LuaArenaManager._isArenaDataLoaded then return end
	_sendRequest(Protocol.CS_GetArenaPlace, {}, false)
	_sendRequest(Protocol.CS_GetArenaPoint, {}, false)
	_sendRequest(Protocol.CS_GetArenaLimit, {}, false)
	_sendRequest(Protocol.CS_GetArenaRival, {}, true)
end

-- 载入本地的配置数据
function LuaArenaManager.loadLocalConfig()
    ConfigParse.loadConfig(LuaArenaManager, "_arenaRewardConfig", "arenaplacereward.txt", {"drop"})
    ConfigParse.loadConfig(LuaArenaManager, "_cupLevelConfig", "arenaCupLevel.txt", {"minCount", "maxCount", "levelA", "levelB"})
    ConfigParse.loadConfig(LuaArenaManager, "_conquestRewardConfig", "conquestrankreward.txt", {"type", "drop"})
    ConfigParse.loadConfig(LuaArenaManager, "_tacticsConfig", "tacticsShow.txt", {"id"})
    ConfigParse.loadConfig(LuaArenaManager, "_vowConfig", "vow.txt", {"id"})
    ConfigParse.loadConfig(LuaArenaManager, "_moodConfig", "mood.txt", {"type", "weight", "attack"})
end

-- 初始化部分数据
function LuaArenaManager.initRankDataOnce( ... )
	if LuaArenaManager.initRankDataOnceFlag then return end
	LuaArenaManager.initRankDataOnceFlag = true
	for k,v in pairs(LuaArenaManager._vowConfig) do
		local role = string.split(v.role, ";")
		local data = {}
		for i,soldierId in ipairs(role) do
			table.insert(data, LuaSoldierManager.findSoldierDataById(soldierId))
		end
		v.soldierList = data
		v.role = nil
	end
end

-- 获取指定id的策略数据
function LuaArenaManager.getTacticDataById( tacticId )
	if not LuaArenaManager._tacticsConfig then return end
	for k,v in pairs(LuaArenaManager._tacticsConfig) do
		if v.id == tacticId then
			return v
		end
	end
end

-- 获取指定id的誓约数据
function LuaArenaManager.getVowDataById( vowId )
	if not LuaArenaManager._vowConfig then return end
	for k,v in pairs(LuaArenaManager._vowConfig) do
		if v.id == vowId then
			v.count = 0
			for i,data in ipairs(v.soldierList) do
				if data.m_bown then
					v.count = v.count+1
				end
			end
			return v
		end
	end
end

-- 获取配置的最大排名奖励数量和对应奖励配置
function LuaArenaManager.getRankDataByType( priseType )
	local configData = LuaArenaManager._arenaRewardConfig

	if priseType == PriseRankType.Conquest then
		configData = {}
		for i,v in ipairs(LuaArenaManager._conquestRewardConfig) do
			if v.type == priseType then
				table.insert(configData, v)
			end
		end
	end

	local maxRank = 0
	for i,v in ipairs(configData) do
		local rankTable = string.split(v.place,";")
        for i=1,#rankTable do
        	if maxRank < tonumber(rankTable[i]) then
        		maxRank = tonumber(rankTable[i])
        	end
        end
	end

	return maxRank, configData
end

-- 根据竞技场奖杯数量获取分级信息图片
function LuaArenaManager.getRankCupImages( cupCount )
	local levelA = 1--1，铜；2，银；3，金；4，钻石
	local levelB = 5--等级从5到1
	local minCupCount = 1--获得钻石的最小奖杯数
	if LuaArenaManager._cupLevelConfig then
		for i,v in ipairs(LuaArenaManager._cupLevelConfig) do
			if cupCount >= v.minCount and cupCount <= v.maxCount then
				levelA = v.levelA
				levelB = v.levelB
			end
			if minCupCount < v.maxCount then
				minCupCount = v.maxCount
			end
		end
	end

	-- 达到钻石的奖杯数
	if cupCount > minCupCount then
		return CCSpriteFrameCache:sharedSpriteFrameCache():spriteFrameByName("zsb.png")
	end

	local frameName = "tb.png"
	if levelA == 2 then
		frameName = "yb.png"
	elseif levelA == 3 then
		frameName = "jb.png"
	end

	local frameA = CCSpriteFrameCache:sharedSpriteFrameCache():spriteFrameByName(frameName)
	local frameB = CCSpriteFrameCache:sharedSpriteFrameCache():spriteFrameByName(levelB.."jb.png")

	return frameA,frameB
end

function LuaArenaManager.registeEvent()
    LuaArenaManager.eventProxy = MyLuaProxy.newProxy("LuaArenaManager.lua")

    function onLuaArenaManagerMsg(msgId, _json)
	    local data = json.decode(_json)
	    -- dump(data)
	    if msgId == Protocol.SC_GetConquestPlace then
	    	if data.rtn == 0 then
	    		print("设置玩家排名")
	    		LuaArenaManager.setPlayerRankByType(data.type, data.pos)
	    	end

	    elseif msgId == Protocol.SC_GetConquestRank then
	    	if data.rtn == 0 then
	    		print("设置排名数据")
    			LuaArenaManager.setRankInfoByType(data.type, data.info)
	    	end

	    elseif msgId == Protocol.SC_GetConquestRival then
	    	if data.rtn == 0 then
	    		LuaArenaManager.setEnemyInfoByType(data.type, data.info)
	    	end

	    elseif msgId == Protocol.SC_GetArenaRankList then
	    	if data.rtn == 0 then
	    		LuaArenaManager.arenaEnemyInfo = data.info
	    		print("获取到竞技场对手列表信息")
	    		dump(LuaArenaManager.arenaEnemyInfo)
	    	end

	    elseif msgId == Protocol.SC_GetRadio then
	    	print("收到单选数据")
    		LuaArenaManager.rankSettingList = data.info
    		dump(LuaArenaManager.rankSettingList)

	    elseif msgId == Protocol.SC_NotifyRadio then
	    	print("通知单选变动")
	    	if data.rtn == 0 then
		    	if LuaArenaManager.rankSettingList and LuaArenaManager.rankSettingList[data.type] then
		    		-- 服务器会设置一次免费刷新次数，在处理该逻辑后，收到正确的通知，客户端自己清除免费次数
		    		LuaArenaManager.rankSettingList[data.type] = {data.id, data.info, 0}
		    		dump(LuaArenaManager.rankSettingList)
		    	end
		    end

        elseif msgId == Protocol.SC_BuyResetCount then
            if data.rtn == 0 then
            	LuaCountManager.addResetCountByType(CountType.Radio, radioType)
            end

        elseif msgId == Protocol.SC_GetArenaPlace then
        	if data.rtn == ErrorCode.OK then
        		LuaArenaManager._arenaRank = data.pos
        	end

        elseif msgId == Protocol.SC_GetArenaPoint then
        	if data.rtn == ErrorCode.OK then
        		LuaArenaManager._arenaScore = data.num
        	end

        elseif msgId == Protocol.SC_GetArenaLimit then
        	if data.rtn == ErrorCode.OK then
        		LuaArenaManager._arenaUsedCount = data.num
        	end

        elseif msgId == Protocol.SC_GetArenaRival then
        	if data.rtn == ErrorCode.OK then
        		LuaArenaManager._arenaEnemyList = data.info
        		if not LuaArenaManager._arenaEnemyList then
        			LuaArenaManager._arenaEnemyList = {}
        		end
        		LuaArenaManager._isArenaDataLoaded = true
        	end

	    end
	end

    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_GetArenaPlace, "onLuaArenaManagerMsg")
    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_GetArenaPoint, "onLuaArenaManagerMsg")
    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_GetArenaLimit, "onLuaArenaManagerMsg")
    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_GetArenaRival, "onLuaArenaManagerMsg")

    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_GetConquestPlace, "onLuaArenaManagerMsg")
    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_GetConquestRank, "onLuaArenaManagerMsg")
    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_GetConquestRival, "onLuaArenaManagerMsg")
    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_GetArenaRankList, "onLuaArenaManagerMsg")

    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_GetRadio, "onLuaArenaManagerMsg")
    LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_NotifyRadio, "onLuaArenaManagerMsg")
    -- 服务器有主动更新次数消息，不用手动增加重置次数
    -- LuaArenaManager.eventProxy:addMsgListener( Protocol.SC_BuyResetCount, "onLuaUIRankSelectMsg")
end

function LuaArenaManager.setPlayerRankByType( rankType, rankPos )
	for i,v in ipairs(LuaArenaManager._rankData) do
		if v.type == rankType then
			if v.pos and v.pos < rankPos then
				LuaArenaManager.rankChangeCount = rankPos
			end
			v.pos = rankPos
			return
		end
	end
	-- 没有数据，则新建对应类型
	table.insert(LuaArenaManager._rankData, {type=rankType, pos=rankPos})

	-- 本次战斗是否排名发生变化，仅限“最近的一次”战斗状态记录
	LuaArenaManager.rankChangeCount = rankPos
end
-- 获取玩家风云争霸的排名
function LuaArenaManager.getPlayerRankByType( rankType )
	for i,v in ipairs(LuaArenaManager._rankData) do
		if v.type == rankType then
			return v.pos
		end
	end
end


function LuaArenaManager.setRankInfoByType( rankType, rankInfo )
	for i,v in ipairs(LuaArenaManager._rankData) do
		if v.type == rankType then
			v.rankList = rankInfo
			return
		end
	end
	table.insert(LuaArenaManager._rankData, {type=rankType, rankList=rankInfo})
end
-- 获取风云争霸排行榜数据
function LuaArenaManager.getRankInfoByType( rankType )
	for i,v in ipairs(LuaArenaManager._rankData) do
		if v.type == rankType then
			return v.rankList
		end
	end
end

-- 设置排行榜对手（经过排序）
function LuaArenaManager.setEnemyInfoByType( rankType, enemyInfo )
	table.sort(enemyInfo, function( one, two )
		if one[RankPlayerData.RankNum] < two[RankPlayerData.RankNum] then
			return true
		end
	end)

	for i,v in ipairs(LuaArenaManager._rankData) do
		if v.type == rankType then
			v.enemyList = enemyInfo
			return
		end
	end
	table.insert(LuaArenaManager._rankData, {type=rankType, enemyList=enemyInfo})
end
-- 获取风云争霸对手数据
function LuaArenaManager.getRankEnemyInfo()
	for i,v in ipairs(LuaArenaManager._rankData) do
		if v.type == LuaArenaManager.curRankType then
			return v.enemyList
		end
	end
end
-- 清除风云争霸缓存对手数据
function LuaArenaManager.clearRankEnemyInfo( ... )
	for i,v in ipairs(LuaArenaManager._rankData) do
		v.enemyList = nil
	end
end

function LuaArenaManager.setCurSelectRankType( rankType )
	LuaArenaManager.curRankType = rankType
end

function LuaArenaManager.getCurSelectRankType( ... )
	return LuaArenaManager.curRankType
end

-- 获取策略配置和誓约配置
function LuaArenaManager.getRankSetting( ... )
	local rankType = LuaArenaManager.curRankType

	-- 针对服务器逻辑处理类型的修正，单选类型
	local radioType = LuaArenaManager.getFixRadiotype()
	print("排行榜类型"..rankType)
	print("单选类型"..radioType)
	if radioType >= RadioType.Con_TianShi_Tactics and radioType <= RadioType.Con_ZuiQiang_Vow then
		if LuaArenaManager.rankSettingList then
			print("返回单选数据")
			return LuaArenaManager.rankSettingList[radioType]
		else
			print("获取单选")
			_sendRequest(Protocol.CS_GetRadio, {}, true)
		end
	else
		-- 非NIL数据，表示没有特殊设置数据
		return ""
	end
end

-- 重置（刷新）策略/誓约
function LuaArenaManager.resetRankSetting( ... )
	print("重置单选")

	local playerData = PlayerMgr.getSingleton():playerWithDBId("", nil)
    local vipInfo = VipConfMgr.getSingleton():getVipByLevel(playerData.curVIPRank)
    if not vipInfo then
        _openWarning("vip数据错误")
        return
    end

    local radioType = LuaArenaManager.getFixRadiotype()
	local countData = LuaCountManager.getCountDataByType(CountType.Radio, radioType)

    local resetedCount = 0
    if countData then
    	resetedCount = countData[CountAttr.Reset]
    end
    local totalCount = 0
    local resetType = nil

	local rankType = LuaArenaManager.curRankType
    if rankType == ConquestRankType.Conquest3 or rankType == ConquestRankType.Conquest4 then
    	totalCount = vipInfo.tactics
    	resetType = ResetCostType.Tactics
    elseif rankType == ConquestRankType.Conquest5 or rankType == ConquestRankType.Conquest6 then
    	totalCount = vipInfo.vow
    	resetType = ResetCostType.Vow
    end

    if not resetType then return end
    local remainCount = totalCount - resetedCount

    if remainCount <= 0 then
        warningCallBack = nil
        function warningCallBack( )
            UIManager:getSingleton():openShop()
        end
        UIManager:getSingleton():openRechargeWarningForLua("重置次数不足，充值VIP可以获得更多重置次数","充值")
    else
        local cost = ResetCostManager:getSingleton():getCostByType(resetType, resetedCount+1)

        warningCallBack = nil
        function warningCallBack( )
            print("确认重置回调")
            if playerData.GOLD < cost then
                UIManager:getSingleton():showOpenShopPage()
                return
            end

			_sendRequest(Protocol.CS_BuyResetCount, {type=ResetCostType.Radio,attr=radioType}, true)
        end
        UIManager:getSingleton():openPayWarningForLua("是否花费"..cost.."元宝刷新?",remainCount,totalCount,"刷新")
    end
end

-- 保存已选择的策略/誓约
function LuaArenaManager.saveRankSetting( targetId )
	print("保存单选")
	local radioType = LuaArenaManager.getFixRadiotype()
	_sendRequest(Protocol.CS_SetRadio, {type=radioType, id=targetId}, true)
end

function LuaArenaManager.getFixRadiotype( )
	return LuaArenaManager.curRankType - ConquestRankType.Conquest3 + RadioType.Con_TianShi_Tactics
end

-- 记录上一次选择的榜单
function LuaArenaManager.setLastSelectRankType( rankType )
	LuaArenaManager.lastRankType = rankType
end

-- 获取对应心情的文字描述
function LuaArenaManager.getMoodChangeDescByType( moodType )
	local value = 0
	local name = ""
	for k,v in pairs(LuaArenaManager._moodConfig) do
		if v.type == moodType then
			name = v.describe
			value = v.attack
			break
		end
	end

	if value > 0 then
		value = value/10000*100
		str = "伤害增加"..value.."%"
	elseif value < 0 then
		value = math.abs(value)/10000*100
		str = "伤害减少"..value.."%"
	else
		str = "没有影响"
	end

	return name.."：     "..str
end

-- 指定风云争霸排行榜是否已开启
function LuaArenaManager.isRankOpen( rankType )
	return FunctionAvaliableManager:getSingleton():curStateOfFunctionForLua(LuaArenaManager.funIdList[rankType]) ~= 0
end

-- 获取榜单未开启提示图片名字
function LuaArenaManager.getRankLockImageName( rankType )
	return FunctionAvaliableManager:getSingleton():getLockImageName(LuaArenaManager.funIdList[rankType])
end

-- 获取榜单奖励翻倍系数
function LuaArenaManager.getRankRewardFactor( rankType )
	local rankCount = 0
	for k,v in pairs(LuaArenaManager._rankData) do
		if v.pos ~= 0 then
			rankCount = rankCount + 1
		end
	end
	-- 如果都还没有排名
	if rankCount == 0 then return 1 end

	table.sort(LuaArenaManager._rankData, function(one, two)
		if one.pos ~= 0 and two.pos == 0 then return true end
		if one.pos == 0 and two.pos ~= 0 then return false end
		if one.pos < two.pos then return true end
		if one.pos > two.pos then return false end
		
		local openIndexA,openIndexB = 0,0
		for i,v in ipairs(ConquestSortTable) do
			if v == one.type then openIndexA = i end
			if v == two.type then openIndexB = i end
		end
		if openIndexA < openIndexB then return true end
		return false
		end)

	local maxPos = 0
	for i,v in pairs(LuaArenaManager._rankData) do
		if v.type == rankType then maxPos = i end
	end
	if maxPos == 1 then return 2
	elseif maxPos == 2 and rankCount >= 2 then return 1.6
	else return 1
	end
end

function LuaArenaManager.getRankFightCount( )
	local radioType = LuaArenaManager.getFixRadiotype()
	local countData = LuaCountManager.getCountDataByType(CountType.Radio, radioType)
	if countData then
		dump(countData)
		return countData[CountAttr.Count]
	end
	return 0
end

function LuaArenaManager_isShowArenaNotify( ... )
	if utils.isFunctionCloseByType(FunctionAvaliableType.Arena) then
		return false
	end
	return LuaArenaManager._arenaUsedCount <= 0
end

LuaArenaManager.init()
