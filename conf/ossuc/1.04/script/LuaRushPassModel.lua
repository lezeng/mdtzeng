LuaRushPassModel = class("LuaRushPassModel")

function LuaRushPassModel:ctor()
	self.msgProxy = LuaMsgProxy()

	self.msgProxy:addMsgListener(Protocol.SC_NewBEAT_CurLayer, handler(self, self.scCurLayer))
    self.msgProxy:addMsgListener(Protocol.SC_NewBEAT_Rank, handler(self, self.scRank))
    -- self.msgProxy:addMsgListener(Protocol.SC_NotifyDrop, handler(self.scDrop))
    -- self.msgProxy:addMsgListener(Protocol.SC_BuyResetCount, handler(self, self.scReset))
    self.msgProxy:addMsgListener(Protocol.SC_NewBEAT_NotifyOver, handler(self, self.scOver))
    self.msgProxy:addMsgListener(Protocol.SC_NewBEAT_NotifyFaild, handler(self, self.scOver))

    self.inited = false

    self.curLayer = 0
    self.curLayerData = {}
    self.curAddition = {}
    self.curExploit = 0
    self.rankData = {}
    self.lastLayer = 0

    self.StartBtnClicked = false
    self.FightOver = false
end

function LuaRushPassModel:setStartBtnClicked(val)
    self.StartBtnClicked = val
end

function LuaRushPassModel:checkStartBtnClicked()
    return self.StartBtnClicked
end

------------------
-- Hx@2015-09-16 : 通过init来判断是否第一次获取数据
-- 未获取过，请求数据，设置界面，播放初始动画
-- 获取过，设置界面，请求数据，再次设置界面，播放数据过渡动画
function LuaRushPassModel:checkInited()
	return self.inited
end

function LuaRushPassModel:setInited()
	self.inited = true
end

-- Hx@2015-09-16 : 因为服务器是单线程有序的，所以使用最后一条发出的请求的回答作为触发更新的节点
-- 需要自己注意消息顺序，还有服务器通知类消息处理
function LuaRushPassModel:update()
    self:csCurLayer()
    self:csRank()
end

------------------
function LuaRushPassModel:csCurLayer()
    local tMsg = {}
    tMsg[ProtocolStr_Request] = Protocol.CS_NewBEAT_CurLayer
    sendRequest(tMsg)
end

function LuaRushPassModel:scCurLayer(msgId, strMessage)
    local tbMessage = json.decode(strMessage)
    -- if tbMessage[ProtocolStr_Rtn] ~= ErrorCode.OK then
    -- 	showLuaErr(ErrorCode.ERROR, "code:%s", tbMessage[ProtocolStr_Rtn])
    -- 	return
    -- end

    self.curLayer = tbMessage[ProtocolStr_Flag]
    self.curLayerData = tbMessage[ProtocolStr_Info]
    self.curExploit = tbMessage[ProtocolStr_Type]
    self.curAddition = tbMessage[ProtocolStr_Attr]
    self.lastLayer = tbMessage[ProtocolStr_Number]
end

function LuaRushPassModel:getCurLayer()
	return self.curLayer
end

function LuaRushPassModel:getCurLayerData()
	return self.curLayerData
end

function LuaRushPassModel:getCurAddition()
	return self.curAddition
end

function LuaRushPassModel:getCurExploit()
    return self.curExploit
end

------------------
function LuaRushPassModel:csRank()
    local tMsg = {}
    tMsg[ProtocolStr_Request] = Protocol.CS_NewBEAT_Rank
    sendRequest(tMsg, true)
end

function LuaRushPassModel:scRank(msgId, strMessage)
    local tbMessage = json.decode(strMessage)
    -- if tbMessage[ProtocolStr_Rtn] ~= ErrorCode.OK then
    --     showLuaErr(ErrorCode.ERROR, "code:%s", tbMessage[ProtocolStr_Rtn])
    --     return
    -- end

    self.rankData = tbMessage[ProtocolStr_Info]

    self:setInited()
end

function LuaRushPassModel:scOver()
    LuaCountManager.addCount(CountType.NewBEAT)
    self.FightOver = true
end

function LuaRushPassModel:getLayerRank()
	return self.rankData[NewBEAT_Rank.Layer]
end

function LuaRushPassModel:getExploitRank()
	return self.rankData[NewBEAT_Rank.Exploits]
end

function LuaRushPassModel:getMyMaxExploit()
	return self.rankData[NewBEAT_Rank.MyExploits]
end

function LuaRushPassModel:getMyMaxLayer()
	return self.rankData[NewBEAT_Rank.MyLayer]
end

function LuaRushPassModel:getLayerRankPosition()
	return self.rankData[NewBEAT_Rank.MyLayerRank]
end

function LuaRushPassModel:getExploitRankPosition()
	return self.rankData[NewBEAT_Rank.MyExploitsRank]
end

function LuaRushPassModel:checkFightOver()
    return self.FightOver
end

function LuaRushPassModel:resetFightOver(val)
    self.FightOver = false
end

function LuaRushPassModel:getLastLayer()
    return self.lastLayer or 0
end

function LuaRushPassModel:isShowFightNotify( ... )
    -- @11/16 ZLu 闯关战斗开始时，并没有立即扣除战斗次数，而是等到战斗结束时才减少的数据
    -- 所以这里首先判定一次是否在战斗中，如果是的话，则不显示战斗提示
    if self.curExploit > 0 or not self.FightOver then return false end
    return LuaCountManager.getReset(CountType.NewBEAT) - LuaCountManager.getCount(CountType.NewBEAT) >= 0
end

------------------
-- function LuaRushPassModel:scDrop(msgId, strMessage)
--     local tbMessage = json.decode(strMessage)
--     self.dropInfo = tbMessage[ProtocolStr_Info]

-- end
-- function LuaRushPassModel:csReset()
--     local tMsg = {}
--     tMsg[ProtocolStr_Request] = Protocol.CS_BuyResetCount
--     tMsg[ProtocolStr_Type] = ResetCostType.NewBEAT
--     sendRequest(tMsg)
-- end

-- function LuaRushPassModel:scReset(msgId, strMessage)
--     local tbMessage = json.decode(strMessage)
--    	if tbMessage[ProtocolStr_Rtn] ~= ErrorCode.OK then
--         _openWarning("scRank failed")
--         return
--     end
--     dump(tbMessage)
-- end

-- function LuaRushPassModel:scOver(msgId, strMessage)
--     local tbMessage = json.decode(strMessage)
--     dump(tbMessage)
-- end

-- function LuaRushPassModel:scFail(msgId, strMessage)
--     local tbMessage = json.decode(strMessage)
--     dump(tbMessage)
-- end

