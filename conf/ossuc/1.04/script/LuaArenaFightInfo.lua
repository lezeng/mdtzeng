require "script/CCBReaderLoad"
require "script/json"
require "script/UserInfoManager"

--Hx@2015-09-11 : copy from LuaUIForm.lua
local scheduler        = require("script/scheduler")
local validDragTime    = 0.1
local validDragDistance = 20
local curTouchState    = FORM_TOUCH_STATE.NO_STATE


local LayerZOrder = {
    "Menu",
}
LayerZOrder = CreatEnumTable(LayerZOrder, 1)


local LuaArenaFightInfo = createCCBClase("LuaUIArenaFightInfo")
local LuaArenaFightInfoPage = nil

function LuaArenaFightInfoOpen( scene, jsonData )
	local node =CCBuilderReaderLoad("LuaUIArenaFightInfo.ccbi", CCBProxy:create(), "LuaArenaFightInfo")
	LuaArenaFightInfoPage = LuaArenaFightInfo.extend(tolua.cast(node, "CCLayer"))

	if LuaArenaFightInfoPage then
		local data = json.decode(jsonData)
		LuaArenaFightInfoPage.enemyId = data.enemyId
		-- 使用的是FormationUseType枚举
		LuaArenaFightInfoPage.fightType = data.fightType
		LuaArenaFightInfoPage.pageType = data.pageType
        LuaArenaFightInfoPage.param = data.param
        -- 关闭消耗信息
        -- LuaArenaFightInfoPage.hideCostInfo = data.hideCostInfo

		LuaArenaFightInfoPage:init(scene:getTouchPriority())
		scene:addChild(LuaArenaFightInfoPage)
	end
end

function LuaArenaFightInfo:init(touchPriority)
    utils.registeSwallowTouch(self, touchPriority, self.closeLayer)
    --self:registeNodeEvent()
    bindScriptHandler(self)
    self.msgProxy = LuaMsgProxy()

    self.forbidenAvator = {}

    self.fightMenuItem:setZoomTarget(self.fightMenu:getParent())
    self.fightMenu:setTouchPriority(touchPriority-LayerZOrder.Menu)

    -- 竞技场在开启后，自动复制了征战阵型，新的排行榜战斗，阵型不需要初始化，战斗时，需要判定阵型是否为空
	self.delegate = require("script/formation/FormationDataDelegate").new(self.fightType)

    self.attackerLayer = require("script/LuaFormationLayer").create()
	self.attackerLayer:setPosition(ccp(0,0))
	self.attackerLayer:updateFormationData(self.delegate:curFormationInfo())
	self.attackerLayer:displayInMineInfo()
    self.attacker:addChild(self.attackerLayer)

	self.selfMight:setString(self.attackerLayer.totalMight)
	self.myPower:setString(UserInfoManager.userName())

    -- Hx@2015-09-10 : 
	self.defenderLayer = require("script/LuaFormationLayer").create(true)
	self.defenderLayer:displayInMineInfo()
	self.defenderLayer:hidePlusBling()

	self.defender:addChild(self.defenderLayer)

    --DEBUG("fightType", self.fightType)

    if self.fightType == FormationUseType.Arena 
        or self.fightType == FormationUseType.Conquest1
        or self.fightType == FormationUseType.Conquest2
        or self.fightType == FormationUseType.Conquest3
        or self.fightType == FormationUseType.Conquest4
        or self.fightType == FormationUseType.Conquest5
        or self.fightType == FormationUseType.Conquest6
        then
        self.defender:getParent():setVisible(false)
        -- Hx@2015-09-10 : 竞技场
        print("对手ID"..self.enemyId)
        if self.enemyId then
            _sendRequest(Protocol.CS_ResBat_GetFightShow, {id=self.enemyId, type=self.fightType}, true)
        end
    end

    if self.pageType == EmPage.RushPass then
        -- Hx@2015-09-10 : 闯关
        self.enemyData = self:getMonsterFormDisplayData(self.enemyId)
        self.defenderLayer:updateEnemyFormationData(self.enemyData, AvatorType.Monster)

        self:enableFormationDrag(self.attackerLayer)
        self:setTouched()
        
        self:setFormationCapacity(self.defenderLayer:loadedCount())
        self:setDefName(self.enemyData[ProtocolStr_Player][PlayerAttr_Name])
        self:setDefPower(self.param.monsterPower)
        -- self:loadResource()
        self.defenderLayer:hidePlusBling()
        self.attackerLayer:hidePlusBling()
        self.defender:getParent():setVisible(true)

        self.hideCostInfo = self.param.hideCostInfo
    end

    -- guide
    self.fightMenuItem:setTutorialStepId(36020313)

    if self.hideCostInfo then
        self.costLabel:setVisible(false)
        self.costSprite:setVisible(false)
        self.fightLabel:setPositionX(self.fightMenu:getPositionX())
        self.fightLabel:setString("战 斗")
    end
end

function LuaArenaFightInfo:onEnterTransitionDidFinish()
    self.msgProxy:addMsgListener(Protocol.SC_SaveFormation, handler(self, self.scSaveFormation))
    self.msgProxy:addMsgListener(Protocol.SC_ArenaFight, handler(self, self.scFight))
    self.msgProxy:addMsgListener(Protocol.SC_NewBEAT_FightCurLayer, handler(self, self.scFight))
    self.msgProxy:addMsgListener(Protocol.SC_ResBat_GetFightShow, handler(self, self.scResBatGetFightShow))
    self.msgProxy:addMsgListener(Protocol.SC_ConquestFight, handler(self, self.scConquestFight))

    if self.hideCostInfo then
        self.fightCost = 0
    else
        self.fightCost = 2
        self:setFightCost(self.fightCost)
    end
end

function LuaArenaFightInfo:scConquestFight( msgId, strMessage )
    local data = json.decode(strMessage)
    _clearWaiting()
    if data[ProtocolStr_Rtn] == ErrorCode.OK then
        --UIManager.getSingleton():LoadBattle()
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_TimeOut then
        UIManager:getSingleton():removeTopLayer()
        _openWarning("排名有变，已更新对手列表")
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_Locked then
        _openWarning("奖励发放中无法挑战其他对手")
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_RivalLocked then
        UIManager:getSingleton():removeTopLayer()
        _openWarning("对手正在战斗中，请稍后再试")
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_PlayerNotFound then
        _openWarning("数据错误，未找到该玩家")
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_NotFightingTime then
        UIManager:getSingleton():removeTopLayer()
        _openWarning("休战中，请明天再来吧")
    elseif data[ProtocolStr_Rtn] == ErrorCode.AttNotEnough then
        _openWarning("攻击令不足")
    else
        utils.showUnknownErrorCodeInfo(data[ProtocolStr_Rtn])
    end
end

function LuaArenaFightInfo:onExitTransitionDidStart()
    self.msgProxy:clearMsgListener()

    TutorialManager:getSingleton():gotoNextStep()
end

function LuaArenaFightInfo:scResBatGetFightShow(msgId, strMessage)
    local tbMessage = json.decode(strMessage)
    _clearWaiting()
    print("获取到对手数据")
    self.enemyData = tbMessage[ProtocolStr_Info]
    self:refreshDefenderFormPos()       
end

function LuaArenaFightInfo:csFight_NewBEAT()
    GameData:getSingleton():SetSelfLeftBattleHUDInfo()
    local mainMonster = self.enemyData[ProtocolStr_Player]
    GameData:getSingleton():SetRightBattleHUDInfo(mainMonster[PlayerAttr_Name],mainMonster[PlayerAttr_Icon],mainMonster[RoleAttr_FightCapacity],mainMonster[PlayerAttr_Level])
    GameData:getSingleton().m_battleType = BATTLE_TYPE.NewBEAT
    LuaDropManager.clearDropData()

    -- @10/19 ZLu 新需求：闯关——上次打到的层数-10以内层数的战斗不能跳过，其他的可以跳过。
    local skipCount = 10
    if Game:getRushPassModel():getCurLayer() <= Game:getRushPassModel():getMyMaxLayer() - skipCount then
        GameData:getSingleton().m_isBattleCouldSkip = true
    else
        GameData:getSingleton().m_isBattleCouldSkip = false
    end

    local tMsg = {}
    tMsg[ProtocolStr_Request] = Protocol.CS_NewBEAT_FightCurLayer
    tMsg[ProtocolStr_Flag] = LuaArenaFightInfoPage.param.difficulty
    sendRequest(tMsg, true)
end

function LuaArenaFightInfo:scFight(msgId, strMessage)
    local data = json.decode(strMessage)
    _clearWaiting()
    if data[ProtocolStr_Rtn] == ErrorCode.OK then
        --UIManager.getSingleton():LoadBattle()
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_TimeOut then
        UIManager:getSingleton():removeTopLayer()
        _openWarning("排名有变，已更新对手列表")
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_Locked then
        _openWarning("奖励发放中无法挑战其他对手")
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_RivalLocked then
        UIManager:getSingleton():removeTopLayer()
        _openWarning("对手正在战斗中，请稍后再试")
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_PlayerNotFound then
        _openWarning("数据错误，未找到该玩家")
    elseif data[ProtocolStr_Rtn] == ErrorCode.E_NotFightingTime then
        UIManager:getSingleton():removeTopLayer()
        _openWarning("休战中，请明天再来吧")
    elseif data[ProtocolStr_Rtn] == ErrorCode.AttNotEnough then
        _openWarning("攻击令不足")
    else
        utils.showUnknownErrorCodeInfo(data[ProtocolStr_Rtn])
    end
end

-- Hx@2015-09-11 : PATCH : the FormationDataDelegate.lua to save formation too complex to use, do it myself
function LuaArenaFightInfo:csSaveFormation_NewBEAT()

    local formation = LuaFormationManager.findFormationInfoByFlag(FormationUseType.NewBEATComplete)

    local tMsg = {}
    tMsg[ProtocolStr_Request] = Protocol.CS_SaveFormation
    tMsg[ProtocolStr_ID] = formation.fomrmationInfo.id
    tMsg[ProtocolStr_Flag] = FormationUseType.NewBEAT
    tMsg[ProtocolStr_Info] = self:getAttackerFormationWithForbiden()

    sendRequest(tMsg, true)
end

function LuaArenaFightInfo:getAttackerFormationWithForbiden()
    local formation = self.delegate:curFormationInfo().soldiers
    local data = clone(formation)
    for k, v in pairs(data) do
        if self:checkForbidenAvator(tonumber(v)) then
            data[k] = 0
        end
    end
    return data
end

function LuaArenaFightInfo:scSaveFormation(msgId, strMessage)
    local tbMessage = json.decode(strMessage)
    _clearWaiting()
    if tbMessage[ProtocolStr_Rtn] ~= ErrorCode.OK then
        _openWarning("保存阵型失败")
    end
    self.delegate:saveFormationInfoToLocal()
    self:updateUI()
end

function LuaArenaFightInfo:setFormationCapacity(val)
    assert(val)
    self.formationCapacity = val
    self:initForbidenAvatorList()
    self.attackerLayer:setForbidenAvator(self.forbidenAvator)
    self.ccSwitchTextLayer:setVisible(true)
    self:updateFormationCountText()
end

function LuaArenaFightInfo:initForbidenAvatorList()
    local formation = self.delegate:curFormationInfo().soldiers
    local count = 0
    for _, v in ipairs(formation) do
        if v ~= 0 then
            count = count + 1
            if count > self.formationCapacity then
                self:addForbidenAvator(tonumber(v))
            end
        end
    end
end

function LuaArenaFightInfo:addForbidenAvator(avatorId)
    assert(avatorId)
    if self:checkForbidenAvator(avatorId) then
        return
    end
    table.insert(self.forbidenAvator, avatorId)
end

function LuaArenaFightInfo:removeForbidenAvator(avatorId)
    assert(avatorId)
    for i = #self.forbidenAvator, 1, -1 do
        if self.forbidenAvator[i] == avatorId then
            table.remove(self.forbidenAvator, i)
        end
    end
end

function LuaArenaFightInfo:checkForbidenAvator(avatorId)
    assert(avatorId)
    for _, v in pairs(self.forbidenAvator or {}) do
        if v == avatorId then
            return true
        end
    end
    return false
end

function LuaArenaFightInfo:checkFormationWithForbidenFull()
    return self.attackerLayer:loadedCount() >= self.formationCapacity
end

function LuaArenaFightInfo:switchForbidenState(avatorId)
    if self:checkForbidenAvator(avatorId) then
        if self:checkFormationWithForbidenFull() then
            _openWarning("已经不能上阵更多武将了")
            return
        end
        self:removeForbidenAvator(avatorId)
    else
        -- @09/25 ZLu 这里的阵型操作过程中允许出现空阵型的情况
        -- if self.attackerLayer:loadedCount() <= 1 then
        --     _openWarning("阵型不能为空")
        --     return
        -- end
        self:addForbidenAvator(avatorId)
    end
    
    self:updateUI()
end

function LuaArenaFightInfo:updateFormationCountText()
    if self.attackerLayer:loadedCount() == self.formationCapacity then
        self.ccCountText:setColor(ccc3(0, 180, 0))
    else
        self.ccCountText:setColor(ccc3(180, 0, 0))
    end
    self.ccCountText:setString(string.format("上阵%s/%s人", self.attackerLayer:loadedCount(), self.formationCapacity))
end

function LuaArenaFightInfo:getMonsterFormDisplayData(mapId)
    assert(mapId)
    local mapConf = LuaMapManager.getLevelData(mapId)
    local tbFormation = getMonsterFormationFormGroup(tonumber(mapConf.monsterid))
    local formType = MonsterManager:getSingleton():getMonsterFormationType(tonumber(mapConf.monsterid))
    local mainMonster = MonsterManager:getSingleton():GetLeaderByMonsterId(tonumber(mapConf.monsterid))

    local form = {}
    form[ProtocolStr_ID] = formType
    form[ProtocolStr_Info] = tbFormation

    local role = {}
    
    for k, v in pairs(tbFormation) do
        if v ~= 0 then
            local conf = MonsterSoldierDataManager:getSingleton():getMonsterSoldierDataById(v)
            local data = {}
            data[RoleAttr_Color] = conf.m_color
            data[RoleAttr_FightCapacity] = conf.m_power
            data[RoleAttr_Job] = conf.m_id
            data[RoleAttr_Level] = conf.m_level
            table.insert(role, data)
        end
    end

    local player = {}
    player[PlayerAttr_ID] = mainMonster.m_id
    player[PlayerAttr_Name] = mainMonster.m_name
    player[PlayerAttr_Icon] = mainMonster.m_icon
    player[PlayerAttr_Level] = mainMonster.m_level
    player[RoleAttr_FightCapacity] = self.param.monsterPower



    local data = {}
    data[ProtocolStr_FormationInfo] = form
    data[ProtocolStr_Role] = role
    data[ProtocolStr_Player] = player
    
    return data
end

--Hx@2015-09-11 : 开启拖动
function LuaArenaFightInfo:enableFormationDrag(formLayer)
    assert(formLayer)
    for i=1,9 do
        local avatar = formLayer["form_" .. i]
        if avatar then
            self:registeLoadedTouchEvent(avatar)
        end
    end
end

--Hx@2015-09-11 : copy from LuaUIForm.lua
function LuaArenaFightInfo:setTouched()
    local function onTouch( eventType, x, y )
        self.curX = x
        self.curY = y
        if eventType == "ended" then
            if curTouchState == FORM_TOUCH_STATE.DRAG_LOAD_SOLDIER then
                -- local pos = ccp(x,y)
                -- pos = self.unloadLayer:convertToNodeSpace(pos)
                -- if self.tableView:boundingBox():containsPoint(pos) then
                --     self:unloadSoldier()
                -- end
            end
            self:cancelTouchEvent()
        elseif eventType == "moved" then
            if curTouchState == FORM_TOUCH_STATE.DRAG_LOAD_SOLDIER
                or curTouchState == FORM_TOUCH_STATE.DRAG_UNLOAD_SOLDIER then
                if self.dragAvatar then
                    self.dragAvatar:setPosition(ccp(x, y))
                end
            end
        elseif eventType == "began" then
            -- Hx@2015-09-14 : PATCH : 点击外部退出
            if not self.closeLayer:boundingBox():containsPoint(self.closeLayer:getParent():convertToNodeSpace(ccp(x,y))) then
                UIManager:getSingleton():removeTopLayer()
            end
        end
        return true
    end

    self:registerScriptTouchHandler(onTouch, false, self:getTouchPriority() - 1, true)
    self:setTouchEnabled(true)
    self:setTouchMode(kCCTouchesOneByOne)
end

--Hx@2015-09-11 : copy from LuaUIForm.lua
-- 给已经上阵的武将注册事件
function LuaArenaFightInfo:registeLoadedTouchEvent( layer )
    local function onTouch( eventType, x, y )
        return self:generalLoadedTouchEvent(eventType, x, y, layer)
    end

    layer:registerScriptTouchHandler(onTouch, false, self:getTouchPriority()-2, false)
    layer:setTouchEnabled(true)
    layer:setTouchMode(kCCTouchesOneByOne)
end

--Hx@2015-09-11 : copy from LuaUIForm.lua
-- 给右侧的阵型位置分发事件
function LuaArenaFightInfo:generalLoadedTouchEvent( eventType, x, y, layer )
    local pos = ccp(x, y)
    pos = layer:convertToNodeSpace(pos)
    local contain = (pos.x > 0 and pos.x < layer:getContentSize().width) and ( pos.y > 0 and pos.y < layer:getContentSize().height)

    if contain then
        if eventType == "began" then
            self.oriX = x
            self.oriY = y
            layer.moved = false
            self:beginTouchLoadedLayer(layer)
        elseif eventType == "moved" then
            if self.curSelecteLayer == layer
                and curTouchState == FORM_TOUCH_STATE.TOUCHED_LOAD_SOLDIER
                and ccpDistance(ccp(x, y), ccp(self.oriX, self.oriY)) > validDragDistance then
                layer.moved = true
                print("移动武将:" .. ccpDistance(ccp(x, y), ccp(self.oriX, self.oriY)) .. ":" .. validDragDistance)
                self:cancelTouchEvent()
            end
        elseif eventType == "ended" then
            self:endDragLoadedLayer(layer)
        end
    else
        layer.moved = true
    end
    return true
end

--Hx@2015-09-11 : copy from LuaUIForm.lua
-- 开始点击已上阵的武将
function LuaArenaFightInfo:beginTouchLoadedLayer( layer )
    -- 当前是静止状态并且点击的layer是有soldier的
    if curTouchState == FORM_TOUCH_STATE.NO_STATE
        and layer.soldierData then
        print("点击已上阵武将" .. layer:getTag() .. " " .. layer.soldierData.name)
        self.touchHandler = scheduler.scheduleUpdateGlobal(handler(self, self.update))
        self.touchTimer = 0
        self.curSelecteLayer = layer
        curTouchState = FORM_TOUCH_STATE.TOUCHED_LOAD_SOLDIER
    end
end

--Hx@2015-09-11 : copy from LuaUIForm.lua
function LuaArenaFightInfo:update( dt )
    self.touchTimer = self.touchTimer + dt

    if self.touchTimer > validDragTime then
        -- 如果时间到了 拖拽时间 并且当前状态一直是没有动的 就进入拖拽状态
        if curTouchState == FORM_TOUCH_STATE.TOUCHED_LOAD_SOLDIER then
            print("update点击已上阵武将");
            self:beginDragLoadedLayer(self.curSelecteLayer)
        else--[[if curTouchState == FORM_TOUCH_STATE.TOUCHED_UNLOAD_SOLDIER then
            print("update点击未上阵武将");
            self:beginDragUnloadLayer(self.curSelecteLayer)
            --]]
        end

    end
end

--Hx@2015-09-11 : copy from LuaUIForm.lua
-- 开始拖拽已上真的武将
-- 并且不在计时
function LuaArenaFightInfo:beginDragLoadedLayer( layer )
    if curTouchState == FORM_TOUCH_STATE.TOUCHED_LOAD_SOLDIER then
        curTouchState = FORM_TOUCH_STATE.DRAG_LOAD_SOLDIER
        print("开始拖拽")
        --self.tableView:setTouchEnabled(false)
        self:beginDragSoldierAvatar()
    else
        self:cancelTouchEvent()
    end
    if self.touchHandler then
        scheduler.unscheduleGlobal(self.touchHandler)
        self.touchHandler = nil
    end
end

--Hx@2015-09-11 : copy from LuaUIForm.lua
-- 结束拖拽并且接受事件
function LuaArenaFightInfo:endDragLoadedLayer( layer )
     if curTouchState == FORM_TOUCH_STATE.DRAG_LOAD_SOLDIER then
        -- 如果之前是拖拽的已上阵武将
        print("如果之前是拖拽的已上阵武将")
        self:replaceSoldier(layer)
     -- elseif curTouchState == FORM_TOUCH_STATE.DRAG_UNLOAD_SOLDIER then
     --    -- 如果之前拖拽的未上阵武将
     --    print("如果之前拖拽的未上阵武将")

     --    -- JasonTai
     --    -- 添加新手引导
     --    if TutorialManager:getSingleton():isPlayingTutorial()
     --        and TutorialManager:getSingleton():curStepEndPosId() > 0 then
     --        if TutorialManager:getSingleton():curStepEndPosId() == layer:getTutorialStepId() then
     --            self:loadSoldierToForm(layer)
     --            TutorialManager:getSingleton():gotoNextStep()
     --        end
     --    else
     --        self:loadSoldierToForm(layer)
     --    end
     else
     end
     self:cancelTouchEvent()
end

--Hx@2015-09-11 : copy from LuaUIForm.lua
-- 取消当前的点击状态
function LuaArenaFightInfo:cancelTouchEvent()
    print("取消武将操作")

    --n Hx@2015-09-11 : PATCH : 点击切换武将状态
    if curTouchState == FORM_TOUCH_STATE.TOUCHED_LOAD_SOLDIER then
        self:switchForbidenState(tonumber(self.curSelecteLayer.soldierData.id))
    end

     TutorialManager:getSingleton():endDragAnimation()
    curTouchState = FORM_TOUCH_STATE.NO_STATE
    -- if not TutorialManager:getSingleton():isPlayingTutorial() then
    --     self.tableView:setTouchEnabled(true)
    -- end
    self.curSelecteLayer = nil
    if self.dragAvatar then
        self:removeChild(self.dragAvatar, true)
        self.dragAvatar = nil
    end
    self.curX = nil
    self.curY = nil
    self.oriX = nil
    self.oriY = inl
    if self.touchHandler then
        scheduler.unscheduleGlobal(self.touchHandler)
        self.touchHandler = nil
    end


end
--Hx@2015-09-11 : copy from LuaUIForm.lua
-- 开始拖拽武将头像
function LuaArenaFightInfo:beginDragSoldierAvatar()
    self.dragAvatar = require("script/formation/LuaFormListItem.lua").create(self.curSelecteLayer.soldierData)
    self.dragAvatar:displayAsDragShadow()
    self:addChild(self.dragAvatar)
    self.dragAvatar:setZOrder(100)
    self.dragAvatar:setPosition(ccp(self.curX, self.curY))
end
--Hx@2015-09-11 : copy from LuaUIForm.lua
function LuaArenaFightInfo:replaceSoldier( layer )
    if layer.soldierData then
        -- 如果当前位置是有武将的 就互换位置
        print("互换位置")
        self.delegate:replacePos(self.curSelecteLayer:getTag(), layer:getTag())
        self:updateUI()
    else
        -- 如果当前位置没有武将的 就将吴丹移到该位置
        print("将位置移到位置")
        self.delegate:replacePos(self.curSelecteLayer:getTag(), layer:getTag())
        self:updateUI()
    end
    --layer:showEnterAnimation()
end

function LuaArenaFightInfo:updateUI()
    self.attackerLayer:updateUI()
    self:updateFormationCountText()
end

function LuaArenaFightInfo:setDefName(name)
    assert(name)
    self.defenderName:setString(name)
end

function LuaArenaFightInfo:setDefPower(val)
    assert(val)
    self.defenderMight:setString(val)
end

function LuaArenaFightInfo:setFightCost(val)
    assert(val)
    self.costLabel:setString(val)
end



-- 刷新攻击对象的战力与武将信息
function LuaArenaFightInfo:refreshDefenderFormPos()
	if not self.enemyData then return end

    --[[
	local defenderLayer = require("script/LuaFormationLayer").create(true)
	defenderLayer:displayInMineInfo()
	defenderLayer:updateEnemyFormationData(self.enemyData)
	defenderLayer:hidePlusBling()
	self.defender:addChild(defenderLayer)
    --]]
    -- @10/12 ZLu 需要等待收到对手数据后，才收显示对手信息UI
    self.defender:getParent():setVisible(true)
	self.defenderLayer:updateEnemyFormationData(self.enemyData)

	self.defenderMight:setString(self.defenderLayer.totalMight)
	self.defenderName:setString(self.enemyData.player.name)
end

-- 点击开始战斗
function LuaArenaFightInfo.onClickFight( tag, sender )
    TutorialManager:getSingleton():gotoNextStep()
    -- if PlayerMgr.getSingleton():playerWithDBId("", nil).attCmd < LuaArenaFightInfoPage.fightCost then
    --     _openWarning("没有足够的攻击令")
    --     return
    -- end
    


    if LuaFormationManager.getFormMightByType(LuaArenaFightInfoPage.fightType) <= 0 then
    	_openWarning("请在阵型中布置上阵武将")
    	return
    end

    local data = LuaArenaFightInfoPage.enemyData
	-- 服务器发过来的数据可能出现异常
    if not data or data.player.id == UserInfoManager.userId() then
    	_openWarning("数据错误")
    	return
    end

    LuaDropManager.clearDropData()
    
    if LuaArenaFightInfoPage.fightType == FormationUseType.Arena then
        if not checkAttCmdEnough(LuaArenaFightInfoPage.fightCost) then
            return
        end
    	_sendRequest(Protocol.CS_ArenaFight, {id=data.player.id}, true)
    elseif LuaArenaFightInfoPage.fightType >= FormationUseType.Conquest1 and LuaArenaFightInfoPage.fightType <= FormationUseType.Conquest6 then
    	-- 修正为排行榜类型
        if not checkAttCmdEnough(LuaArenaFightInfoPage.fightCost) then
            return
        end
    	local rankType = LuaArenaFightInfoPage.fightType - FormationUseType.Conquest1 + 1
    	_sendRequest(Protocol.CS_ConquestFight, {type=rankType, id=data.player.id}, true)
    	GameData:getSingleton().m_battleType = rankType +  BATTLE_TYPE.fengyun1 - 1
        LuaArenaManager.rankChangeCount = 0
    end

    if LuaArenaFightInfoPage.pageType == EmPage.RushPass then
        LuaArenaFightInfoPage:csSaveFormation_NewBEAT()
        if not LuaArenaFightInfoPage:checkFormationWithForbidenFull() then
            function warningCallBack()
                --@12/21 ZLu 保存阵型和战斗开始的【showwaiting】需要调整
                LuaArenaFightInfoPage:csFight_NewBEAT()
            end
            UIManager:getSingleton():openRechargeWarningForLua("上阵人数未满，是否进入战斗？","战斗")
            return
        else
            LuaArenaFightInfoPage:csFight_NewBEAT()
        end
    end
    -- 服务器需要处理竞技场奖励时，可能停止竞技场战斗，需要判定后再进行场景切换
    -- UIManager.getSingleton():LoadBattle()
end
