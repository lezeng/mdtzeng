require "script/CCBReaderLoad"
require "script/Protocol"
require "script/json"


local LuaUIGirl = createCCBClase("LuaUIGirl")
local LuaUIGirlPage = nil

local danceLyaer = nil  --跳舞动画
local poemLyaer = nil

local LayerZOrder = {
    "GirlList", --佳人列表
    "Menu",     --功能按钮
    "Anime",    --动画
}
LayerZOrder = CreatEnumTable(LayerZOrder, 1)

local SpriteZOrder = {
    "GirlBack",     --
    "GirlFront",    --
    "CoverBack",    --
    "TempBack",     --
    "TempFront",    --
    "CoverFront",   --
    "Menu",         --功能按钮
    "Particle",     --鲜花粒子
    "Anime",        --功能动画
}
SpriteZOrder = CreatEnumTable(SpriteZOrder, 0)


function LuaUIGirlOpen(scene)
    local node = CCBuilderReaderLoad("LuaUIGirl.ccbi", CCBProxy:create(), LuaUIGirl)
    node = tolua.cast(node, "CCLayer")

    LuaUIGirlPage = LuaUIGirl.extend(node)
    if LuaUIGirlPage then
        LuaUIGirlPage:setTouchPriority(scene:getTouchPriority())
        LuaUIGirlPage:init()
        scene:addChild(LuaUIGirlPage)
    end

    TutorialManager:getSingleton():gotoNextStep()
end

function LuaUIGirl:init()
    utils.registeSwallowTouch(self, self:getTouchPriority())

    self.addMenuItemA:setZoomTarget(self.addMenuA:getParent())
    self.addMenuA:setTouchPriority(self:getTouchPriority()-LayerZOrder.Menu)
    self.addMenuItemB:setZoomTarget(self.addMenuB:getParent())
    self.addMenuB:setTouchPriority(self:getTouchPriority()-LayerZOrder.Menu)
    self:registeNodeEvent()

    self.addMenuA:getParent():setZOrder(SpriteZOrder.Menu)
    self.addMenuB:getParent():setZOrder(SpriteZOrder.Menu)
    self.remainNode:setZOrder(SpriteZOrder.Menu)
    self.sgywDesc:setZOrder(SpriteZOrder.Menu)
    self.hssmDesc:setZOrder(SpriteZOrder.Menu)
    self.coverFront:setZOrder(SpriteZOrder.CoverFront)
    self.coverBack:setZOrder(SpriteZOrder.CoverBack)

    local winSize = CCDirector:sharedDirector():getWinSize();
    local particlePos = ccp(winSize.width/2, winSize.height)
    for i=1,3 do
        local emitter = CCParticleSystemQuad:create("Particles/yinghua"..i..".plist");
        emitter:setPosition(particlePos);
        self:addChild(emitter, SpriteZOrder.Particle);
    end

    -- self.sgywDesc:setString("（好感度全部+"..ConfigManager.GetItemById(GlobalConfig.PalaceSGYWGainFavor).val.."）")
    self.sgywDesc:setString("（全体加1心好感度）")
    self.hssmDesc:setString("（好感度"..ConfigManager.GetItemById(GlobalConfig.PalaceHMSSFavorLastDay).val.."天不减）")
    self.sgywCost:setString(ConfigManager.GetItemById(GlobalConfig.PalaceSGYWMoneyCost).val)
    self.hmssCost:setString(ConfigManager.GetItemById(GlobalConfig.PalaceHMSSMoneyCost).val)

    LuaGirlManager.selectGirlIndex = 1
    self:createGirlList()
    self:refreshRemainTime()
end

function LuaUIGirl:registerProxy()
    print("后宫注册事件")
    self.eventProxy = MyLuaProxy.newProxy("LuaUIGirl.lua")
    if not self.eventProxy then return end

    function onLuaUIGirlMsg( msgId , jsonstr)
        local data = json.decode(jsonstr)
        dump(data)
        if msgId == Protocol.SC_SGYW then
            if data[ProtocolStr_Rtn] == 0 then
                self:refreshAll()
            else
                _printRequestMsg(msgId, data[ProtocolStr_Rtn])
            end
            _clearWaiting()

        elseif msgId == Protocol.SC_HMSS then
            if data[ProtocolStr_Rtn] ~= 0 then
                _printRequestMsg(msgId, data[ProtocolStr_Rtn])
            end
            _clearWaiting()

        elseif msgId == Protocol.SC_SendPalaceInfo then
            self:refreshAll()
            _clearWaiting()

        elseif msgId == Protocol.SC_SendPalaceInfoOne then
            local girlCell = self.activeCellList[LuaGirlManager.selectGirlIndex]
            local girlData = LuaGirlManager.activeGirlList[LuaGirlManager.selectGirlIndex]
            girlCell:updateLikeValue(girlData.likeValue)

        elseif msgId == Protocol.SC_Palace_EndReduceFavorTime then
            self:refreshRemainTime()
        end
    end

    self.eventProxy:addMsgListener(Protocol.SC_SGYW, "onLuaUIGirlMsg")
    self.eventProxy:addMsgListener(Protocol.SC_HMSS, "onLuaUIGirlMsg")
    self.eventProxy:addMsgListener(Protocol.SC_SendPalaceInfo, "onLuaUIGirlMsg")
    self.eventProxy:addMsgListener(Protocol.SC_SendPalaceInfoOne, "onLuaUIGirlMsg")
    self.eventProxy:addMsgListener(Protocol.SC_Palace_EndReduceFavorTime, "onLuaUIGirlMsg")
end

-- 刷新所有后宫UI（目前仅刷新好感度）
function LuaUIGirl:refreshAll()
    for idx=1, #LuaGirlManager.activeGirlList do
        self.activeCellList[idx]:updateLikeValue(LuaGirlManager.activeGirlList[idx].likeValue)
    end
end

function LuaUIGirl:createGirlList()
    local activeCount = GirlsMgr:getSingleton():getActiveCount()
    local deactiveCount = GirlsMgr:getSingleton():getDeactiveCount()

    LuaGirlManager.activeGirlList = {}
    self.activeCellList = {}
    for idx=1,activeCount do
        table.insert(LuaGirlManager.activeGirlList,0)
        table.insert(self.activeCellList,0)
    end

    local distance = nil
    local backMove = 80 --第二排错位显示，右移距离

    local girlContainer = CCLayer:create()

    local countBack = 0
    for idx=3,activeCount+deactiveCount,2 do
        local girlData = GirlsMgr:getSingleton():getGirlByIndex(idx-1)
        local myGirl = require("script/CCGirl").create(girlData, idx, self:getTouchPriority())
        myGirl:updateUI()

        -- 获取后宫显示宽度
        if distance == nil then
            local girlWidth = myGirl:getContentSize().width
            -- 后宫图片交错叠加显示
            distance = girlWidth * 0.6
        end

        myGirl:setPositionX(distance * countBack -40 + backMove)
        myGirl:setPositionY(90)
        if girlData.isActive then
            girlContainer:addChild(myGirl, SpriteZOrder.GirlFront)
            LuaGirlManager.activeGirlList[idx] = girlData
            self.activeCellList[idx] = myGirl
        else
            girlContainer:addChild(myGirl, SpriteZOrder.GirlBack)
        end
        countBack = countBack + 1
    end
    self.coverBack:removeFromParentAndCleanup(false)
    girlContainer:addChild(self.coverBack)

    local countFront = 0
    local idx = 1
    local girlData = GirlsMgr:getSingleton():getGirlByIndex(idx-1)
    local myGirl = require("script/CCGirl").create(girlData, idx, self:getTouchPriority())
    myGirl:updateUI()
    myGirl:setPositionX(distance * countFront -40)
    if girlData.isActive then
        girlContainer:addChild(myGirl, SpriteZOrder.TempFront)
        if tonumber(girlData.id) == LuaGirlManager.firstGirlId then
            myGirl:setTutorialStepId(36020801)
        end
        LuaGirlManager.activeGirlList[idx] = girlData
        self.activeCellList[idx] = myGirl
    else
        girlContainer:addChild(myGirl, SpriteZOrder.TempBack)
    end
    countFront = countFront + 1
    for idx=2,activeCount+deactiveCount,2 do
        local girlData = GirlsMgr:getSingleton():getGirlByIndex(idx-1)
        local myGirl = require("script/CCGirl").create(girlData, idx, self:getTouchPriority())
        myGirl:updateUI()
        myGirl:setPositionX(distance * countFront -40)
        if girlData.isActive then
            girlContainer:addChild(myGirl, SpriteZOrder.TempFront)
            LuaGirlManager.activeGirlList[idx] = girlData
            self.activeCellList[idx] = myGirl
        else
            girlContainer:addChild(myGirl, SpriteZOrder.TempBack)
        end
        countFront = countFront + 1
    end

    -- 计算滑动区域宽度
    local newWidth = 0
    if countBack >= countFront then
        newWidth = distance * countBack + backMove
    else
        newWidth = distance * countFront
    end

    self.girlList = tolua.cast(self.girlList, "CCScrollView")

    if newWidth > self.girlList:getContentSize().width then
        girlContainer:setContentSize(CCSizeMake(newWidth, self.girlList:getContentSize().height))
    else
        girlContainer:setContentSize(self.girlList:getContentSize())
    end
    self.girlList:setContainer(girlContainer)
    self.girlList:setContentSize(girlContainer:getContentSize())

    self.girlList:setTouchEnabled(true)
    self.girlList:setTouchMode(kCCTouchesOneByOne)
    self.girlList:setDirection(kCCScrollViewDirectionHorizontal)
    self.girlList:setTouchPriority(self:getTouchPriority()-LayerZOrder.GirlList)
end

--后宫列表页面好感度全部加X
function LuaUIGirl:onClickForAll(tag, sender)
    --没有后宫则点击无效
    if #LuaGirlManager.activeGirlList < 1 then return end

    warningCallBack = nil
    function warningCallBack( ... )
        danceLyaer = CCBuilderReaderLoad("CCGirlDance.ccbi", CCBProxy:create(), CCGirlDance)
        danceLyaer = tolua.cast(danceLyaer, "CCLayer")
        LuaUIGirlPage:addChild(danceLyaer, SpriteZOrder.Anime)
        utils.registeSwallowTouch(danceLyaer, LuaUIGirlPage:getTouchPriority()-LayerZOrder.Anime)
        _sendRequest(Protocol.CS_SGYW, {}, true)
    end

    local goldCast = tonumber(ConfigManager.GetItemById(GlobalConfig.PalaceSGYWMoneyCost).val)

    local playerData = PlayerMgr.getSingleton():playerWithDBId("", nil)
    if playerData.GOLD < goldCast then
        UIManager:getSingleton():showOpenShopPage()
        return
    end

    UIManager:getSingleton():openRechargeWarningForLua("是否花费"..goldCast.."元宝,进行'笙歌艳舞'?","确定")
end

--好感度X天不减
function LuaUIGirl:onClickDays(tag, sender)
    --没有后宫则点击无效
    if #LuaGirlManager.activeGirlList < 1 then return end
    
    warningCallBack = nil
    function warningCallBack( ... )
        poemLyaer = CCBuilderReaderLoad("CCGirlPoem.ccbi", CCBProxy:create(), CCGirlPoem)
        poemLyaer = tolua.cast(poemLyaer, "CCLayer")
        LuaUIGirlPage:addChild(poemLyaer, SpriteZOrder.Anime)
        utils.registeSwallowTouch(poemLyaer, LuaUIGirlPage:getTouchPriority()-LayerZOrder.Anime)
        _sendRequest(Protocol.CS_HMSS, {}, true)
    end

    local goldCast = tonumber(ConfigManager.GetItemById(GlobalConfig.PalaceHMSSMoneyCost).val)

    local playerData = PlayerMgr.getSingleton():playerWithDBId("", nil)
    if playerData.GOLD < goldCast then
        UIManager:getSingleton():showOpenShopPage()
        return
    end

    UIManager:getSingleton():openRechargeWarningForLua("是否花费"..goldCast.."元宝,进行'海誓山盟'?","确定")
end

-- 刷新海誓山盟剩余时间
function LuaUIGirl:refreshRemainTime( ... )
    local remainTime = LuaGirlManager.getRemainTime()
    if remainTime > 0 then
        local day = math.ceil(remainTime/86400)
        self.remainNode:setVisible(true)
        self.remainTime:setString(day.."天）")
    else
        self.remainNode:setVisible(false)
    end
end


CCGirlDance = class( "CCGirlDance" )
CCGirlDance.__index = CCGirlDance
ccb["CCGirlDance"] = CCGirlDance

function CCGirlDance:endAnimation( tag,sender )
    if danceLyaer ~= nil then
        danceLyaer:removeFromParentAndCleanup(true)
    end
end

CCGirlPoem = class( "CCGirlPoem" )
CCGirlPoem.__index = CCGirlPoem
ccb["CCGirlPoem"] = CCGirlPoem

function CCGirlPoem:endAnimation( tag,sender )
    if poemLyaer ~= nil then
        poemLyaer:removeFromParentAndCleanup(true)
    end
end
