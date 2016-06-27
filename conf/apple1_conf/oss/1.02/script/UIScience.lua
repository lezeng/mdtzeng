--相当于头文件
require "script/CCBReaderLoad"
require "script/Protocol"
require "script/json"
require "script/debug"

local self = nil
local scheduler        = require("script/scheduler")
local frontArray = {}
local lockAnimateArray = {} ----锁链特效组
local upNeedMoney = nil -----升级所需科技币
local upNeedLevel = nil ----升级需要等级
local memoArray = {} -- 阵形效果描述的数组
local index = nil ---判断相同描述的位子
local posSpriteArray = {}--位子效果精灵
local infoSpriteArray = {}--存储右边描述的ccb

local interval = 5
local scienId = 2 ------
local sendId = 1 -------存储阵形的ID,默认为第一个阵形
local lineId = {line1Id,line2Id,line3Id,line4Id,line5Id,lind6Id}
local buffArray = {}---存储buff
local showGrid ={}--显示的效果
local moreBuff = {}--存储具有多个buff的表


local LuaUIScience = createCCBClase("UIScience2")

function LuaUIScience:registerProxy()
    if self.eventProxy then
        function onLuaUIScienceMsg(msgId,jsonstr)
            local jsonTable = json.decode(jsonstr)
            if msgId == Protocol.SC_TechnologyUp then
                print("科技_Protocol.SC_TechnologyUp")
                if jsonTable.new ~= nil then
                    lineId[scienId] = jsonTable.new
                    sendId=lineId[scienId]
                    self:showData()
                end

                if jsonTable.rtn == 0 then
                    local money = PlayerMgr:getSingleton():playerWithDBId("",nil).techMoney
                    self.techMoney:setString(money)
                    self:runActionCallBack()
                end

                 UIManager:getSingleton():ClearWaiting()

            elseif msgId == Protocol.SC_Technology then
                print("科技_Protocol.SC_Technology")
                self:initData()
                UIManager:getSingleton():ClearWaiting()

            elseif msgId == Protocol.SC_NotifyOpenFormation then
                print("科技_Protocol.SC_NotifyOpenFormation")
                self:initData()
                UIManager:getSingleton():ClearWaiting()
            end
        end

        self.eventProxy:addMsgListener(Protocol.SC_TechnologyUp, "onLuaUIScienceMsg")
        self.eventProxy:addMsgListener(Protocol.SC_Technology, "onLuaUIScienceMsg")
        self.eventProxy:addMsgListener(Protocol.SC_NotifyOpenFormation,"onLuaUIScienceMsg")
    end
end

--创建锁链特效
function createLockAnimate( point ,index)
    local lockAnimateSprite = CCSprite:create()
    lockAnimateSprite:setPosition(point)
    lockAnimateSprite:setScale(0.75)
    self.mapMenuNodes:addChild(lockAnimateSprite,1)
    table.insert(lockAnimateArray,lockAnimateSprite)
    local openLevel = LuaFormationManager.getFormationOpenLevel(index)
    if openLevel then
        local openLabel = createCommonLabel(openLevel.."级开放", nil, 10, CCSize(31 * 0.7, 0))
        openLabel:setPosition(point)
        self.mapMenuNodes:addChild(openLabel,10)
    end

    local animate = create_animation("effect09_.plist", "effect09_", 0.12, 1, 9, 0xffffffff)
    lockAnimateSprite:runAction(animate)
end

function LuaUIScience:assignCCBMemberVariables()
    for i=1,6 do
        self["formLock_"..i]:setZOrder(2)
        self["formLock_"..i]:setVisible(false)
    end

    for i=1,6 do
        -- lineBaseArray[i] = tolua.cast(self["lineBase_"..i],"CCMenuItemImage")
        self["lineBase_"..i]:setZoomTarget(self["lineBase_"..i]:getParent())
    end

    local animate = create_animation("effect15_.plist", "effect15_", 0.08, 1, 12, 0xffffffff)
    self.texiao:runAction(animate)
end

function LuaUIScience:onExitTransitionDidStart(  )
    self:unregisterProxy()
    self:stopBuff()
end

--init数据
function LuaUIScience:initData()
    tempData = LuaFormationManager._formationIdMap
    if not tempData then return end
    for i=1,#tempData+1 do
        lineId[i]=tempData[i]
        if lineId[2] ~= nil then
            sendId=lineId[2]
            local linePoint = ccp(self["lineBase_"..2]:getPosition())
            local point = self["lineBase_"..2]:getParent():convertToWorldSpace(linePoint)
            self:playBaseAnimation(point)
        else
            sendId = lineId[1]
            print("LuaUIScience...servertData...isErro")
        end
    end

    for i=6,#tempData+1,-1 do
        self["formLock_"..i]:setVisible(true)
        local lockPoint = ccp(self["formLock_"..i]:getPosition())
        createLockAnimate(lockPoint,i)
    end
end

function LuaUIScience:init( touchPriority )
    utils.registeSwallowTouch(self, touchPriority)
    self.upgradeMenuItem:setTutorialStepId(36020601)
    self.upgradeMenu:setTouchPriority(touchPriority-1)
    for i=1,6 do
        self["BTform0"..i]:setTouchPriority(touchPriority-1)
    end
    self:assignCCBMemberVariables()
    self:registeNodeEvent()

    local money = PlayerMgr:getSingleton():playerWithDBId("",nil).techMoney
    self.techMoney:setString(money)

    self:initData()

    local formationLayer = require("script/LuaFormationLayer").create(false, true)
    self.lineGrid:addChild(formationLayer)
    formationLayer:updateFormationId(sendId)
    formationLayer:displayInTech()
    self.formationLayer = formationLayer
    self:showData()
end

--阵形回调
function LuaUIScience.line_IsDown(tag, sender)
    if tag ~= 7 and lineId[tag] == nil then
        return
    end

    for i=1,9 do
        self["grid"..i]:setVisible(false)
    end

    if tag <7 then
        scienId = tag

        local fadeAnimation = CCSequence:createWithTwoActions(CCFadeOut:create(0.3),CCFadeIn:create(0.3))
        self.lineGrid:runAction(fadeAnimation)

        local linePoint = ccp(self["lineBase_"..tag]:getPosition())
        local point = self["lineBase_"..tag]:getParent():convertToWorldSpace(linePoint)
        self:playBaseAnimation(point)

    else
        utils.uiMgr:removeTopLayer()
        self:stopBuff()
    end

    if lineId[scienId]~=nil and tag ~=7 then
        sendId=lineId[scienId]
        self:showData()
    end
  end

--阵形选中效果动画
function LuaUIScience:playBaseAnimation( point)
    if self.animationSprite then
        self.animationSprite:setPosition(point)
    else
       self.animationSprite = CCSprite:create()
       self.animationSprite:setPosition(point)
       self.animationSprite:setScale(0.5)
       self:addChild(self.animationSprite)
       local animation = create_animation("effect04_.plist", "effect04_", 0.08, 1, 6, 0xffffffff)
       self.animationSprite:runAction(animation)
    end
end

--科技升级回调
function LuaUIScience:showData()
    local scienData = LuaFormationManager._FormationData

    --阵形描述
    for k,v in pairs(frontArray) do
        frontArray[k] = nil
    end

    for k,v in pairs(memoArray) do
        memoArray[k]=nil
    end

    for k,v in pairs(scienData) do
        if v.id==sendId then
     --阵形效果的数据
        --阵形的描述
            --相同描述位子
            local memoData = {pos=v.pos, img=v.effect}
            local isTrue = self:isHave(v.front,frontArray)
            if isTrue then
                table.insert(memoArray[index].tempArray, memoData)
            else
                local effectData = {lineMemo=v.front, tempArray={}}
                table.insert(frontArray, v.front) --将描述加入到描述容器中
                table.insert(effectData.tempArray, memoData)
                table.insert(memoArray, effectData)
            end
        end
    end




    self:stopBuff()

    --科技描述显示
    for i,v in ipairs(memoArray) do
        local memoSprite = createInfoSprite(self.memoLayer)
        memoSprite:setScale(0.7)
        local size = self.memoLayer:getContentSize()
        memoSprite:setPosition(ccp(-30,size.height-30*i-15))
        memoSprite.cb_momeTTF:setString(tostring(v.lineMemo))
        for _i,_v in ipairs(v.tempArray) do
            utils.setFrameImgToSprite(_v.img, posSpriteArray[_v.pos])
        end
        table.insert(infoSpriteArray,memoSprite)
    end



    self.formationLayer:updateFormationId(sendId)
    for k,v in pairs(scienData) do

        if v.id == sendId then
            self.lineNameTTF:setString(v.name)
            local have = self:isHave(self["grid"..v.pos], showGrid)
            if not have  then
                table.insert(showGrid, self["grid"..v.pos])
            end

            self.level:setString(v.level)

            local isMaxLevel = true
            for k,value in pairs(LuaFormationManager.MoneyDataConfig) do
                if value.curformation == v.id then
                    upNeedMoney = value.money
                    upNeedLevel = value.levellimit
                    local displayMoney = value.money
                    if value.money >= 100000 then
                        displayMoney = (displayMoney/1000).."K"
                    end
                    self.upMoney:setString(displayMoney)
                    isMaxLevel = false
                    break
                end
            end
            self.maxTipsLabel:setVisible(isMaxLevel)
            self.upgradeButton:setVisible(not isMaxLevel)
        end
    end
end

--检测元素是否存在于表中
function LuaUIScience:isHave(temp,list)
    -- body
    for k,v in pairs(list) do
        if v == temp then
            index = k
            return true
        end
    end
    return false
end

--把单个buff转成表
--把双buff解析成表
function LuaUIScience:parseBuff(v)
    local isDouble = self:subStr(v)
    if isDouble then
        local imgArray = string.split(v,";")
        return imgArray
    else
        local tempTable ={ v }
        return tempTable
    end
end

function LuaUIScience:runActionCallBack()
     for k,v in pairs(showGrid) do
        self:playAnimation(v)
    end
end

-- 播放升级特效
function LuaUIScience:playAnimation(tempSprite)
    local animation = create_animation("jinglian2_.plist", "jinglian2_", 0.08, 1, 11, 1)
    if animation then
       tempSprite:setVisible(true)
       local seq = CCSequence:createWithTwoActions(animation,CCCallFunc:create(function()
            tempSprite:setVisible(false)
        end))
       tempSprite:runAction(seq)
    end
end

--开始显示buff效果
function LuaUIScience:beginBuff()
    for k,v in pairs(showGrid) do
        if #buffArray[k] > 1 then
            v.curIndex = 1
            utils.setFrameImgToSprite(buffArray[k][v.curIndex], v)
            v.buffIndex = k
            if self.displayHandler then
                self.displayHandler = scheduler.scheduleGlobal(handler(self, self.schedulerBuffStr), interval)
            end
            v:setVisible(true)
            table.insert(moreBuff,v)
        else
            utils.setFrameImgToSprite(buffArray[k][1], v)
        end
    end
end

function LuaUIScience:schedulerBuffStr()
    for k,v in pairs(moreBuff) do
        local actions = CCArray:createWithCapacity(4)
        local a2 = CCFadeIn:create(interval * 0.15)
        local a3 = CCDelayTime:create(interval * 0.7)
        local a4 = CCFadeOut:create(interval * 0.15)
        local a1 = CCCallFunc:create(function()
            v.curIndex = v.curIndex + 1
            utils.setFrameImgToSprite(buffArray[v.buffIndex][v.curIndex], v)

            if v.curIndex == #buffArray[v.buffIndex] then
                v.curIndex = 0
            end
        end)

        actions:addObject(a1)
        actions:addObject(a2)
        actions:addObject(a3)
        actions:addObject(a4)
        local action = CCSequence:create(actions)
        action:setTag(100)
        v:runAction(action)
    end
end

--暂停buff效果
function LuaUIScience:stopBuff()
    for k,v in pairs(moreBuff) do
         moreBuff[k] = nil
    end

    if self.displayHandler then
        scheduler.unscheduleGlobal(self.displayHandler)
        self.displayHandler = nil
    end

    for k,v in pairs(showGrid) do
        v:setVisible(false)
        v:stopActionByTag(100)
        showGrid[k]=nil
    end

    for k,v in pairs(buffArray) do
        buffArray[k]=nil
    end

    for k,v in pairs(infoSpriteArray) do
        v:removeFromParentAndCleanup(true)
        infoSpriteArray[k]=nil
    end

    self:stopActionByTag(100)
end

function LuaUIScience:subStr(str)
   for i=1,#str do
       chars = string.sub(str,i,i)
       if chars == ";" then
            return true
       end
   end
   return false
end

--科技升级回调
function LuaUIScience.upItemCallBack(tag, sender)
    local myLevel = PlayerMgr.getSingleton():playerWithDBId("",nil).LEVEL
    if myLevel >= upNeedLevel then
        local money = PlayerMgr:getSingleton():playerWithDBId("",nil).techMoney
        if sendId and upNeedMoney then
            if money >= upNeedMoney then
                _sendRequest(Protocol.CS_TechnologyUp, {rq=Protocol.CS_TechnologyUp, id=sendId}, true)
            else
                _openWarning("科技币不足")
            end
        end
    else
        _openWarning("升级此阵形，需"..upNeedLevel.."级")
    end
    TutorialManager:getSingleton():gotoNextStep()
end

function LuaUIScienceOpen( scene )
    local node =CCBuilderReaderLoad("UIScience2.ccbi", CCBProxy:create(), "LuaUIScience")
    self = LuaUIScience.extend(tolua.cast(node, "CCLayer"))

    if self then
        self:init(scene:getTouchPriority())
        scene:addChild(self)
    end

    TutorialManager:getSingleton():gotoNextStep()
end
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------LuaScienceInfo------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local LuaScienceInfo = createCCBClase("LuaScienceInfo")

function LuaScienceInfo:init( )
    for i=1,9 do
        posSpriteArray[i] = tolua.cast(self["cb_pos"..i],"CCSprite")
    end
end

function createInfoSprite( scene )
    local node   = CCBuilderReaderLoad("LuaScienceInfo.ccbi", CCBProxy:create(), "LuaScienceInfo")
    infoSelf   = LuaScienceInfo.extend(tolua.cast(node, "CCNode"))
    if infoSelf then
        infoSelf:init()
    end

    scene:addChild(infoSelf)
    return infoSelf
end
