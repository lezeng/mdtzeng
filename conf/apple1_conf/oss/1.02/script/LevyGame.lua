require("script/LoadLevyCoinConfig")
require("script/ConfigManager")
require("script/UserInfoManager")
local scheduler = require("script/scheduler")

-- Hx@2015-07-27 : 结算界面也放在了里面
-- 应该提取一个公共的出来

-- Hx@2015-07-24 : 方向
DirectionType = {
    "Left",
    "Right",
    "Stop",
}
DirectionType = CreatEnumTable(DirectionType)

LevyCoinType = {
    "Small",
    "Large",
}
LevyCoinType = CreatEnumTable(LevyCoinType, 1)

LevyGameState = {
    "Load",
    "Play",
    "Summary",
}
LevyGameState = CreatEnumTable(LevyGameState)

-- ===========================================================================
-- Hx@2015-07-27 : 钱币
-- ===========================================================================

LevyCoin = class("LevyGameCoin", function()
    return CCSprite:createWithSpriteFrameName("tonqianbi.png")
end)
LevyCoin.__index = LevyCoin

function LevyCoin:ctor(emCoinType, fFadeOutDistance)
    bindScriptHandler(self)

    self.bDestory = false

    self:setZOrder(0)

    self.emType = emCoinType
    if self.emType == LevyCoinType.Small then
        self:setScale(0.65)
    elseif self.emType == LevyCoinType.Large then
        self:setScale(1)
    else
        showLuaErr(ErrorCode.ERROR, "unkonwn type:%s", self.emType)
        return 
    end

    local tConf = getLevyCoinConfig(UserInfoManager.userLevel(), self.emType)
    self.fDropTime = tConf[LevyCoinConfigAttr.DropTime]

    local objWinSize = CCDirector:sharedDirector():getWinSize()
    self.fFadeInTime = self.fDropTime * 100 / objWinSize.height
    self.fFadeOutTime = self.fDropTime * fFadeOutDistance / objWinSize.height
end

function LevyCoin:onEnterTransitionDidFinish()
    self:init()
end

function LevyCoin:init()
    local objWinSize = CCDirector:sharedDirector():getWinSize()
    local objSize = self:getContentSize()
    self:setPosition(ccp(
        math.random(objWinSize.width - objSize.width) + objSize.width / 2,
        objWinSize.height + objSize.height / 2
    ))

    self:runAction(CCRepeatForever:create(createSequence(
            CCOrbitCamera:create(math.random(0.3, 0.5), 1, 0, 0, 360, math.random(180), 0)
    )))
    self:runAction(CCFadeIn:create(self.fFadeInTime))
    self:runAction(createSequence(
        CCEaseIn:create(
            CCMoveBy:create(self.fDropTime, ccp(0, -(objWinSize.height + objSize.height))), 2
        ),
        CCDelayTime:create(self.fDropTime - self.fFadeOutTime),
        CCCallFunc:create(handler(self, self.destory))
    ))
end

function LevyCoin:destoryWithFadeOut()
    if self.bDestory then
        return
    end

    self.bDestory = true

    self:runAction(createSequence(
        CCFadeOut:create(self.fFadeOutTime),
        CCCallFunc:create(handler(self, self.destory))
    ))
end

--[[
function LevyCoin:destoryWithAnimation()
    if self.bDestory then
        return
    end

    self.bDestory = true

    self:stopAllActions()
    
    self:runAction(
        create_animation("effect11_.plist", "effect11_", 0.07, 1, 10, 1)
    )

    self:runAction(createSequence(
        CCDelayTime:create(0.07 * 10),
        CCCallFunc:create(handler(self, self.destory))
    ))
end
--]]

function LevyCoin:destory()
    self:removeFromParentAndCleanup(true)
end

function LevyCoin:getType()
    return self.emType 
end

-- ===========================================================================
-- Hx@2015-07-27 :场景
-- ===========================================================================

LevyGame = class("LevyGame", function() 
    return CCBClass.new("LuaUILevyGame.ccbi", "CCLayer")
end)
LevyGame.__index = LevyGame

function LevyGame:ctor()
    self:bindCcbProxy()
    bindScriptHandler(self)
    bindScriptTouchHandler(self, -127, true)
    self.objMsgProxy = LuaMsgProxy()

    -- 最大速度
    self.fMaxSpeed = 14

    -- 游戏时间
    self.iGameTime = ConfigManager.GetItemById(GlobalConfig.LevyGameTime).val
    -- 得分
    self.iScore = 0
    -- 翻倍次数
    self.iScoreMultiTime = 0
    -- 翻倍花费
    self.iScoreMultiCost = 0
    --游戏状态
    self.emGameState = nil
    --服务器验证号
    self.iPassport = nil

    --铜钱使用了翻转效果，所以不能使用
    --self.ccBatchNode = CCSpriteBatchNode:create("zc-yaoqianshu.pvr.ccz", 10)

    self.ccCoinsLayer = CCLayer:create()
    self.ccCoinsLayer:setZOrder(-1)
    self.ccMainScene:addChild(self.ccCoinsLayer)

    local objWinSize = CCDirector:sharedDirector():getWinSize()
    local objSize = self.ccBowl:getContentSize()
    self.iBowlMaxRight = objWinSize.width - objSize.width / 2
    self.iBowlMinLeft = objSize.width / 2
    self.ccBowl:setZOrder(100)

    self.ccGameCountDown = tolua.cast(self.ccGameCountDown, "CCLabelTTF")   
    self.ccLoadCountDown = tolua.cast(self.ccLoadCountDown, "CCSprite")
    self.ccScore = tolua.cast(self.ccScore, "CCLabelTTF")
    self.ccSummaryScore = tolua.cast(self.ccSummaryScore, "CCLabelTTF")
    self.ccCostText = tolua.cast(self.ccCostText, "CCLabelTTF")
    self.ccMultiText = tolua.cast(self.ccMultiText, "CCLabelTTF")
    self.ccVipTip = tolua.cast(self.ccVipTip, "CCLabelTTF")

    tolua.cast(tolua.cast(self.ccMultiButton, "CCMenuItemSprite"):getDisabledImage(), "CCSprite"):addGray()
end

function LevyGame:onEnterTransitionDidFinish()
    self.objMsgProxy:addMsgListener(Protocol.SC_Levy, handler(self, self.onSCLevy))
    self.objMsgProxy:addMsgListener(Protocol.SC_Levy_Rewards, handler(self, self.onSCLevyRewards))

    self:CSLevy()
end

function LevyGame:onExitTransitionDidStart()
    self:disableAccelerate()

    self.objMsgProxy:removeMsgListener(Protocol.SC_Levy)
    self.objMsgProxy:removeMsgListener(Protocol.SC_Levy_Rewards)
end

function LevyGame:enableAccelerate()
    self:setAccelerometerEnabled(true)
    self:registerScriptAccelerateHandler(handler(self, self.onAccelerate))
end

function LevyGame:disableAccelerate()
    self:unregisterScriptAccelerateHandler()
end

function LevyGame:startProduceCoin()
    self.schedulerCoinDropHandler = scheduler.scheduleGlobal(
        handler(self, self.schedulerProduceCoin), 0.2
    )
end

function LevyGame:schedulerProduceCoin()
    local emType = randCoinType(UserInfoManager.userLevel())
    if not emType then
        return
    end

    self.ccCoinsLayer:addChild(LevyCoin.new(emType, self.ccBowl:getContentSize().height / 2))
end

function LevyGame:stopProduceCoin()
    scheduler.unscheduleGlobal(self.schedulerCoinDropHandler)
end

function LevyGame:startLoadGame()
    local iLoadCountDown = 3
    local objCountDownSeq = createSequence(
        CCCallFunc:create(function()
            local strName = string.format("djs%d.png", iLoadCountDown)
            local objFrame = CCSpriteFrameCache:sharedSpriteFrameCache():spriteFrameByName(strName)
            self.ccLoadCountDown:setDisplayFrame(objFrame)
            iLoadCountDown = iLoadCountDown - 1
        end),
        CCDelayTime:create(1)
    )

    self:runAction(createSequence(
        CCRepeat:create(objCountDownSeq, iLoadCountDown),
        CCCallFunc:create(function() 
            self:changeState(LevyGameState.Play)
        end)
    ))
end

function LevyGame:startGame()
    self.ccLoad:setVisible(false)
    self.ccMainScene:setVisible(true)

    self.iGameTime = os.time() + self.iGameTime

    self:enableAccelerate()
    self:startProduceCoin()

    self.schedulerGameHandler = scheduler.scheduleUpdateGlobal(handler(self, self.schedulerGame))
end

function LevyGame:stopGame()
    scheduler.unscheduleGlobal(self.schedulerGameHandler)
end

function LevyGame:onAccelerate(x, y, z, timestamp)
    local iPosition = self.ccBowl:getPositionX() + x * self.fMaxSpeed
    if iPosition > self.iBowlMaxRight then
        iPosition = self.iBowlMaxRight
    elseif iPosition < self.iBowlMinLeft then
        iPosition = self.iBowlMinLeft
    end
    self.ccBowl:setPositionX(iPosition)
end

function LevyGame:schedulerGame()
    self:checkBounding()
    self:updateCountDown()
end

function LevyGame:checkBounding()
    local tChildArr = self.ccCoinsLayer:getChildren()
    if not tChildArr then
        return
    end

    for i = 1,tChildArr:count() do
        local objCoin = tolua.cast(tChildArr:objectAtIndex(i - 1), "CCNode")
        local objPos = self.ccMainScene:convertToNodeSpace(
            self.ccBowl:convertToNodeSpace(
                ccp(objCoin:getPositionX(), objCoin:getPositionY())
            )
        )
        local objSize = self.ccBowl:getContentSize()

        if self.ccBowlBounding:boundingBox():containsPoint(objPos) then
            local tConf = getLevyCoinConfig(UserInfoManager.userLevel(), objCoin:getType())

            local objSprite = CCSprite:createWithSpriteFrameName("effect11_01.png")
            objSprite:runAction(createSequence(
                create_animation("effect11_.plist", "effect11_", 0.07, 1, 10, 1),
                CCEaseSineOut:create(
                    CCMoveTo:create(1, ccp(self.ccScore:getPositionX(), self.ccScore:getPositionY()))
                ),
                CCCallFunc:create(function() 
                    self:addScore(tConf[LevyCoinConfigAttr.Value])
                    if self.emGameState == LevyGameState.Summary then
                        self:updateSummaryFrame()
                    end
                    objSprite:removeFromParentAndCleanup(true)
                end)
            ))
            local objLabel = CCLabelTTF:create(tConf[LevyCoinConfigAttr.Value], "Arial", 14)
            objSprite:addChild(objLabel)
            self:addChild(objSprite)

            objSprite:setPosition(ccp(objCoin:getPositionX(), objCoin:getPositionY()))
            local objSize = objSprite:getContentSize()
            objLabel:setPosition(ccp(objSize.width / 2, objSize.height / 2))
            objCoin:destory()

            SoundMgr:getSingleton():playLuaEff("tongqian.mp3", false);
            break
        end

        if objCoin:getPositionY() < self.ccBowlBounding:getPositionY() then
            objCoin:destoryWithFadeOut()   
        end
    end
end

function LevyGame:addScore(iVal)
    assert(iVal)
    self.iScore = self.iScore + iVal
    self.ccScore:setString(self.iScore)
end

function LevyGame:updateCountDown()
    local iRemain = self.iGameTime - os.time()
    if iRemain <= 0 then
        self.ccGameCountDown:setString("00:00")
        scheduler.unscheduleGlobal(self.schedulerGameHandler)
        self:stopProduceCoin()
        self:changeState(LevyGameState.Summary)
        return
    end
    local iMin = math.floor(iRemain / 60)
    local iSec = iRemain % 60
    self.ccGameCountDown:setString(string.format("%.2d:%.2d", iMin, iSec))
    if iMin == 0 and iSec <= 3 then
        self.ccGameCountDown:setColor(ccc3(255, 0, 0))
    end
end

function LevyGame:changeState(iState)
    assert(iState)
    self.emGameState = iState
    if iState == LevyGameState.Load then
        self.ccLoad:setVisible(true)
        self.ccMainScene:setVisible(false)
        self.ccSummary:setVisible(false)
        self:startLoadGame()

    elseif iState == LevyGameState.Play then
        self.ccLoad:setVisible(false)
        self.ccMainScene:setVisible(true)
        self.ccSummary:setVisible(false)
        self:startGame()

    elseif iState == LevyGameState.Summary then
        self.ccLoad:setVisible(false)
        self.ccMainScene:setVisible(false)
        self.ccSummary:setVisible(true)
        self:stopGame()
        self:startSummary()
    else
        showLuaErr(ErrorCode.ERROR, "unknown state:%s", iState)
    end
end

function LevyGame:startSummary()
    self.ccSummary:setScale(0)
    -- disable touch a while
    self:setTouchEnabled(false)
    self.ccSummary:runAction(createSequence(
        CCScaleTo:create(0.4, 1),
        CCCallFunc:create(function()
            self:setTouchEnabled(true)
            self:updateSummaryFrame()       
        end)
    )) 

    local iMultiFactor = tonumber(ConfigManager.GetItemById(GlobalConfig.LevyMultiFactor).val)
    self.ccMultiText:setString(string.format("翻%s倍", iMultiFactor))

    --[[
    self.ccShine:runAction(createSequence(
        CCRepeatForever:create(createSequence(
            
        ))
    ))
    --]]
end

function LevyGame:updateSummaryFrame()
    local iMultiFactor = tonumber(ConfigManager.GetItemById(GlobalConfig.LevyMultiFactor).val)
    self.ccSummaryScore:setString(math.floor(self.iScore * math.pow(iMultiFactor, self.iScoreMultiTime)))
    local objPlayer = PlayerMgr:getSingleton():playerWithDBId("",nil)

    local tVipConf = VipConfMgr:getSingleton():getVipByLevel(objPlayer.curVIPRank)

    DEBUG("gold:%s,cost:%s", objPlayer.GOLD, self.iScoreMultiCost)
    if self.iScoreMultiTime >= tVipConf.levycount then
        self.ccVipTip:setVisible(true)
        self.ccUpArrow:setVisible(false)
        self.ccMultiButton:setEnabled(false)
    elseif objPlayer.GOLD - self.iScoreMultiCost <= 0 then
        self.ccVipTip:setVisible(true)
        self.ccUpArrow:setVisible(false)
        self.ccMultiButton:setEnabled(false)
        self.ccVipTip:setString("(金币不足)")
    else
        self.ccVipTip:setVisible(false)
    end

    local iCost = ResetCostManager:getSingleton():getCostByType(ResetCostType.LevyMultiCost, self.iScoreMultiTime + 1)
    self.ccCostText:setString(iCost)
end

function LevyGame:onMultiClick()
    self.iScoreMultiTime = self.iScoreMultiTime + 1
    self.iScoreMultiCost = self.iScoreMultiCost + self.ccCostText:getString()
    self:updateSummaryFrame()
end

function LevyGame:onTouchBegan(x, y)
    return true
end

function LevyGame:onTouchEnded(x, y)
    if self.emGameState == LevyGameState.Summary then
        if self.ccSummaryContainer:boundingBox():containsPoint(ccp(x, y)) then
            return
        end
        self:CSLevyRewards()
    end
end

function LevyGame:exit()
    UIManager:getSingleton():setUIHudTVisible(true)
    UIManager:getSingleton():removeTopLayer()
end

function LevyGame:onSCLevy(emMsgID, strMsg)
    _clearWaiting()
    local tMsg = json.decode(strMsg)
    if tMsg[ProtocolStr_Rtn] ~= ErrorCode.OK then
        _openWarning("开启征收游戏失败")
        self:runAction(createSequence(
            CCDelayTime:create(1),
            CCCallFunc:create(function()
                self:exit()
            end)
        ))
        return
    end
    self.iPassport = tMsg[ProtocolStr_ID]
    self:changeState(LevyGameState.Load)
end

function LevyGame:onSCLevyRewards(emMsgID, strMsg)
    _clearWaiting()
    local tMsg = json.decode(strMsg)
    if tMsg[ProtocolStr_Rtn] ~= ErrorCode.OK then
        _openWarning("ERROR:"..tMsg[ProtocolStr_Rtn])       
    end
    self:exit()
end

function LevyGame:CSLevyRewards()
    local tMsg = {}
    tMsg[ProtocolStr_Request] = Protocol.CS_Levy_Rewards
    tMsg[ProtocolStr_ID] = self.iPassport
    tMsg[ProtocolStr_Info] = {}
    tMsg[ProtocolStr_Info][1] = tonumber(self.ccSummaryScore:getString())
    tMsg[ProtocolStr_Info][2] = self.iScoreMultiCost
    sendRequest(tMsg, true)
end

function LevyGame:CSLevy()
    local tMsg = {}
    tMsg[ProtocolStr_Request] = Protocol.CS_Levy
    sendRequest(tMsg, true)
end

function LuaUILevyGameOpen(scene)
    scene:addChild(LevyGame.new())
end
