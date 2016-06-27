require "script/CCBReaderLoad"
require "script/Protocol"
require "script/json"

require "script/RoutesManager"

local LuaUIGeneral      = createCCBClase("LuaUIGeneral")
local container         = nil
local scrollView        = nil
local curIndex          = 1
local OWNED_LAYER_TAG   = 1000
local UNOWNED_LAYER_TAG = 2000
ownedSoldiers     = nil
unOwnedSoldiers   = nil
local curPage           = nil
local validDisantce     = 10
curSelectGeneral = nil

function onGeneralUIMsg( msgId ,_json)
	local data = json.decode(_json)
	if msgId == Protocol.SC_NotifyRoleAttrChange then
		dump("武将列表刷新")
		curPage:refreshTableView()
	elseif msgId == Protocol.SC_RecBySou then
		_clearWaiting()
		if data.rtn == 0 then
			if curPage.recruritWaitingFlag then
				curPage.recruritWaitingFlag = false
			else
				curPage:refreshTableView()
			end
		else
			_openWarning("遇到错误" .. data.rtn)
		end
	elseif msgId == ClienNotifyProtocol.NEW_RESPAWN_SOLDIER then
		-- local soldierItem = getSoldierListItem(data.id)
		-- if soldierItem then
		-- 	soldierItem:showNotifyIcon()
		-- end
		curPage:refreshTableView()
	elseif msgId == ClienNotifyProtocol.NO_RESPAWN_SOLDIER then
		curPage:refreshTableView()
	elseif msgId == ClienNotifyProtocol.NEW_RECURIT_SOLDIER then
		curPage:refreshTableView()
	elseif msgId == ClienNotifyProtocol.NO_RECURIT_SOLDIER then
		-- curPage:refreshTableView(	)
	end
end

function getSoldierListItem( id )
	local container = scrollView:getContainer()
	local children = container:getChildren()
	for i=0,children:count() - 1 do
		local child = children:objectAtIndex(i)
		if child.soldier and tonumber(child.soldier.id) == id then
			return child
		end
	end
end

function mapAllSoldierListItem(fun)
	local container = scrollView:getContainer()
	local children = container:getChildren()
	for i=0,children:count() - 1 do
		local child = children:objectAtIndex(i)
		if child and child.soldier then
			fun(child)
		end
	end
end

function LuaUIGeneral:registerProxy()
	if self.eventProxy then
		 self.eventProxy:addMsgListener( Protocol.SC_GetRole, "onGeneralUIMsg")
		 self.eventProxy:addMsgListener( Protocol.SC_RecBySou, "onGeneralUIMsg")
		 self.eventProxy:addMsgListener( Protocol.SC_NotifyRoleAttrChange, "onGeneralUIMsg")
		 self.eventProxy:addMsgListener( ClienNotifyProtocol.NEW_RESPAWN_SOLDIER, "onGeneralUIMsg")
		 self.eventProxy:addMsgListener( ClienNotifyProtocol.NO_RESPAWN_SOLDIER, "onGeneralUIMsg")
		 self.eventProxy:addMsgListener( ClienNotifyProtocol.NO_RECURIT_SOLDIER, "onGeneralUIMsg")
		 self.eventProxy:addMsgListener( ClienNotifyProtocol.NEW_RECURIT_SOLDIER, "onGeneralUIMsg")
	end
end

function LuaUIGeneral:onExitTransitionDidStart()
	self:unregisterProxy()
	ownedSoldiers = nil
	unOwnedSoldiers = nil
	curSelectGeneral = nil
end

function LuaUIGeneral:refreshSoldierData()
	unOwnedSoldiers = {}
	ownedSoldiers = {}
	local totalSoldiers = nil
	if curIndex == 1 then
		totalSoldiers = LuaSoldierManager.allSoldiers()
	else
		totalSoldiers = LuaSoldierManager.findSoldierDataByType(curIndex-1)
	end
	for i,v in ipairs(totalSoldiers) do
		if v.m_bown then
			table.insert(ownedSoldiers, v)
		else
			table.insert(unOwnedSoldiers, v)
		end
	end

	-- @10/16 ZLu 上阵的状态仅显示征战的阵型
	ownedSoldiers = LuaSoldierManager.sortSoldierListByLoaded(ownedSoldiers, {FormationUseType.Monster})
	table.sort(unOwnedSoldiers, function(one, two)
		local countOne = LuaSoldierManager.getSoulItemCountForRecurit(one)
		local countTwo = LuaSoldierManager.getSoulItemCountForRecurit(two)
		if countOne ~= countTwo then
			return countOne > countTwo
		else
			return tonumber(one.id) > tonumber(two.id)
		end
	end)
	self.cb_lblGeneralNum:setString("" .. #ownedSoldiers .. "/" .. #totalSoldiers)
end

function LuaUIGeneral:createTableView()
	self:refreshSoldierData()
	local cellHeight   = 67 + 5
	local cellWidth    = 139
	local width        = container:getContentSize().width
	local height       = container:getContentSize().height
	local cellHPadding = (width - 3*cellWidth) / 2 - 3
	local vPaddingAddon = 5
	local cellVPadding = 6
	local column       = 3
	local labelHeight  = cellVPadding + vPaddingAddon
	local function cellSizeForIndex(table, idx)
		local count = math.ceil(#ownedSoldiers / column)
		if idx < count then
			return cellHeight, width
		end
		if #unOwnedSoldiers > 0 then
			if idx == count then
				return labelHeight, width
			else
				return cellHeight + cellVPadding, width
			end
		end
	end

	local function numberOfCell( table )
		local count = math.ceil(#ownedSoldiers / column)
		if #unOwnedSoldiers > 0 then
			count = count + 1 + math.ceil(#unOwnedSoldiers / column)
		end
		return count
	end

	local function cellForIndex( table, idx )
		local number = numberOfCell(table)
		local count = math.ceil(#ownedSoldiers / column)
		local height, width = cellSizeForIndex(table, idx)
		local cell = table:dequeueCell()
		if nil == cell then
			 cell = CCTableViewCell:new()
		end
		-- test
		-- local cell = CCLayer:create()

		if idx < count then
			-- 已经招募的武将
			for i=1,3 do
				local soldierData = ownedSoldiers[idx * 3 + i]
				local soldierLayer = tolua.cast(cell:getChildByTag(1000 + i), "CCLayer")

				-- 如果没有初始化这个layer
				if soldierLayer == nil then
					if soldierData then
						-- 如果有该位置的武将 再初始化
			        	soldierLayer = require("script/LuaGeneralListItem").create(soldierData)
						soldierLayer:setTag(1000 + i)
						soldierLayer.touchTag = OWNED_LAYER_TAG + idx * 3 + i
						self:registeTouchEventToLayer(soldierLayer)
						cell:addChild(soldierLayer)
						soldierLayer:setPosition(ccp((cellWidth + cellHPadding) * (i-1), 0))
						if tonumber(soldierData.id) == 12000047 then
							soldierLayer:setTutorialStepId(36010401)
						elseif tonumber(soldierData.id) == 12000048 then
							soldierLayer:setTutorialStepId(36010101)
						end
					end
				else
					if soldierData then
						soldierLayer.soldier = soldierData
						soldierLayer:updateUI()
						soldierLayer.touchTag = OWNED_LAYER_TAG + idx * 3 + i
						soldierLayer:setVisible(true)
						soldierLayer:setTouchEnabled(true)
						if soldierLayer.oriScale then
							soldierLayer:setScale(soldierLayer.oriScale)
						end
					else
						soldierLayer:setVisible(false)
						soldierLayer:setTouchEnabled(false)
					end
				end
			end
			local titleSprite = tolua.cast(cell:getChildByTag(2000), "CCSprite")
			if titleSprite then
				titleSprite:setVisible(false)
			end
	    elseif idx == count then
	    	-- 显示中间的label
	    	for i=1,3 do
				local soldierLayer = tolua.cast(cell:getChildByTag(1000 + i), "CCLayer")
				if soldierLayer then
					soldierLayer:setVisible(false)
				end
	    	end


			local titleSprite = tolua.cast(cell:getChildByTag(2000), "CCSprite")
			if not titleSprite then
				titleSprite = CCSprite:createWithSpriteFrameName("wjzhaomujinduwz.png")
				cell:addChild(titleSprite)
				titleSprite:setTag(2000)
				titleSprite:setPosition(ccp(width/2, height/2))
			else
				titleSprite:setVisible(true)
			end
	    else
	    	-- 显示未招募的武将
			for i=1,3 do
				local soldierData = unOwnedSoldiers[(idx - count - 1) * 3 + i]
				local soldierLayer = tolua.cast(cell:getChildByTag(1000 + i), "CCLayer")

				-- 如果没有初始化这个layer
				if soldierLayer == nil then
					if soldierData then
						-- 如果有该位置的武将 再初始化
			        	soldierLayer = require("script/LuaGeneralListItem").create(soldierData)
						soldierLayer:setTag(1000 + i)
						soldierLayer.touchTag = UNOWNED_LAYER_TAG + (idx - count - 1) * 3 + i
						self:registeTouchEventToLayer(soldierLayer)
						cell:addChild(soldierLayer)
						soldierLayer:setPosition(ccp((cellWidth + cellHPadding) * (i-1), 0))
					end
				else
					if soldierData then
						soldierLayer.soldier = soldierData
						soldierLayer:updateUI()
						soldierLayer.touchTag = UNOWNED_LAYER_TAG + (idx - count - 1) * 3 + i
						soldierLayer:setVisible(true)
						-- if LuaSoldierManager.canBeRecurit( soldierData ) then
							-- soldierLayer:setTouchEnabled(true)
						-- else
						-- 	soldierLayer:setTouchEnabled(false)
						-- end
						if soldierLayer.oriScale then
							soldierLayer:setScale(soldierLayer.oriScale)
						end
					else
						soldierLayer:setVisible(false)
						-- soldierLayer:setTouchEnabled(false)
					end
				end
			end
			local titleSprite = tolua.cast(cell:getChildByTag(2000), "CCSprite")
			if titleSprite then
				titleSprite:setVisible(false)
			end
	    end

		return cell
	end

	-- 添加tableView
	local tableView = CCTableView:create(container:getContentSize())
	tableView:setDirection(kCCScrollViewDirectionVertical)

	tableView:setVerticalFillOrder(kCCTableViewFillTopDown)
	container:addChild(tableView)
	tableView:setPosition(ccp(0,0))
	tableView:setTouchPriority(self:getTouchPriority() - 1)
	tableView:setTouchEnabled(true)

	tableView:registerScriptHandler(cellSizeForIndex, 6)
	tableView:registerScriptHandler(cellForIndex, 7)
	tableView:registerScriptHandler(numberOfCell, 8)
	-- -- tableView:registerScriptHandler(tableCellTouched, cc.TABLECELL_TOUCHED)
	-- -- tableView:registerScriptHandler(tableCellHeighlight, cc.TABLECELL_HIGH_LIGHT)
	-- -- tableView:registerScriptHandler(tableCellUnheighlight, cc.NUMBER_OF_CELLS_IN_TABLEVIEW)

	tableView:reloadData()
	self.tableView = tableView
end

function LuaUIGeneral:refreshTableView()
	self:refreshSoldierData()
	self.tableView:reloadData()
end

-- 给武将的itemlayer 注册监听事件
function LuaUIGeneral:registeTouchEventToLayer( layer )
	local function onTouch( eventType, x, y )
		return self:generalTouchEvent(eventType, x, y, layer)
	end

	layer:registerScriptTouchHandler(onTouch, false, self:getTouchPriority()-2, false)
	layer:setTouchMode(kCCTouchesOneByOne)
end

-- 武将cell的点击事件分发方法
function LuaUIGeneral:generalTouchEvent( eventType, x, y, layer )
	if not layer:isVisible() then
		return false
	end
	local pos = ccp(x, y)
	pos = layer:convertToNodeSpace(pos)
	local contain = (pos.x > 0 and pos.x < layer:getContentSize().width) and ( pos.y > 0 and pos.y < layer:getContentSize().height)


	if contain then
		if eventType == "began" then
			layer.moved = false
			layer:playBiggerAnimation()
			self._curTouchPosX = x
			self._curTouchPosY = y
		elseif eventType == "moved" then
			if math.sqrt((self._curTouchPosX - x) * (self._curTouchPosX - x)
				+ (self._curTouchPosY - y) * (self._curTouchPosY - y)) > validDisantce then
				layer.moved = true
				layer:playSmallerAnimation()
			end
		elseif eventType == "ended" then
			layer:playSmallerAnimation()
			if not layer.moved then
				local tag = layer.touchTag
				if tag > UNOWNED_LAYER_TAG then
					-- TODO: debug 邰健聪
					local index = tag - UNOWNED_LAYER_TAG
						local _tmp = unOwnedSoldiers[index]
					if LuaSoldierManager.canBeRecurit( _tmp ) then
						self:recuritSoldier(_tmp, layer)
					else
						UIManager:getSingleton():openLuaPageWithArgs("script/LuaUIGeneralView.lua",
						"LuaUIGeneralViewOpen",
						"LuaUIGeneralView",
						json.encode({index=index}))
					end
					-- 判断是否已经能能招募
					-- UIManager:getSingleton():openLuaPage("script/LuaUIGeneralInfo.lua",
					-- 	"UIGeneralInfoOpen",
					-- 	"UIGeneralInfo")
					-- layer.moved = false
					-- print(index)
					-- RoutesManager.openPageFromTask(index)
				else
					curSelectGeneral = ownedSoldiers[tag - OWNED_LAYER_TAG]
					UIManager:getSingleton():openLuaPageWithArgs("script/LuaUIGeneralInfo.lua",
						"UIGeneralInfoOpen",
						"UIGeneralInfo",
						json.encode({id=curSelectGeneral.id}))
					layer.moved = false
				end
			end
		end
		return true
	else
		layer.moved = false
		return false
	end
end

--binding ccb variables
function LuaUIGeneral:assignCCBMemberVariables()
	container = tolua.cast(self.cb_nodeContainer, "CCLayer")
end

function LuaUIGeneral:recuritSoldier( soldier, layer )
	SoundMgr:getSingleton():playLuaEff("hero.mp3", false);
	self:playRecuritEffect(layer)
	_sendRequest(Protocol.CS_RecBySou, {id = tonumber(soldier.id)})
	-- 招募会播放一个动画，而收到招募成功的消息可能有延迟，增加【recruritWaitingFlag】来处理相应逻辑
	self.recruritWaitingFlag = true
end

function LuaUIGeneral:playRecuritEffect(layer)
	self.tableView:setTouchEnabled(false)
	local effect = CCSprite:create()
	local animation = create_animation("effect32_.plist", "effect32_", 0.1, 1, 13, 1)
	print(animation:getDuration(), "招募特效 时长")
	layer.avatar:addChild(effect)
	effect:setZOrder(100)
	local size = layer.avatar:getContentSize()
	effect:setPosition(ccp(size.width/2, size.height/2))
	effect:setScale(1.5)
	layer:removeRecruitEffect()
	local callback = function()
		layer.avatar:removeChild(effect, true)
		self.tableView:setTouchEnabled(true)
		if self.recruritWaitingFlag then
			UIManager:getSingleton():ShowWaiting()
			self.recruritWaitingFlag = false
		else
			self:refreshTableView()
		end
	end
	effect:runAction(CCSequence:createWithTwoActions(animation, CCCallFunc:create(callback)))
end


function LuaUIGeneral:init()
	UIManager:getSingleton():ShowWaiting()
	self:assignCCBMemberVariables()
	-- self:createScrollView()
	--self:fillUIElements()
	-- self:registerProxy()
	self:updateUI()
	self["segment_1"]:selected()
	
	LuaSoldierManager.loadCplusData()
	UIManager:getSingleton():ClearWaiting()
	self:createTableView()

	self:setTouched()
end


function LuaUIGeneral.onSegmentBtnClicked( sender )
    SoundMgr:getSingleton():playNormalBtnSound()
	curIndex = sender
	for i=1,4 do
		local btn = curPage["segment_" .. i]
		if curIndex == i then
			btn:selected()
		else
			btn:unselected()
		end
	end
	curPage:refreshTableView()
end


function LuaUIGeneral:updateUI()
end

local function countDownTimer( )
end

--touch
function LuaUIGeneral:onTouchBegan( x, y )
	return true
	--return false
end

function LuaUIGeneral:onTouchMoved( x, y )

end

function LuaUIGeneral:onTouchEnded( x, y )

end

function LuaUIGeneral:setTouched()
	local function onTouch( eventType, x, y )
		if eventType == "began" then
			return self:onTouchBegan(x, y)

		elseif eventType == "moved" then
			return self:onTouchMoved( x, y )

		elseif eventType == "ended" then
			return self:onTouchEnded( x, y )
		else
		end
	end

	self:registerScriptTouchHandler(onTouch, false, self:getTouchPriority(), true)
	self:setTouchEnabled(true)
	self:setTouchMode(kCCTouchesOneByOne)

end

function LuaUIGeneral:initTutorialData()
	TutorialManager:getSingleton():gotoNextStep()
end

function LuaUIGeneral:openSubPage( pageType, soldierId )
	if not pageType then return end
	if not soldierId then return end

	local isNotFound = true
	for i,v in ipairs(ownedSoldiers) do
		if tonumber(v.id) == soldierId then 
			curSelectGeneral = v
			isNotFound = false
		end
	end

	if isNotFound then return end

	if pageType == GeneralUISubPageType.Info then
		UIManager:getSingleton():openLuaPage("script/LuaUIGeneralInfo.lua", "UIGeneralInfoOpen", "UIGeneralInfo")
	elseif pageType == GeneralUISubPageType.Upgrade then
		UIManager:getSingleton():openLuaPage("script/LuaUIGeneralUpgrade.lua", "UIGeneralUpgradeOpen", "UIGeneralUpgrade")
	elseif pageType == GeneralUISubPageType.Respawn then
		UIManager:getSingleton():openLuaPage("script/LuaUIGeneralRespawn.lua", "UIGeneralRespawnOpen", "UIGeneralRespawn")
	end
end


function UIGeneralOpen( scene, jsonStr )
	local node =CCBuilderReaderLoad("UIGeneral.ccbi", CCBProxy:create(), "LuaUIGeneral")
	node = LuaUIGeneral.extend(tolua.cast(node, "CCLayer"))
	if node then
		node:setTouchPriority(scene:getTouchPriority())
		node:init()
	end
	curPage = node

	node:registeNodeEvent()

	scene:addChild(node)

	node:initTutorialData()
	for i=1,4 do
		local tmp = tolua.cast(node["segment_" .. i]:getParent(), "CCMenu")
		tmp:setTouchPriority(node:getTouchPriority()-3)
	end

	if jsonStr and jsonStr ~= "" then
		local function openGeneralSubPage( ... )
			local openInfo = json.decode(jsonStr)
			node:openSubPage(openInfo.pageType, openInfo.id)
			-- local soldierId = openInfo.id
			-- node:openSubPage( 2, 12000047)
		end
		node:runAction(CCSequence:createWithTwoActions(CCDelayTime:create(0.01), CCCallFunc:create(openGeneralSubPage)))
	end
end

