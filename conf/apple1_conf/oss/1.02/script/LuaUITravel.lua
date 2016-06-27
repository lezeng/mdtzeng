require "script/CCBReaderLoad"
require "script/debug"
require "script/Protocol"
require "script/json"
require "script/LuaAutoGrowManager"
require "script/ErrorCodes"


local LuaUITravel = createCCBClase("LuaUITravel")
local LuaUITravelPage = nil

local recoverTime = 5*60 --游历次数恢复时间
local lastRecoverTime = nil --上一次恢复时间

local RewardMoneyData = {
    "Id",
    "Count",
}
RewardMoneyData = CreatEnumTable(RewardMoneyData, 1)


-- 获取已经记录的奖励货币数量
function LuaUITravel:getRecordMoneyNum( moneyId )
    for k,v in pairs(self.travelReward.attrList) do
        if v[RewardMoneyData.Id] == moneyId then
            return v[RewardMoneyData.Count]
        end
    end
    return 0
end

-- 设置已获取货币奖励记录
function LuaUITravel:setRecordMoneyNum( moneyId, value )
    for k,v in pairs(self.travelReward.attrList) do
        if v[RewardMoneyData.Id] == moneyId then
            v[RewardMoneyData.Count] = value
            return
        end
    end
    table.insert(self.travelReward.attrList, {moneyId, value})
end

-- 解析获得货币命令
-- 增加指定货币类型的货币数量，仅缓存在客户端，顶部UI的数值也是客户端模拟改变，游历完成后一次性发送数据到服务器
function LuaUITravel:parseMoneyCommand( keyId, value, moneyType)
    if value == 0 then return end

    local itemData = nil
    local isNotEnough = false

    local count = self:getRecordMoneyNum(keyId) + value

    local playerData = PlayerMgr.getSingleton():playerWithDBId("", nil)
    if moneyType == NotifyPlayerAttrType.Money then
        itemData = LuaItemManager.findItemById(keyId)
        if playerData.SILVER < -count then isNotEnough=true end
    elseif moneyType == NotifyPlayerAttrType.Gold then
        itemData = LuaItemManager.findItemById(keyId)
        if playerData.GOLD < -count then isNotEnough=true end
    elseif moneyType == NotifyPlayerAttrType.Command then
        itemData = LuaItemManager.findItemById(keyId)
        if playerData.COMMAND < -count then isNotEnough=true end
    elseif moneyType == NotifyPlayerAttrType.Att then
        itemData = LuaItemManager.findItemById(keyId)
        if playerData.attCmd < -count then isNotEnough=true end
    elseif moneyType == NotifyPlayerAttrType.TechMoney then
        itemData = LuaItemManager.findItemById(keyId)
        moneyType = -10086
    elseif moneyType == NotifyPlayerAttrType.Exp then
        itemData = LuaItemManager.findItemById(keyId)
        moneyType = -10086
    end

    if not itemData then return end

    if isNotEnough then
        UIManager:getSingleton():OpenLuaWarning(itemData.name.."不足")
        return
    end

    self:setRecordMoneyNum(keyId, count)
    if moneyType > 0 then
        UIManager:getSingleton():addMoneyOnlyClient(moneyType, count)
    end

    if value > 0 then
        return "获得 "..value.." "..itemData.name
    else
        return "消耗 "..-value.." "..itemData.name
    end
end

-- 解析后宫命令
function LuaUITravel:parseGirlCommand( girlId )
    local returnStr = ""
    -- 后宫命令只是为了整合到现有流程
    local girlData = GirlsMgr:getSingleton():getGirlById(girlId)
    if girlData then
        local curLikeValue = LuaGirlManager.getLikeValueByGirlId(girlId)
        if curLikeValue >= girlData.activeNum then
            self:showGirlpage(girlId)
        else
            returnStr = "获得佳人"..girlData.name.."缘分值+1"
        end
        self.travelReward.girlId = girlId
        self.girlEffect = true
    else
        _openWarning("后宫数据错误")
    end

    return returnStr
end

local CMD_TABLE ={
"文本跳转",
["元宝"] = function(value) return LuaUITravelPage:parseMoneyCommand(17010038, value, NotifyPlayerAttrType.Gold) end,
["军令"] = function(value) return LuaUITravelPage:parseMoneyCommand(17010054, value, NotifyPlayerAttrType.Command) end,
["攻击令"] = function(value) return LuaUITravelPage:parseMoneyCommand(17010055, value, NotifyPlayerAttrType.Att) end,
["科技币"] = function(value) return LuaUITravelPage:parseMoneyCommand(17010040, value, NotifyPlayerAttrType.TechMoney) end,
["铜钱"] = function(value) return LuaUITravelPage:parseMoneyCommand(17010039, value, NotifyPlayerAttrType.Money) end,
["经验"] = function(value) return LuaUITravelPage:parseMoneyCommand(17010044, value, NotifyPlayerAttrType.Exp) end,
["好感"] = function(value) return LuaUITravelPage:parseGirlCommand(value) end,
}

local LayerZOrder = {
    "Menu",         --功能按钮
    "DialogBox",    --对话框
    "Option",       --对话选项
    "GirlCover",    --佳人遮挡图片
    "GirlEffect",   --佳人出现特效
    "ShowGirlPage", --获得佳人页面
}
LayerZOrder = CreatEnumTable(LayerZOrder, 1)

local OptionType = {
    "A",
    "B",
}
OptionType = CreatEnumTable(OptionType, 1)

function LuaUITravelOpen(scene)
    local node = CCBuilderReaderLoad("LuaUITravel.ccbi", CCBProxy:create(), "LuaUITravel")

    LuaUITravelPage = LuaUITravel.extend(tolua.cast(node, "CCLayer"))
    if LuaUITravelPage then
        LuaUITravelPage:init(scene:getTouchPriority())
        scene:addChild(LuaUITravelPage)
    end
    
    TutorialManager:getSingleton():gotoNextStep()
end

function LuaUITravel:init( touchPriority )
    utils.registeSwallowTouch(self, touchPriority)
    self:registeNodeEvent()

    self.startItem:setZoomTarget(self.startButton)
    self.startItem:setTutorialStepId(36020201)

    local startImgAction = CCSequence:createWithTwoActions(CCScaleTo:create(1,1.4), CCScaleTo:create(1,1))
    self.startImg:runAction(CCRepeatForever:create(startImgAction))

    math.randomseed(tostring(os.time()):reverse():sub(1, 6))

    local travelGrowInfo = LuaAutoGrowManager.findDataById(AssetType.TravelCount)
    if travelGrowInfo then
        recoverTime = tonumber(travelGrowInfo.cd)
    end

    self.maxTravelCount = 0--最大游历次数
    local vipInfo = VipConfMgr.getSingleton():getVipByLevel(PlayerMgr.getSingleton():playerWithDBId("", nil).curVIPRank)
    if vipInfo then self.maxTravelCount = vipInfo.travelCount end

    self.startMenu:setTouchPriority(self:getTouchPriority()-LayerZOrder.Menu)

    self.detailItem:setZoomTarget(self.detailMenu:getParent())
    self.detailMenu:setTouchPriority(self:getTouchPriority()-LayerZOrder.Menu)

    utils.registeSwallowTouch(self.dialogBox, self:getTouchPriority()-LayerZOrder.DialogBox)
    self.dialogBox:setTouchEnabled(false)

    self.optionMenuA:setTouchPriority(self:getTouchPriority()-LayerZOrder.Option)
    self.optionMenuB:setTouchPriority(self:getTouchPriority()-LayerZOrder.Option)

    self.scheduler = CCDirector:sharedDirector():getScheduler():scheduleScriptFunc(function(dt) self:updateTravelTime() end,1,false)

    self.effect:runAction(create_animation("effect17_.plist", "effect17_", 0.1, 1, 16, 0xffffffff))

    self.startImg:setScale(1)
    self.showgirl:setZOrder(LayerZOrder.ShowGirlPage)

    self:updateLastRecoverTime()

    self:refreshCount()
    self:updateTravelTime()

    LuaGirlManager.createRandomTable()
end

function LuaUITravel:getTravelCount( ... )
    local count = self.maxTravelCount - LuaGirlManager.traveledCount
    if count <= 0 then count = 0 end
    return count
end

function LuaUITravel:registerProxy()
    self.eventProxy = MyLuaProxy.newProxy("LuaUITravel.lua")
    if not self.eventProxy then return end

    function onLuaUITravelMsg( msgId ,jsonstr)
        if msgId == Protocol.SC_TravelResult then
            print("收到游历结果，关闭对话框")
            if self.travelReward.girlId > 0 then
                local girlData = GirlsMgr:getSingleton():getGirlById(self.travelReward.girlId)
                if girlData then
                    local curLikeValue = LuaGirlManager.getLikeValueByGirlId(self.travelReward.girlId)
                    if curLikeValue >= girlData.activeNum then
                        LuaGirlManager.onCatchGirl(self.travelReward.girlId)
                    else
                        LuaGirlManager.addGirlLikeValue(self.travelReward.girlId)
                    end
                    LuaGirlManager.createRandomTable()
                end
            end
            self:closeDialog()
            local data = json.decode(jsonstr)
            if data[ProtocolStr_Rtn] ~= ErrorCode.OK then
                _printRequestMsg(msgId, data[ProtocolStr_Rtn])
            end
            _clearWaiting()

        --游历剩余次数
        elseif msgId == Protocol.SC_NotifyTravelCount then
            local data = json.decode(jsonstr)
            if data[ProtocolStr_Rtn] == ErrorCode.OK then
                self:refreshCount()
            else
                _printRequestMsg(msgId, data[ProtocolStr_Rtn])
            end

        elseif msgId == Protocol.SC_OneTravel then
            local data = json.decode(jsonstr)
            if data.rtn == ErrorCode.OK then
                self:startTravel()
            else
                _openWarning("游历次数错误")
            end
            _clearWaiting()

        elseif msgId == Protocol.SC_CD then
            lastRecoverTime = LuaCDManager.autoGrowCD(AssetType.TravelCount)
            if not lastRecoverTime then
                print("服务器无时间记录，本地构建数据")
                lastRecoverTime = os.time() - recoverTime
            end
            print("收到cd时间："..lastRecoverTime)
        end

        TutorialManager:getSingleton():gotoNextStep()
    end

    self.eventProxy:addMsgListener(Protocol.SC_GetTravel, "onLuaUITravelMsg")
    self.eventProxy:addMsgListener(Protocol.SC_TravelResult, "onLuaUITravelMsg")
    self.eventProxy:addMsgListener(Protocol.SC_CD, "onLuaUITravelMsg")
    self.eventProxy:addMsgListener(Protocol.SC_NotifyTravelCount, "onLuaUITravelMsg")
    self.eventProxy:addMsgListener(Protocol.SC_OneTravel, "onLuaUITravelMsg")
end

-- 更新上一次恢复游历时间记录
function LuaUITravel:updateLastRecoverTime( ... )
    lastRecoverTime = LuaCDManager.autoGrowCD(AssetType.TravelCount)
    if not lastRecoverTime then
        lastRecoverTime = os.time() - recoverTime
    end
end

-- 更新游历状态
function LuaUITravel:updateTravelTime( ... )
    if not self.timeLabel:isVisible() then return end

    if self:getTravelCount() >= self.maxTravelCount then
        self.timeLabel:setVisible(false)
        self.time:setVisible(false)
        return
    else
        self.timeLabel:setVisible(true)
        self.time:setVisible(true)
    end

    local currentTime = os.time()
    local timeDuration = lastRecoverTime + recoverTime - currentTime

    local safeFlag = 0
    -- 上次记录的时间可能超过多次恢复时间
    local function fixTime( td )
        if safeFlag > 100 then
            return recoverTime
        end
        if td <= 0 then
            lastRecoverTime = lastRecoverTime + recoverTime
            td = lastRecoverTime + recoverTime - currentTime
        end
        if td < 0 then
            td = fixTime(td)
        end
        safeFlag = safeFlag + 1
        return td
    end

    timeDuration = fixTime(timeDuration)

    local minute = math.floor(timeDuration / 60)
    local second = timeDuration % 60
    timeDuration = string.format("%02d", minute)..":"..string.format("%02d", second)
    self.timeLabel:setString(timeDuration)
    self.time:setVisible(true)
end

function LuaUITravel:onExitTransitionDidStart()
    CCDirector:sharedDirector():getScheduler():unscheduleScriptEntry(self.scheduler)
    if self.dialogBox:isVisible() then
        self:save(false)
    end
    self:unregisterProxy()
end

-- 刷新剩余游历次数显示
function LuaUITravel:refreshCount()
    self.countLabel:setString(self:getTravelCount().."/"..self.maxTravelCount)
    self:updateStartBtnState()
end

-- 更新开始按钮状态
function LuaUITravel:updateStartBtnState( ... )
    if self:getTravelCount() > 0 then
        self.startButton:setVisible(true)
        self.startImg:setVisible(true)
        self.nullTips:setVisible(false)
    else
        self.startButton:setVisible(false)
        self.startImg:setVisible(false)
        self.nullTips:setVisible(true)
    end
end

-- 根据对话命令涉及数据，修正对话选项显示文字
function LuaUITravel:getFixDialogInfo( originStr, typeStr, value )
    if typeStr == "元宝" or typeStr == "军令" or typeStr == "攻击令"
        or typeStr == "科技币" or typeStr == "铜钱" then
        if value > 0 then return originStr.."（获得"..typeStr.." "..value end
        if value < 0 then return originStr.."（消耗"..typeStr.." "..-value end
    end
end

-- 获取对话选项命令；{{cmd="xxx", arg=111}, {cmd="yyy", arg=222}}
function LuaUITravel:getCmdList( cmdStr )
    local strList = string.split(cmdStr, ";")
    local cmdList = {}
    for i=1,#strList, 2 do
        if strList[i] then
            local cmdStr = strList[i]
            -- 移除获得两个字，处理上要方便一些，稍后考虑让策划直接从命令中移除
            cmdStr = string.gsub(cmdStr, "获得", "")
            local cmd = {cmd=cmdStr, arg=tonumber(strList[i+1])}
            if cmd.arg ~= 0 then
                table.insert(cmdList, cmd)
            end
        end
    end
    return cmdList
end

-- 获取对话选项文字，需要附加到对话文字本身显示，主要是在有消耗的选项中提醒玩家
function LuaUITravel:getDialogInfo( cmdStr )
    local optionStr = ""
    local cmdList = self:getCmdList(cmdStr)
    for i,v in ipairs(cmdList) do
        if v.cmd ~= CMD_TABLE[1] and v.arg then
            local moneyValue = v.arg
            if moneyValue < 0 then
                optionStr = self:getFixDialogInfo(optionStr, v.cmd, moneyValue)
            end
        end
    end

    if optionStr ~= "" then
        optionStr = optionStr.."）"
    end
    return optionStr
end

-- 打开指定id对话框
function LuaUITravel:openDialog(dialogId)
    -- 可能出现配置错误，找不到对话的情况，不直接对currentDialog赋值
    local dialogData = LuaGirlManager.getDialogById(dialogId)

    if not dialogData then
        _openWarning("没有ID为"..dialogId.."的对话数据")
        return
    end

    self.currentDialog = dialogData

    local frame = CCSpriteFrameCache:sharedSpriteFrameCache():spriteFrameByName(dialogData.img)
    if frame then
        self.npcImage:setZOrder(LayerZOrder.Option)
        self.girlCover:setZOrder(LayerZOrder.GirlCover)
        self.npcImage:setDisplayFrame(frame)
        if self.isFirstLookGirl and dialogData.girlAnime then
            self.isFirstLookGirl = false

            local spriteA = CCSprite:create()
            local pos = ccp(self.npcImage:getContentSize().width/2, 0)
            spriteA:setPosition(pos)
            spriteA:setAnchorPoint(ccp(0.5,0))
            self.npcImage:addChild(spriteA)
            spriteA:setZOrder(LayerZOrder.GirlEffect)

            local animation = create_animation("effect41_.plist", "effect41_", 0.05, 1, 15, 1)
            spriteA:runAction(CCSequence:createWithTwoActions(animation,
            CCCallFunc:create(function()
                spriteA:removeFromParentAndCleanup(true)
            end)))
            SoundMgr:getSingleton():playLuaEff("woman.mp3", false);
        end
    end

    self.dialogLabel:setString(dialogData.dialog)

    -- 生成对话A的文字
    local optionAStr = dialogData.optionA
    if dialogData.cmdA ~= "" then
        optionAStr = optionAStr..self:getDialogInfo(dialogData.cmdA)
    end
    self.optionA:setString(optionAStr)

    -- 生成对话B的文字
    local optionBStr = dialogData.optionB
    if dialogData.cmdB ~= "" then
        optionBStr = optionBStr..self:getDialogInfo(dialogData.cmdB)
    end
    self.optionB:setString(optionBStr)

    self.dialogBox:setVisible(true)
    self.mainPage:setVisible(false)
end

-- 保存游历数据，在单次游历结束后，一次性将缓存的数据结果与服务器同步
function LuaUITravel:save(isShowWaiting)
    local isNeedSave = false
    --每次都应该保存佳人数据
    local girlTable = LuaGirlManager.travelGirlList
    -- 后宫事件
    if self.travelReward.girlId > 0 then
        girlTable = {}
        isNeedSave = true
        -- 首次游历必然获得指定佳人
        if GirlsMgr:getSingleton():getActiveCount() <= 0 then
            table.insert(girlTable, {LuaGirlManager.firstGirlId, 1})
        else
            local curLikeValue = LuaGirlManager.getLikeValueByGirlId(self.travelReward.girlId)
            local girlData = GirlsMgr:getSingleton():getGirlById(self.travelReward.girlId)
            -- 达到条件
            if curLikeValue >= girlData.activeNum then
                for i,v in ipairs(LuaGirlManager.travelGirlList) do
                    if v[TravelGirlData.GirlId] ~= self.travelReward.girlId then
                        table.insert(girlTable, v)
                    end
                end
            else
                local isNotFound = true
                -- 改变好感度
                for i,v in ipairs(LuaGirlManager.travelGirlList) do
                    if v[TravelGirlData.GirlId] == self.travelReward.girlId then
                        isNotFound = false
                        table.insert(girlTable, {v[TravelGirlData.GirlId], v[TravelGirlData.LikeValue]+1})
                    else
                        table.insert(girlTable, v)
                    end
                end
                if isNotFound and LuaGirlManager.getInTravelGirlCount() < LuaGirlManager.maxTravelGirlCount then
                    table.insert(girlTable, {self.travelReward.girlId, 1})
                end
            end
        end
    end

    local moneyTable = {}
    -- 货币奖励
    for k,v in pairs(self.travelReward.attrList) do
        if v[RewardMoneyData.Count] ~= 0 then
            isNeedSave = true
            table.insert(moneyTable, v)
        end
    end

    dump(LuaGirlManager.travelGirlList)
    dump({attr=girlTable, info=moneyTable})
    if isNeedSave then
        _sendRequest(Protocol.CS_TravelResult, {attr=girlTable, info=moneyTable}, isShowWaiting)
        -- self:closeDialog()
    else
        self:closeDialog()
    end
end

-- 关闭对话框
function LuaUITravel:closeDialog()
    self.dialogBox:setVisible(false)
    self.mainPage:setVisible(true)
    self.optionNodeA:stopAllActions()
    self.optionNodeB:stopAllActions()
    self.currentDialog = nil
    self:updateStartBtnState()

    -- 遇到佳人事件，播放特效
    if self.girlEffect then
        local animation = create_animation("effect35_.plist", "effect35_", 0.15, 1, 10, 1)
        local effectSprite = CCSprite:create()
        effectSprite:setPosition(self.detailMenu:getParent():getPosition())
        effectSprite:setAnchorPoint(ccp(0.5,0))
        self:addChild(effectSprite)

        effectSprite:runAction(CCSequence:createWithTwoActions(animation,
        CCCallFunc:create(function()
            effectSprite:removeFromParentAndCleanup(true)
        end)))
        self.girlEffect = nil
    end
end

-- 点击对话选项后，解析对应对话命令
function LuaUITravel:onSelectOption(optionType)
    if not self.currentDialog then return end

    local cmd = nil
    if optionType == OptionType.A then
        if self.currentDialog.optionA == "" then return end
        cmd = self.currentDialog.cmdA
    elseif optionType == OptionType.B then
        if self.currentDialog.optionB == "" then return end
        cmd = self.currentDialog.cmdB
    end

    if cmd == "" then
        print("无命令，关闭对话框并发送消息")
        self:save(true)
        return
    end

    local cmdList =self:getCmdList(cmd)
    dump(cmdList)

    local nextDialogId = nil
    local info = ""
    for i,v in ipairs(cmdList) do
        if v.cmd == CMD_TABLE[1] then
            nextDialogId = v.arg
        else
            if CMD_TABLE[v.cmd] then
                local reStr = CMD_TABLE[v.cmd](v.arg)
                -- 返回空命令，此对话无效（金币不足等）
                if not reStr then return end
                if reStr ~= "" then--有效的命令，但不是佳人命令（佳人不弹出提示）
                    info = info..reStr..","
                end
            else
                UIManager:getSingleton():OpenLuaWarning("命令错误:"..v.cmd..v.arg)
            end
        end
    end

    if info and info ~= "" then
        UIManager:getSingleton():OpenLuaWarning(string.sub(info,1,-2))
    end

    if nextDialogId then
        self:openDialog(nextDialogId)
    else
        print("无后续对话，关闭对话框并发送消息")
        self:save(true)
    end
end

-- 开始游历
function LuaUITravel:startTravel( ... )
    TutorialManager:getSingleton():gotoNextStep()

    -- 用于标识是否第一次在该对话中看到佳人头像
    self.isFirstLookGirl = true
    --次数已满的情况，更新cd时间
    if self:getTravelCount() == self.maxTravelCount-1 then
        -- 当次数满时，客户端自己更新上一次恢复时间点，不发获取cd的消息给服务器，因为效果一样，自己处理即可
        lastRecoverTime = os.time()
        LuaCDManager.updateTravelTime()
        self.timeLabel:setVisible(true)
    end

    --用于记录游历过程中生成的缓存数据，稍后一起发送到服务器
    self.travelReward = {girlId=0, attrList={}}
    self.startButton:setVisible(false)
    self.startImg:setVisible(false)
    self.nullTips:setVisible(false)

    local event = LuaGirlManager.getNextEvent()
    if not event then
        _openWarning("事件数据错误")
        return
    end

    self:openDialog(event.dialogID)
    -- self:openDialog(33000601)
    self:playTravelAnimation()
end

-- 播放游历开始（对话框出现）动画
function LuaUITravel:playTravelAnimation( ... )
    local targetPos = ccp(self.npcImage:getPosition())
    self.dialogNode:setScale(0)
    self.optionNodeA:setVisible(false)
    self.optionNodeB:setVisible(false)

    local function onshowOptionEndB( ... )
        local optionActionB = CCSequence:createWithTwoActions(CCScaleTo:create(0.6, 1.1), CCScaleTo:create(0.6, 1))
        self.optionNodeB:runAction(CCRepeatForever:create(optionActionB))
    end

    -- 选项A淡入后，重复播放放大缩小的动态效果；同时选项B开始淡入
    local function onShowOptionEndA( ... )
        local optionActionA = CCSequence:createWithTwoActions(CCScaleTo:create(0.6, 1.1), CCScaleTo:create(0.6, 1))
        self.optionNodeA:runAction(CCRepeatForever:create(optionActionA))

        self.optionNodeB:setVisible(true)
        local optionActionB = CCSequence:createWithTwoActions(CCFadeIn:create(0.3), CCCallFunc:create(onshowOptionEndB))
        self.optionNodeB:runAction(optionActionB)
    end

    -- 对话框放大后，选项A淡入
    local function onShowDialogEnd( ... )
        self.optionNodeA:setVisible(true)
        local optionActionA = CCSequence:createWithTwoActions(CCFadeIn:create(0.3), CCCallFunc:create(onShowOptionEndA))
        self.optionNodeA:runAction(optionActionA)
    end

    -- 佳人从左侧飞入后，对话框放大
    local function onShowGirlEnd( ... )
        local dialogAction = CCSequence:createWithTwoActions(CCScaleTo:create(0.4, 1), CCCallFunc:create(onShowDialogEnd))
        self.dialogNode:runAction(dialogAction)
    end

    if self.npcFlyinPos then
        self.npcImage:setPosition(self.npcFlyinPos:getPosition())
    end

    self.npcImage:setOpacity(0)
    local flyinAction = CCSpawn:createWithTwoActions(CCFadeIn:create(0.6), CCMoveTo:create(0.5, targetPos))
    local girlAction = CCSequence:createWithTwoActions(flyinAction, CCCallFunc:create(onShowGirlEnd))
    self.npcImage:runAction(girlAction)
end

-- 显示获得指定后宫页面
function LuaUITravel:showGirlpage( girlId )
    SoundMgr:getSingleton():playLuaEff("jiaren.mp3", false);
    self.showgirl:setVisible(true)

    local girlData = GirlsMgr:getSingleton():getGirlById(girlId)
    if girlData then
        self.girlName:setString(girlData.name)
        utils.setFrameImgToSprite(girlData.bodyIcon, self.girl)
    end

    self.showgirl:setScale(0)
    local hideAction = CCSequence:createWithTwoActions(CCScaleTo:create(0.2, 0), CCHide:create())
    local scaleAction = CCSequence:createWithTwoActions(CCDelayTime:create(1.2), hideAction)
    local showAction = CCSequence:createWithTwoActions(CCScaleTo:create(0.2, 1), scaleAction)
    self.showgirl:runAction(showAction)
end

-- 全局函数，返回是否正处于游历当中
function LuaUITravel_isTraveling( ... )
    return LuaUITravelPage.dialogBox:isVisible()
end

--点击对话选项
function LuaUITravel.onClickOption(tag, sender)
    LuaUITravelPage:onSelectOption(tag)
end

--点击开始游历
function LuaUITravel.onClickStart(tag,sender)
    if LuaUITravelPage.dialogBox:isVisible() then return end
    SoundMgr:getSingleton():playNormalBtnSound()

    _sendRequest(Protocol.CS_OneTravel, {}, true)
    -- LuaUITravelPage:startTravel()
end

--点击打开佳人界面
function LuaUITravel.onOpenGirl(tag,sender)
    SoundMgr:getSingleton():playNormalBtnSound()
    UIManager:getSingleton():openLuaPage("script/LuaTravelGirl.lua", "LuaTravelGirlOpen", "LuaTravelGirl")
end

