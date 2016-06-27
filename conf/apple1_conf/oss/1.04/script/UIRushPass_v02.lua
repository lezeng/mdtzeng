require("script/RushPassCell")
require("script/LuaUIRankDesc")
require("script/LoadNewBEAT")
require("script/UIGetItem")

local UIRushPass = class("UIRushPass", function()
    return CCBClass.new("LuaUIRushPass_v02.ccbi", "CCLayer")
end)

function UIRushPass:ctor(touchPriority)
    assert(touchPriority)
    self:bindCcbProxy()
    bindScriptHandler(self)
    self.msgProxy = LuaMsgProxy()
    utils.registeSwallowTouch(self, touchPriority)

    self.cells = {}

    self.progressBarWidth = self.ccProgressBar:boundingBox().size.width
    self.progressBarPos = ccp(self.ccProgressBar:getPositionX(), self.ccProgressBar:getPositionY())
    self.ccBox:setVisible(false)
    self.progressBoxes = {}

    self.maxCount = 2

    self.cost = 0

    self.scope = Game:getMemento():get(UIRushPass.__cname) or {}
    Game:getMemento():clear()

    self.ccFormationBtn:setTouchPriority(touchPriority - 1)
    self.ccFormationBtnImg:setZoomTarget(self.ccFormationBtn:getParent())
    self.ccHelpBtn:setTouchPriority(touchPriority - 1)
    self.ccHelpBtnImg:setZoomTarget(self.ccHelpBtnImg)
    -- self.ccResetBtn:setTouchPriority(touchPriority - 1)
    -- self.ccResetBtnImg:setZoomTarget(self.ccResetBtn:getParent())
    self.ccRankBtn:setTouchPriority(touchPriority - 1)
    self.ccRankBtnImg:setZoomTarget(self.ccRankBtn:getParent())

    local progress = CCProgressTimer:create(CCSprite:createWithSpriteFrameName("cgzgtiao0.png"))
    progress:setPosition(self.progressBarPos)
    progress:setScaleY(1.2)
    progress:setType(kCCProgressTimerTypeBar)
    progress:setBarChangeRate(ccp(1,0))
    progress:setMidpoint(ccp(0,0))
    progress:setZOrder(-1)
    progress:setScaleX(self.ccProgressBar:getScaleX())
    self.ccProgressBar:getParent():addChild(progress)
    self.ccProgressBar:removeFromParentAndCleanup(true)
    self.ccProgressBar = progress

    self:initLevelData()
end

function UIRushPass:tryToGoFightOver()
    if Game:getRushPassModel():checkFightOver() then
        function warningCallBack()
            warningCallBack = nil
        end
        UIManager:getSingleton():openRechargeWarningForLua(
            "闯关结束，请大侠重新再来！\n本次闯关到达了"..(self.scope.layer).."层","确定"
        )
        Game:getRushPassModel():resetFightOver()
        Game:getRushPassModel():setStartBtnClicked(false)
    end
end

function UIRushPass:onEnter()
    self.msgProxy:addMsgListener(Protocol.SC_NewBEAT_Rank, handler(self, self.uiChange))
    self.msgProxy:addMsgListener(Protocol.SC_BuyResetCount, handler(self, self.uiChange))

    self:tryToGoFightOver()

    if not isTableEmpty(self.scope) then
        self:uiSet()
    end

    -- guide
    self.ccPointer:setTutorialStepId(36020310)
    self.ccFormationBtn:setTutorialStepId(36020311)
    self.cells[#self.cells]:setTutorialStepId(36020312)
    self.ccStartBtn:setTutorialStepId(36020314)
end

function UIRushPass:initLevelData()
    self.ccLevel:removeAllChildrenWithCleanup(true)
    local map = {
        {x=1, y=0},
        {x=0.5, y=0.5},
        {x=0, y=1},
    }
    local objSize = self.ccLevel:getContentSize()
    for k, v in ipairs(map) do
        local objCell = RushPassCell.new(self:getTouchPriority() - 1)
        objCell:setPosition(ccp(objSize.width * v.x, objSize.height * v.y))
        self.ccLevel:addChild(objCell)
        self.cells[k] = objCell
        objCell:setVisible(false)
    end
end

function UIRushPass:onHelpClick()
    UIManager:getSingleton():openLuaPageWithArgs(
        "script/LuaUIRankDesc.lua","LuaUIRankDescOpen","LuaUIRankDesc",
        json.encode({pageType = EmPage.RushPass})
    )
end

function UIRushPass:onRankListClick()
    UIManager:getSingleton():openLuaPageWithArgs(
        "script/LuaUIRushPassRank.lua", "RushPassRankOpen", "RushPassRank", 
        json.encode({pageType=EmPage.RushPass})
    )
end

function UIRushPass:onFormationClick()
    UIManager:getSingleton():openLuaPageWithArgs(
        "script/LuaUIForm.lua", "LuaUIFormOpen", "LuaUIForm", 
        json.encode({type=FormationUseType.NewBEATComplete})
    )
    TutorialManager:getSingleton():gotoNextStep()
end

function UIRushPass:csReset()
    local tMsg = {}
    tMsg[ProtocolStr_Request] = Protocol.CS_BuyResetCount
    tMsg[ProtocolStr_Type] = ResetCostType.NewBEAT
    sendRequest(tMsg)
end

function UIRushPass:goReset()
    local objPlayer = PlayerMgr.getSingleton():playerWithDBId("", nil)
    local curReset = LuaCountManager.getReset(CountType.NewBEAT)
    local maxReset = VipConfMgr:getSingleton():getVipByLevel(objPlayer.curVIPRank).NewBEAT
    local resetCost = ResetCostManager.getSingleton():getCostByType(ResetCostType.NewBEAT, curReset + 1)


    -- function warningCallBack()

    --     --local objPlayer = PlayerMgr.getSingleton():playerWithDBId("", nil)
    --     local remain = maxReset - curReset

    --     if remain <= 0 then 
    --         function warningCallBack( )
    --             UIManager:getSingleton():openShop()
    --         end
    --         UIManager:getSingleton():openRechargeWarningForLua("重置次数不足，充值VIP可以获得更多重置次数","充值")
    --     elseif objPlayer.GOLD < resetCost then
    --         UIManager:getSingleton():showOpenShopPage()
    --     else
    --         self:csReset()
    --         Game:getLuaRushPassModel():setStartBtnClicked(false)
    --     end
    -- end
    -- UIManager:getSingleton():openPayWarningForLua(
    --     "是否花费"..resetCost.."元宝重置?",
    --     maxReset - curReset, maxReset, "重置"
    -- )

    local objPlayer = PlayerMgr.getSingleton():playerWithDBId("", nil)
    local remain = maxReset - curReset
    if remain <= 0 then 
        function warningCallBack( )
            UIManager:getSingleton():openShop()
        end
        UIManager:getSingleton():openRechargeWarningForLua("购买次数不足，充值VIP可以获得更多购买次数","充值")
    elseif objPlayer.GOLD < resetCost then
        UIManager:getSingleton():showOpenShopPage()
    else
        function warningCallBack()
            self:csReset()
            Game:getRushPassModel():setStartBtnClicked(false)
            if GameData:getSingleton().m_purchaseDesc then
                GameData:getSingleton().m_purchaseDesc = "购买闯关次数"
            end
        end
        UIManager:getSingleton():openPayWarningForLua(
            "是否花费"..resetCost.."元宝购买1次闯关次数",
            maxReset - curReset, maxReset, "购买"
        )
    end
end

----------------
function UIRushPass:onEnterTransitionDidFinish()
    Game:getRushPassModel():update()
end

function UIRushPass:uiSet()
    self:uiSetLayerText(self.scope.layer)
    self:uiSetLayerData(self.scope.layerData)
    self:uiSetExploit(self.scope.exploit)
    -- self:uiSetResetCost(self.scope.curReset)
    self:uiSetAddition(self.scope.addition)
    self:uiSetMaxLayer(self.scope.maxLayer)
    self:uiSetMaxExploit(self.scope.maxExploit)
    self:uiUpdateStartLayer()
end


function UIRushPass:uiChange()
    _clearWaiting()
    local data = {}
    data.layer = Game:getRushPassModel():getCurLayer()
    data.layerData = Game:getRushPassModel():getCurLayerData()
    data.exploit = Game:getRushPassModel():getCurExploit()
    -- data.curReset = LuaCountManager.getReset(CountType.NewBEAT)
    data.addition = Game:getRushPassModel():getCurAddition()
    data.maxLayer = Game:getRushPassModel():getMyMaxLayer()
    data.maxExploit = Game:getRushPassModel():getMyMaxExploit()

    if isTableEmpty(self.scope) then
        self.scope = data
    end
    
    self:uiSet()

    if self.scope.layer ~= data.layer then
        self:uiChangeLayerText(data.layer, self.scope.layer)
    end

    if not isSameTable(self.scope.layerData, data.layerData) then
        self:uiChangeLayerData(data.layerData, self.scope.layerData)
    end

    if self.scope.exploit ~= data.exploit then
        self:uiChangeExploit(data.exploit, self.scope.exploit)
    end

    self:uiSetAddition(data.addition)
    self:uiSetMaxLayer(data.maxLayer)
    self:uiSetMaxExploit(data.maxExploit)
    -- self:uiSetResetCost(data.curReset)

    self.scope = data
    -- @11/09 ZLu 页面刷新有问题，【开始状态】的显示判定了(UIRushPass:uiUpdateStartLayer)self.scope.exploit == 0)
    -- uiUpdateStartLayer的调用需要在更新赋值后调用
    self:uiUpdateStartLayer()

    Game:getMemento():save(UIRushPass.__cname, self.scope)
end

function UIRushPass:uiUpdateStartLayer()
    local curCount = LuaCountManager.getCount(CountType.NewBEAT)
    if Game:getRushPassModel():checkFightOver()
        or curCount >= self.maxCount + LuaCountManager.getReset(CountType.NewBEAT) * 1
        or (self.scope.exploit == 0 and Game:getRushPassModel():checkStartBtnClicked() == false) 
        then
        self.ccStart:setVisible(true)
        self.ccLevel:setVisible(false)
    else
        self.ccStart:setVisible(false)
        self.ccLevel:setVisible(true)
    end

    self.ccStartText:setString("剩余闯关次数："..(self.maxCount + LuaCountManager.getReset(CountType.NewBEAT) * 1 - curCount))
end

function UIRushPass:onStartClick()
    Game:getRushPassModel():setStartBtnClicked(true)

    if LuaCountManager.getCount(CountType.NewBEAT) >= self.maxCount + LuaCountManager.getReset(CountType.NewBEAT) * 1 then
        self:goReset()
    else
        self.ccStart:setVisible(false)
        self.ccLevel:setVisible(true)
    end

    TutorialManager:getSingleton():gotoNextStep()
end

function UIRushPass:uiSetLayerText(val)
    self.ccLevelText:setString("第"..val.."层")
end

function UIRushPass:uiChangeLayerText(new, old)
    self.ccLevelText:runAction(createSequence(
        CCScaleTo:create(0.2, 1.3),
        CCCallFunc:create(function ()
            self.ccLevelText:setString("第"..new.."层")
        end),
        CCScaleTo:create(0.3, 1)
    ))
end

function UIRushPass:uiSetLayerData(val)
    for _, v in pairs(val) do
        local cell = self.cells[v[NewBEATAttr.Difficulty]]
        cell:setData(v)
        cell:setVisible(true)
    end
end

function UIRushPass:uiChangeLayerData(new, old)
    for _, v in pairs(new) do
        local cell = self.cells[v[NewBEATAttr.Difficulty]]
        cell:setVisible(true)
        cell:runAction(createSequence(
            CCDelayTime:create((v[NewBEATAttr.Difficulty] - 1) * 0.2),
            CCCallFunc:create(function()
                cell:setData(v)
            end),
            CCOrbitCamera:create(0.5, 1, 0, 270, 90, 90, 0)
        ))
    end
end

function UIRushPass:uiSetExploit(val)
    self.ccExploitText:setString(val)

    local grade = getGradeByExploit(val)
    self.ccTreasureText:setString(grade.."品宝箱")

    local minVal = getMinExploit(grade)
    local maxVal = getMaxExploit(grade)
    local curRate = (self.scope.exploit - minVal) / (maxVal - minVal)

    self.ccPointer:setPositionX(self.progressBarPos.x - self.progressBarWidth / 2 + self.progressBarWidth * curRate)
    self.ccProgressBar:setPercentage(curRate * 100)

    self:_uiSetProgressBox(grade, val)
end

function UIRushPass:_uiSetProgressBox(grade, exploit)
    DEBUG("")
    self.ccProgressBarFG:removeAllChildrenWithCleanup(true)
    local barSize = self.ccProgressBarFG:getContentSize()
    local conf = getNewBEATConfigByGrade(grade)
    for _, v in ipairs(conf) do
        local frame = nil
        if v <= exploit then
            frame = CCSprite:createWithSpriteFrameName("chestUnlocked0.png")
        else
            frame = CCSprite:createWithSpriteFrameName("chestLocked.png")
        end
        frame:setPosition(ccp(
            barSize.width * (v - getMinExploit(grade)) / (getMaxExploit(grade) - getMinExploit(grade)), 
            self.ccBox:getPositionY()
        ))
        frame:setScale(0.5)
        frame:ignoreAnchorPointForPosition(false)
        self.ccProgressBarFG:addChild(frame)
    end
    self.ccTreasureText:setString(grade.."品宝箱")
end

function UIRushPass:uiChangeExploit(new, old)
    local oldGrade = getGradeByExploit(old)
    local oldMinVal = getMinExploit(oldGrade)
    local oldMaxVal = getMaxExploit(oldGrade)
    local oldRate = (old - oldMinVal) / (oldMaxVal - oldMinVal)

    local grade = getGradeByExploit(new)
    local minVal = getMinExploit(grade)
    local maxVal = getMaxExploit(grade)
    local curRate = (new - minVal) / (maxVal - minVal)

    if oldGrade < grade then
        self.ccProgressBar:runAction(createSequence(
            CCProgressFromTo:create(0.5, self.ccProgressBar:getPercentage(), 100),
            CCProgressFromTo:create(0.5, 0, curRate * 100)
        ))
        self.ccPointer:runAction(createSequence(
            CCMoveTo:create(0.5, ccp(
                self.progressBarPos.x - self.progressBarWidth / 2 + self.progressBarWidth * 1, 
                self.ccPointer:getPositionY()
            )),
            CCMoveTo:create(0, ccp(
                self.progressBarPos.x - self.progressBarWidth / 2 + self.progressBarWidth * 0, 
                self.ccPointer:getPositionY()
            )),
            CCMoveTo:create(0.5, ccp(
                self.progressBarPos.x - self.progressBarWidth / 2 + self.progressBarWidth * curRate, 
                self.ccPointer:getPositionY()
            ))
        ))
        self:_uiSetProgressBox(grade, 0)
    elseif oldGrade > grade then
        self.ccProgressBar:runAction(createSequence(
            CCProgressFromTo:create(0.5, curRate * 100, 0),
            CCProgressFromTo:create(0.5, 100, 0)
        ))
        self.ccPointer:runAction(createSequence(
            CCMoveTo:create(0.5, ccp(
                self.progressBarPos.x - self.progressBarWidth / 2 + self.progressBarWidth * 0, 
                self.ccPointer:getPositionY()
            )),
            CCMoveTo:create(0, ccp(
                self.progressBarPos.x - self.progressBarWidth / 2 + self.progressBarWidth * 1, 
                self.ccPointer:getPositionY()
            )),
            CCMoveTo:create(0.5, ccp(
                self.progressBarPos.x - self.progressBarWidth / 2 + self.progressBarWidth * curRate, 
                self.ccPointer:getPositionY()
            ))
        ))
        self:_uiSetProgressBox(grade, 0)

    else
        self.ccProgressBar:runAction(createSequence(
            CCProgressFromTo:create(0.5, oldRate * 100, curRate * 100)
        ))
        
        self.ccPointer:runAction(createSequence(
            CCMoveTo:create(0, ccp(
                self.progressBarPos.x - self.progressBarWidth / 2 + self.progressBarWidth * oldRate, 
                self.ccPointer:getPositionY()
            )),
            CCMoveTo:create(0.5, ccp(
                self.progressBarPos.x - self.progressBarWidth / 2 + self.progressBarWidth * curRate, 
                self.ccPointer:getPositionY()
            ))
        ))
    
        
        self.ccTreasureText:setString(grade.."品宝箱")
    end

    if new < old then
        -- patch: failed 
        Game:getRushPassModel():setStartBtnClicked(false)
        self:uiUpdateStartLayer()
    elseif new > old then
        -- @12/18 ZLu 处理宝箱的提示框显示,当前逻辑在绘制宝箱和处理宝箱动画，以及弹出提示框是有问题的
        -- 暂时判定跨越了等级时，直接显示掉落
        if grade > oldGrade then
            self:showProgressBoxPrise()
        end
        self.ccProgressBarFG:removeAllChildrenWithCleanup(true)
        local barSize = self.ccProgressBarFG:getContentSize()
        local conf = getNewBEATConfigByGrade(grade)
        for _, v in ipairs(conf) do
            local frame = nil
            if v <= old then
                frame = CCSprite:createWithSpriteFrameName("chestUnlocked0.png")
            elseif old < v and v <= new then
                frame = CCSprite:createWithSpriteFrameName("chestLocked.png")
                frame:runAction(createSequence(
                    CCMoveBy:create(0, ccp(0, 6)),
                    createSpawn(
                        create_animation("chestLocked_.plist", "chestLocked_", 0.08, 1, 12, 2),
                        CCScaleTo:create(0.8, 0.8)
                    ),
                    create_animation("chestUnlocked_.plist", "chestUnlocked_", 0.08, 1, 5, 1),
                    CCMoveBy:create(0, ccp(0, -6)),
                    CCScaleTo:create(0.3, 0.5),
                    CCCallFunc:create(function ()
                        frame:setDisplayFrame(CCSpriteFrameCache:sharedSpriteFrameCache():spriteFrameByName("chestUnlocked0.png"))
                        self:showProgressBoxPrise()
                    end)
                ))
            else
                frame = CCSprite:createWithSpriteFrameName("chestLocked.png")
            end
            frame:setPosition(ccp(
                barSize.width * (v - minVal) / (maxVal - minVal), self.ccBox:getPositionY()
            ))
            frame:setScale(self.ccBox:getScale())
            self.ccProgressBarFG:addChild(frame)
        end
    end

    self.ccExploitText:runAction(createSequence(
        CCScaleTo:create(0.2, 1.3),
        CCCallFunc:create(function ()
            self.ccExploitText:setString(new)
        end),
        CCScaleTo:create(0.3, 1)
    ))
end

function UIRushPass:uiSetAddition(val)
    self.ccAtkText:setString((val[NewBEATAddAttr.Atk] * 100).."%")
    self.ccDefText:setString((val[NewBEATAddAttr.Def] * 100).."%")
    self.ccHPText:setString((val[NewBEATAddAttr.HP] * 100).."%")
end

function UIRushPass:uiSetMaxLayer(val)
    self.ccMaxLevelText:setString(val)
end

function UIRushPass:uiSetMaxExploit(val)
    self.ccMaxExploitText:setString(val)
end

-- function UIRushPass:uiSetResetCost(val)
--     local objPlayer = PlayerMgr.getSingleton():playerWithDBId("", nil)
--     self.maxReset = VipConfMgr:getSingleton():getVipByLevel(objPlayer.curVIPRank).NewBEAT

--     self.resetCost = ResetCostManager.getSingleton():getCostByType(ResetCostType.NewBEAT, val + 1)

--     self.ccResetCostText:setString(self.resetCost)
--     -- if val >= self.maxReset or objPlayer.GOLD < self.resetCost then
--     --     self.ccResetBtn:setEnabled(false)
--     -- else
--     --     self.ccResetBtn:setEnabled(true)
--     -- end
-- end

function UIRushPass:showCellBoxPrise()
    local data = Game:getNotifyDropModel():popDropInfo(SourceType.NewBEAT_NormalBox)
    if isTableEmpty(data) then
        return
    end
    UIManager:getSingleton():openLuaPageWithArgs(
        "script/UIGetItem.lua", "UIGetItemOpen", "UIGetItem", 
        json.encode(data)
    )
end

function UIRushPass:showProgressBoxPrise()
    local data = Game:getNotifyDropModel():popDropInfo(SourceType.NewBEAT)
    if isTableEmpty(data) then
        return
    end
    UIManager:getSingleton():openLuaPageWithArgs(
        "script/UIGetItem.lua", "UIGetItemOpen", "UIGetItem", 
        json.encode(data)
    )
end

----------------
function UIRushPass:onExitTransitionDidStart()
    self.msgProxy:clearMsgListener()
end

----------------
function UIRushPassOpen(scene)
    scene:addChild(UIRushPass.new(scene:getTouchPriority()))
    -- scene:addChild(UIGetItem.new(scene:getTouchPriority(), json.decode([==[
    -- [[17010009,2],[17010014,1],[17010010,1],[17010026,1],[17010023,1],[17010030,1],[17020032,1]]

    -- ]==])))
end
