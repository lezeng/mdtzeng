--
-- Author: JasonTai(taijcjc@gmail.com)
-- Date: 2015-01-20 16:19:23
--

LuaFormationManager = LuaFormationManager or {}

require("script/debug")
require("script/UserInfoManager")

function LuaFormationManager.init( ... )
	if LuaFormationManager._init then return end
	LuaFormationManager._init = true

	LuaFormationManager._LoadedFormation = {}
	LuaFormationManager._ServerSavedFormation = {}
	LuaFormationManager._formationIdMap = {}

	LuaFormationManager.loadLocalConfig()
	LuaFormationManager.registeEvent()
end

-- 载入本地的配置数据
function LuaFormationManager.loadLocalConfig()
	ConfigParse.loadConfig(LuaFormationManager, "_FormationData", "fromation.txt", {"id", "index", "level", "pos", "statusid", "random", "tactics"})
	ConfigParse.loadConfig(LuaFormationManager, "_FormationLimitData", "openformation.txt", {"id", "level"})
	ConfigParse.loadConfig(LuaFormationManager, "_ValidPosCount", "fromationlimit.txt", {"level", "num"})
	ConfigParse.loadConfig(LuaFormationManager, "_Tactics", "formationtactics.txt", {"id", "index", "pos"})
	ConfigParse.loadConfig(LuaFormationManager, "MoneyDataConfig", "technology.txt", {"curformation", "levellimit", "nextformation", "money"})

	LuaFormationManager._idMap = {}
	local _formation         = {}
	local curFormationName   = nil -- 当前阵型的名称
	local curFormation       = nil -- 当前阵型的table
	local curFomrationId     = nil -- 当前阵型的id(每个阵型会随着等级变化而改变id)
	local curFormationLevel  = nil -- 当前阵型不同等级的数据
	local curFormationStatus = nil -- 当前阵型当前等级的status数组
	local mapIndex           = 0   -- 当前的mapIndex
	for i,v in ipairs(LuaFormationManager._FormationData) do
		if curFormationName ~= v.name then

			-- 新建一个formation table
			curFormation         = {}
			mapIndex             = mapIndex + 1
			-- 存储到数组中
			curFormation.name    = v.name
			curFormation.index   = v.index
			curFormation.tactics = v.tactics
			curFormationName     = v.name
			curFormation.levels  = {}
			curFormation.startId = v.id
			_formation[curFormation.index]  = curFormation
		end

		if curFormationId ~= v.id then
			-- 如果id变化了 说明到了一个新的阵型等级
			curFormationLevel                         = {}
			curFormationLevel.status                  = {}  -- buff数组
			curFormationLevel.id                      = v.id
			curFormationId                            = v.id
			curFormation.levels[v.level]    = curFormationLevel
		end

		local state                               = {}
		state.memo                                = v.memo
		state.statusid                            = v.statusid

		-- 修改阵型的数据结构
		if v.random > 0 then
			if not curFormationLevel.status[v.pos] then
				curFormationLevel.status[v.pos] = {}
			end
			table.insert(curFormationLevel.status[v.pos], state)
		end
		LuaFormationManager._idMap[v.id] = v.index
	end
	LuaFormationManager._ParsedFormationData = _formation

	-- loadTactics匹配的是key:pos value:index
	for k,_v in pairs(LuaFormationManager._ParsedFormationData) do
		local tactics = _v.tactics
		local tacticsData = {}
		for i,v in ipairs(LuaFormationManager._Tactics) do
			if v.id == tactics then
				tacticsData[v.pos] = v.index
			end
		end
		_v.tacticsData = tacticsData
	end
end

-- 获取第几个阵型（index）的开放等级
function LuaFormationManager.getFormationOpenLevel( index )
	local startId = 0
	for k,v in ipairs(LuaFormationManager._ParsedFormationData) do
		if v.index == index then
			startId = v.startId
			break
		end
	end
	for k,v in ipairs(LuaFormationManager._FormationLimitData) do
		if startId == v.id then
			return v.level
		end
	end
end

-- 返回第几个阵型（index）的当前阵型ID
function LuaFormationManager.formationIdOfIndex( index )
	return LuaFormationManager._formationIdMap[index]
end

-- 更新当前各阵型可使用等级的阵型ID表
function LuaFormationManager.loadFormationIdMapFromServer( data )
	for i,v in ipairs(data) do
		local mapIndex = LuaFormationManager._idMap[tonumber(v)]
		LuaFormationManager._formationIdMap[mapIndex] = v
	end
end

-- _LoadedFormation用于记录资源战阵型的使用情况，为true表示对应阵型处于占领中
function LuaFormationManager.addLoadedFormation( flag )
	LuaFormationManager._LoadedFormation[flag] = true
end
function LuaFormationManager.deleteLoadedFormation( flag )
	LuaFormationManager._LoadedFormation[flag] = nil
end
function LuaFormationManager.isLoadedFormation( flag )
	return LuaFormationManager._LoadedFormation[flag]
end


-- 根据阵型id 返回阵型的status信息 还有名称
function LuaFormationManager.findFormationInfoById( formationId )
	local mapId = tonumber(formationId)
	local mapIndex     = LuaFormationManager._idMap[tonumber(mapId)]
	local mapLevels    = LuaFormationManager._ParsedFormationData[mapIndex]
	if mapLevels then
		for k,v in pairs(mapLevels.levels) do
			if v.id == mapId then
				local r = {}
				for _k,_v in pairs(v) do
					r[_k] = _v
				end
				r.name = mapLevels.name
				r.index = mapLevels.index
				r.startId = mapLevels.startId
				r.tacticsData = mapLevels.tacticsData
				return r
			end
		end
	end
end

-- 根据阵型的flag返回阵型的信息 包括阵型上面已经安排的武将信息
function LuaFormationManager.findFormationInfoByFlag( flag )
	local serverData = LuaFormationManager._ServerSavedFormation[tonumber(flag)]
	return serverData
end

-- 加载服务器返回的数据 并且修正
function LuaFormationManager.loadServerFormation( data )
	for i,v in ipairs(data) do
		LuaFormationManager._ServerSavedFormation[tonumber(v.flag)] = v
		v.fomrmationInfo = LuaFormationManager.findFormationInfoById(v.id)
		v.soldiers = v.info
		v.info = nil
	end
	LuaFormationManager.checkFormPosAvaliable()
end

-- 把data中的数据存储到本地
function LuaFormationManager.saveServerFormation( data )
	LuaFormationManager._ServerSavedFormation[tonumber(data.flag)] = data
	LuaFormationManager.checkFormPosAvaliable()
end

-- 获取这些flag下面已经上真的武将id
function LuaFormationManager.loadedSoldierIds(flagArray)
	local r = {}
	for i,v in ipairs(flagArray) do
		local info = LuaFormationManager._ServerSavedFormation[v]
		if info and info.soldiers then
			for _i,_v in ipairs(info.soldiers) do
				if _v ~= 0 then
					-- table.insert(r, _v)
					if not r[_v] then
						r[_v] = v
					end
				end
			end
		end
	end
	return r
end

-- 判断该武将（在指定阵型中）是否上阵
function LuaFormationManager.isLoadedSoldier( soldierId, formType )
	for k,v in pairs(LuaFormationManager._ServerSavedFormation) do
		if formType then
			if formType == k then
				for _i,_v in ipairs(v.soldiers) do
					if tonumber(_v) == tonumber(soldierId) then
						return true
					end
				end
			end
		else
			for _i,_v in ipairs(v.soldiers) do
				if tonumber(_v) == tonumber(soldierId) then
					return true
				end
			end
		end
	end
	return false
end


-- 判断该武将是pvp的上阵武将
function LuaFormationManager.isPveLoadedSoldier( soldierId )
	local r = {}
	local v = LuaFormationManager.findFormationInfoByFlag(1)
	for _i,_v in ipairs(v.soldiers) do
		if tonumber(_v) == tonumber(soldierId) then
			return true
		end
	end
	return false
end

-- 当前已经开放的map
function LuaFormationManager.validFormationMapIndex()
	local r = {}
	local curLevel = UserInfoManager.userLevel()
	for i,v in ipairs(LuaFormationManager._FormationLimitData) do
		if v.level <= curLevel then
			local mapIndex = LuaFormationManager._idMap[v.id]
			table.insert(r, mapIndex)
		end
	end

	return r
end

-- 当前可以上阵的个数
function LuaFormationManager.curValidPosCount(formType)
	if formType then
		if formType == FormationUseType.Conquest5 then
			return 3
		elseif formType == FormationUseType.Conquest6 then
			return 1
		end
	end
	return LuaFormationManager.validCountOfLevel( UserInfoManager.userLevel() )
end

-- 获取指定等级可以上阵的武将数量
function LuaFormationManager.validCountOfLevel( level )
	for i,v in ipairs(LuaFormationManager._ValidPosCount) do
		if v.level == level then
			return v.num
		end
	end
	return 9
end

-- @10/16 ZLu 获取下一级别可以上阵的人数信息
function LuaFormationManager.getNextValidCountInfo()
	local curCount = LuaFormationManager.validCountOfLevel(UserInfoManager.userLevel())
	local targetLevel = 0
	local targetCount = 0

	for i,v in ipairs(LuaFormationManager._ValidPosCount) do
		if v.num > curCount then
			targetLevel = v.level
			targetCount = v.num
			break
		end
	end
	return targetLevel,targetCount
end

-- 判断资源战阵型是不是没有武将上阵
function LuaFormationManager.resBattleFormationIsBlanc()
	local isBlanc = true
	for i=1,3 do
		local flag = FormationUseType["Resource" .. i]
		local info = LuaFormationManager._ServerSavedFormation[flag]
		if info and info.soldiers then
			for _i,_v in ipairs(info.soldiers) do
				if _v ~= 0 then
					isBlanc = false
					break
				end
			end
			if not isBlanc then
				break
			end
		end
	end
	return isBlanc
end

-- 返回征战阵型的上阵武将列表
function LuaFormationManager.monsterFormSoldiers()
	local formation = LuaFormationManager.findFormationInfoByFlag(FormationUseType.Monster)
	local soldiers = {}
	for i,v in ipairs(formation.soldiers) do
		if v ~= 0 then
			local soldier = LuaSoldierManager.findSoldierDataById(tonumber(v))
			table.insert(soldiers, soldier)
		end
	end
	return soldiers
end

-- 返回竞技场阵型的上阵武将列表
function LuaFormationManager.arenaFormSoldiers()
	local formation = LuaFormationManager.findFormationInfoByFlag(FormationUseType.Arena)
	local soldiers = {}
	for i,v in ipairs(formation.soldiers) do
		if v ~= 0 then
			local soldier = LuaSoldierManager.findSoldierDataById(tonumber(v))
			table.insert(soldiers, soldier)
		end
	end
	return soldiers
end

-- 设置阵型ID（科技升级后改变阵型ID）
function LuaFormationManager.upgradeFormId( oldId, newId )
	if not oldId or not newId then return end
	for k,v in pairs(LuaFormationManager._formationIdMap) do
		if v == oldId then
			LuaFormationManager._formationIdMap[k] = newId
			break
		end
	end
	-- 同时更新当前记录的正在使用的阵型数据
	for k,v in pairs(LuaFormationManager._ServerSavedFormation) do
		if v.id == oldId then
			v.id = newId
			v.fomrmationInfo = LuaFormationManager.findFormationInfoById(newId)
		end
	end
end

function formationAttrUpdateFun(  msgId , _json )
	local data = json.decode(_json)
	if msgId == Protocol.SC_SendFormation then
		LuaFormationManager.loadServerFormation(data.info)
	elseif msgId == Protocol.SC_TechnologyUp then
		LuaFormationManager.upgradeFormId(data.old, data.new)
	elseif msgId == Protocol.SC_Technology then
		LuaFormationManager.loadFormationIdMapFromServer(data.info)
	elseif msgId == Protocol.SC_RecBySou then
		LuaFormationManager.checkFormPosAvaliable()
	elseif msgId == Protocol.SC_GetRole then
		LuaFormationManager.checkFormPosAvaliable()
	elseif msgId == Protocol.SC_NotifyPlayerAttrChange then
		-- 如果是等级发生改变 需要重新检测 有没有新的位置开启
		if data.type == NotifyPlayerAttrType.Level then
			LuaFormationManager.checkFormPosAvaliable()
		end
	elseif msgId == Protocol.SC_NotifyOpenFormation then
		for i,v in ipairs(data.info) do
			table.insert(LuaFormationManager._formationIdMap, v)
		end
	end
end

function LuaFormationManager.registeEvent()
    LuaFormationManager.eventProxy = MyLuaProxy.newProxy("LuaFormationManager.lua")
	LuaFormationManager.eventProxy:addMsgListener( Protocol.SC_SendFormation, "formationAttrUpdateFun")
	LuaFormationManager.eventProxy:addMsgListener( Protocol.SC_Technology, "formationAttrUpdateFun")
	LuaFormationManager.eventProxy:addMsgListener( Protocol.SC_TechnologyUp, "formationAttrUpdateFun")
	LuaFormationManager.eventProxy:addMsgListener( Protocol.SC_NotifyOpenFormation, "formationAttrUpdateFun")
	LuaFormationManager.eventProxy:addMsgListener( Protocol.SC_RecBySou, "formationAttrUpdateFun")
	LuaFormationManager.eventProxy:addMsgListener( Protocol.SC_GetRole, "formationAttrUpdateFun")
	LuaFormationManager.eventProxy:addMsgListener( Protocol.SC_NotifyPlayerAttrChange, "formationAttrUpdateFun")
end

-- 返回指定阵型上的武将ID（TO CPP）
function LuaFormFormationSoldieIdForTypeAndPos( formationType, pos )
	local formation = LuaFormationManager._ServerSavedFormation[formationType]
	if formation and formation.soldiers and formation.soldiers[pos] then
		return formation.soldiers[pos]
	end
	return 0
end

-- 返回指定资源战阵型是否可出战（未处于冷却中）
function LuaFormationManager.isAvaliableResBattleFormation( flag )
	local cdtime = LuaCDManager.resBattleFormCD( flag )
	if cdtime then
		return cdtime + LuaResBattleManager.fightCoolingTime <= os.time()
	else
		return true
	end
end

-- 检测并设置是否有未上阵的武将位置
function LuaFormationManager.checkFormPosAvaliable()
	local validCount = LuaFormationManager.curValidPosCount()
	local info = LuaFormationManager._ServerSavedFormation[FormationUseType.Monster]
	local soldierCount = LuaSoldierManager.getOwnedSoldierCount()
	local count = 0
	for i,v in ipairs(info.soldiers) do
		if v ~= 0 then
			count = count + 1
		end
	end
	
	if count < validCount then
		if count < soldierCount then
			if not LuaFormationManager._hasAvaliablePos then
				utils.gameControl:dispatchUIEvent(ClienNotifyProtocol.FORMATION_POS_AVALIABLE ,json.encode({}))
				LuaFormationManager._hasAvaliablePos = true
			end
		elseif LuaFormationManager._hasAvaliablePos then
			utils.gameControl:dispatchUIEvent(ClienNotifyProtocol.FORMATION_POS_INAVALIABLE ,json.encode({}))
			LuaFormationManager._hasAvaliablePos = false
		end
	else
		if LuaFormationManager._hasAvaliablePos then
			utils.gameControl:dispatchUIEvent(ClienNotifyProtocol.FORMATION_POS_INAVALIABLE ,json.encode({}))
			LuaFormationManager._hasAvaliablePos = false
		end
	end
end

-- 返回是否有未上阵武将的阵型位置
function LuaFormationManagerFormPosAvaliabel()
	return LuaFormationManager._hasAvaliablePos
end

-- 获取指定阵型上阵武将的总战力
function LuaFormationManager.getFormMightByType( formationType )
	local totalMight = 0
	for k,v in pairs(LuaFormationManager._ServerSavedFormation) do
		if v.flag == formationType then
			for idx,value in ipairs(v.soldiers) do
				if value > 0 then
					totalMight = totalMight + SoldierManager:getSingleton():GetPowerById(value, 0)
				end
			end
			break
		end
	end
	return totalMight
end

-- 获取指定阵型当前已上阵武将数
function LuaFormationManager.getSoldierCountInForm( formationType )
	local count = 0
	local formData = LuaFormationManager.findFormationInfoByFlag(formationType)
    if formData and formData.soldiers then
        for k,v in pairs(formData.soldiers) do
            if v > 0 then
            	count = count + 1
            end
        end
    end
    return count
end

LuaFormationManager.init()
