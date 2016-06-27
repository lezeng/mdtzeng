--
-- Author: JasonTai(taijcjc@gmail.com)
-- Date: 2015-01-20 11:41:23
--
require "script/CCBReaderLoad"
require "script/Protocol"
require "script/json"
require "script/resBattle/LuaResBattleMineInfo"

local scheduler        = require("script/scheduler")

local LuaUIForm        = createCCBClase("LuaUIForm")
local curPage          = nil
local padding          = 8
local width            = 60
local tmpScale = 0.858
local startY = 0
local startX = 11
local startXPadding = 8
local yPadding = 2
local validDragTime    = 0.1
local validDragDistance = 20

local curTouchState    = FORM_TOUCH_STATE.NO_STATE

--@2015/01/24, ZLu : 现存两种添加页面的模式，关闭时需要加以区分
--为【true】时，调用常规的移除方式，使用UIManager。removeTopLayer
local closeCheckFlag = false
--默认为编辑“推图”阵型，即普通阵型
gCurFormType = FormationUseType.Monster

function LuaUIForm.create(formationDelegate, touchPriority)
	local  proxy = CCBProxy:create()
	local node =CCBuilderReaderLoad("LuaUIForm.ccbi", proxy, "LuaUIForm")
	node = tolua.cast(node, "CCLayer");
	LuaUIForm.extend(node)
	node.delegate = formationDelegate
	node.validCount = LuaFormationManager.curValidPosCount()

	curPage = node
	curPage._curTag = formationDelegate._curInfo.fomrmationInfo.index
	if node ~= nil then
		node:setTouchPriority(touchPriority)
		node:init()
	end

	node:registeNodeEvent()
	return node
end

function onUIFormMsg( msgId ,_json)
	local data = json.decode(_json)
	print("reverive msg " .. msgId)
	if msgId == Protocol.SC_SendFormation then
		_clearWaiting()
		curPage:refreshFormPos()
	elseif msgId == Protocol.SC_SaveFormation then
		_clearWaiting()
		if data.rtn == 0 then
			curPage.delegate:saveFormationInfoToLocal()
			curPage:updateUI()
		else
			_openWarning("保存阵型失败")
		end
	end
end

function LuaUIForm:registerProxy()
	if self.eventProxy ~= nil then
		print("注册武将升级事件 ")
		 -- self.eventProxy:addMsgListener( Protocol.SC_SendFormation, "onUIFormMsg")
		 self.eventProxy:addMsgListener( Protocol.SC_SaveFormation, "onUIFormMsg")
	end
end

function LuaUIForm:updateUI()
	self.soldierArray = self.delegate:soldierList()
	local curOffset = self.tableView:getContentOffset()
	self.tableView:reloadData()
	self.tableView:setContentOffset(curOffset)
	self.formLayer:updateUI()
	self:updateFormMapBtn()
	-- if self.isResFormation and LuaResBattleManager.isLoadedFormation(self.delegate.flag) then
	-- 	self.formLayer:setAllFormTouchEnable(false)
	-- else
	-- 	self.formLayer:setAllFormTouchEnable(true)
	-- end
	self:refreshFormState()
	self:checkHasAvaliableSoldier()
end

function LuaUIForm:setTouched()
	local function onTouch( eventType, x, y )
		self.curX = x
		self.curY = y
		if eventType == "ended" then
			if curTouchState == FORM_TOUCH_STATE.DRAG_LOAD_SOLDIER then
				local pos = ccp(x,y)
				pos = self.unloadLayer:convertToNodeSpace(pos)
				if self.tableView:boundingBox():containsPoint(pos) then
					self:unloadSoldier()
				end
			end
			self:cancelTouchEvent()
		elseif eventType == "moved" then
			if curTouchState == FORM_TOUCH_STATE.DRAG_LOAD_SOLDIER
				or curTouchState == FORM_TOUCH_STATE.DRAG_UNLOAD_SOLDIER then
				if self.dragAvatar then
					self.dragAvatar:setPosition(ccp(x, y))
				end
			end
		end
        return true
	end

	self:registerScriptTouchHandler(onTouch, false, self:getTouchPriority(), true)
	self:setTouchEnabled(true)
	self:setTouchMode(kCCTouchesOneByOne)
end

function LuaUIForm:closeCurPage()
	if closeCheckFlag then
		UIManager:getSingleton():removeTopLayer()
	else
		local parent = curPage:getParent()
		parent:removeChild(curPage, true)
		curPage = nil
	end
end

-- --------------------------------------------
--			点击事件注册分发方法
-- --------------------------------------------

-- 给为上阵的layer注册点击事件
function LuaUIForm:registeUnloadTouchEvent(layer)
	local function onTouch( eventType, x, y )
		return self:generalUnloadTouchEvent(eventType, x, y, layer)
	end

	layer:registerScriptTouchHandler(onTouch, false, self:getTouchPriority()-2, false)
	layer:setTouchEnabled(true)
	layer:setTouchMode(kCCTouchesOneByOne)
end

-- 为未上真的layer分发点击事件
function LuaUIForm:generalUnloadTouchEvent( eventType, x, y, layer )
	local pos = ccp(x, y)
	pos = layer:convertToNodeSpace(pos)
	local contain = (pos.x > 0 and pos.x < layer:getContentSize().width) and ( pos.y > 0 and pos.y < layer:getContentSize().height)

	if contain then
		if eventType == "began" then
			layer.moved = false
			self:beginTouchUnloadLayer(layer)
			self.oriX = x
			self.oriY = y
		elseif eventType == "moved" then
			if self.curSelecteLayer == layer
				and curTouchState == FORM_TOUCH_STATE.TOUCHED_UNLOAD_SOLDIER
				and ccpDistance(ccp(x, y), ccp(self.oriX, self.oriY)) > validDragDistance then
				print("moved:",x,y,":",self.oriX,self.oriY,":"..validDragDistance)
				layer.moved = true
				self:cancelTouchEvent()
			end
		elseif eventType == "ended" then
			layer.moved = false
		end
		return true
	else
		return false
	end
end

-- 给已经上阵的武将注册事件
function LuaUIForm:registeLoadedTouchEvent( layer )
	local function onTouch( eventType, x, y )
		return self:generalLoadedTouchEvent(eventType, x, y, layer)
	end

	layer:registerScriptTouchHandler(onTouch, false, self:getTouchPriority()-2, false)
	layer:setTouchEnabled(true)
	layer:setTouchMode(kCCTouchesOneByOne)
end

-- 给右侧的阵型位置分发事件
function LuaUIForm:generalLoadedTouchEvent( eventType, x, y, layer )
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

-- --------------------------------------------
--			状态变更方法
-- --------------------------------------------

-- 开始点击已上阵的武将
function LuaUIForm:beginTouchLoadedLayer( layer )
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

-- 开始点击未上阵的武将
function LuaUIForm:beginTouchUnloadLayer( layer )
	if curTouchState == FORM_TOUCH_STATE.NO_STATE and
	not layer.soldierData._loaded then
		print("点击未上阵武将" .. layer:getTag() .. " " .. layer.soldierData.name)
		self.touchHandler = scheduler.scheduleUpdateGlobal(handler(self, self.update))
		self.touchTimer = 0
		self.curSelecteLayer = layer
		curTouchState = FORM_TOUCH_STATE.TOUCHED_UNLOAD_SOLDIER
	 	TutorialManager:getSingleton():showDragTips()
	end
end

-- 开始拖拽已上真的武将
-- 并且不在计时
function LuaUIForm:beginDragLoadedLayer( layer )
	if curTouchState == FORM_TOUCH_STATE.TOUCHED_LOAD_SOLDIER then
		curTouchState = FORM_TOUCH_STATE.DRAG_LOAD_SOLDIER
		print("开始拖拽")
		self.tableView:setTouchEnabled(false)
		self:beginDragSoldierAvatar()
	else
		self:cancelTouchEvent()
	end
	if self.touchHandler then
		scheduler.unscheduleGlobal(self.touchHandler)
		self.touchHandler = nil
	end
end

-- 开始拖拽未上阵的武将
-- 并且不在计时
function LuaUIForm:beginDragUnloadLayer( layer )
	if curTouchState == FORM_TOUCH_STATE.TOUCHED_UNLOAD_SOLDIER then
		curTouchState = FORM_TOUCH_STATE.DRAG_UNLOAD_SOLDIER
		print("开始拖拽")
		self.tableView:setTouchEnabled(false)
	 	TutorialManager:getSingleton():playDragAnimation()
		self:beginDragSoldierAvatar()
	else
		self:cancelTouchEvent()
	end
	if self.touchHandler then
		scheduler.unscheduleGlobal(self.touchHandler)
		self.touchHandler = nil
	end
end

-- 结束拖拽并且接受事件
function LuaUIForm:endDragLoadedLayer( layer )
	 if curTouchState == FORM_TOUCH_STATE.DRAG_LOAD_SOLDIER then
	 	-- 如果之前是拖拽的已上阵武将
	 	print("如果之前是拖拽的已上阵武将")
	 	self:replaceSoldier(layer)
	 elseif curTouchState == FORM_TOUCH_STATE.DRAG_UNLOAD_SOLDIER then
	 	-- 如果之前拖拽的未上阵武将
	 	print("如果之前拖拽的未上阵武将")

	 	-- JasonTai
	 	-- 添加新手引导
	 	if TutorialManager:getSingleton():isPlayingTutorial()
	 		and TutorialManager:getSingleton():curStepEndPosId() > 0 then
	 		if TutorialManager:getSingleton():curStepEndPosId() == layer:getTutorialStepId() then
		 		self:loadSoldierToForm(layer)
	 			TutorialManager:getSingleton():gotoNextStep()
	 		end
	 	else
	 		self:loadSoldierToForm(layer)
	 	end
	 else
	 end
	 self:cancelTouchEvent()
end

-- 取消当前的点击状态
function LuaUIForm:cancelTouchEvent()
	print("取消武将操作")
	 TutorialManager:getSingleton():endDragAnimation()
	curTouchState = FORM_TOUCH_STATE.NO_STATE
	if not TutorialManager:getSingleton():isPlayingTutorial() then
		self.tableView:setTouchEnabled(true)
	end
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

-- 开始拖拽武将头像
function LuaUIForm:beginDragSoldierAvatar()
	self.dragAvatar = require("script/formation/LuaFormListItem.lua").create(self.curSelecteLayer.soldierData)
	self.dragAvatar:displayAsDragShadow()
	self:addChild(self.dragAvatar)
	self.dragAvatar:setZOrder(100)
	self.dragAvatar:setPosition(ccp(self.curX, self.curY))
end

function LuaUIForm:update( dt )
	self.touchTimer = self.touchTimer + dt

	if self.touchTimer > validDragTime then
		-- 如果时间到了 拖拽时间 并且当前状态一直是没有动的 就进入拖拽状态
		if curTouchState == FORM_TOUCH_STATE.TOUCHED_LOAD_SOLDIER then
			print("update点击已上阵武将");
			self:beginDragLoadedLayer(self.curSelecteLayer)
		elseif curTouchState == FORM_TOUCH_STATE.TOUCHED_UNLOAD_SOLDIER then
			print("update点击未上阵武将");
			self:beginDragUnloadLayer(self.curSelecteLayer)
		end
	end
end

-- 显示入场的位置动画
function LuaUIForm:showEnterAnimation()
	local info = self.delegate:curFormationInfo()
	if info and info.fomrmationInfo then
		for i=1,9 do
			if info.fomrmationInfo.status[i] then
				self.formLayer["form_" .. i]:showEnterAnimation()
			end
		end
	end
end


-- --------------------------------------------
--			页面刷新方法
-- --------------------------------------------

--王鹏宇修改
--解析读取的memo
function LuaUIForm:parseBuff(tempTable)
	local buffArray = {} --用于存储buff
	 for k,v in pairs(tempTable) do
	 --判断是否为两个buff效果
        local isDouble = self:subStr(v)
        if isDouble then
            local imgArray = string.split(v,";")
            for k,v in pairs(imgArray) do
            	table.insert(buffArray,v)
            end
        else
            table.insert(buffArray,v)
        end
    end
    return buffArray
end
--王鹏宇修改
--判断这个memo是否存在“；”号
function LuaUIForm:subStr(str)
   for i=1,#str do
       chars = string.sub(str,i,i)
       if chars == ";" then
            return true
       end
   end
   return false
end

function LuaUIForm:showFlagSegment()
	self.segmentBtns:setVisible(true)
end


-- --------------------------------------------
--			数据操作方法
-- --------------------------------------------

-- 上阵
function LuaUIForm:loadSoldierToForm( layer )
 	if layer.soldierData then
 		-- 如果当前位置是有武将的 就把该位置的武将替换下去
 		print("上阵 xxx  下阵 xxx")
 		-- @07/01 张露 从左侧拖入武将放入右侧，右侧位置已被占用，直接调用【addSoldierToPos】，该方法直接设置了对应数据
 		-- 等同于调用了【unloadSoldier】清空再设置新武将
 		-- 【unloadSoldier】的处理会保存一次阵型，这时阵型可能是空的，阵型中必须有一个武将！见BUG【1587】
 		-- self.delegate:unloadSoldier(layer:getTag())
 		self.delegate:addSoldierToPos(self.curSelecteLayer.soldierData.id, layer:getTag())
 	else
 		-- 如果当前位置没有武将的 就把武将移到这个位置
 		print("上阵 xxxx")
 		if self.delegate:loadedCount() < self.validCount then
	 		self.delegate:addSoldierToPos(self.curSelecteLayer.soldierData.id, layer:getTag())
	 	else
	 		print("达到上阵个数上限")
	 	end
 	end
 	-- TODO 在layer上面播放特效
 	layer:showEnterAnimation()
 	self:updateUI()
end

function LuaUIForm:replaceSoldier( layer )
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
 	layer:showEnterAnimation()
end

-- 下阵
function LuaUIForm:unloadSoldier()
	print("下阵")
	local minCount = 1
	-- @11/18 ZLu 资源战可以全部下阵
	if gCurFormType >= FormationUseType.Resource1 and gCurFormType <= FormationUseType.Resource5 then
		minCount = 0
	end
	-- @07/01 ZLu 阵型上至少需要一个武将
	if self.delegate:loadedCount() > minCount then
		local pos = self.curSelecteLayer:getTag()
		self.delegate:unloadSoldier(pos)
		self:updateUI()
	end
end

-- 修改阵型的map
function LuaUIForm:changeMapIndex( index )
	self.delegate:selecteMap(index)
	self:updateUI()
	self:updateFormMapBtn()
	self:showEnterAnimation()
end

function LuaUIForm:changeMapFlag( flag )
	self.delegate:selecteFormation(flag + 2)
	-- self:refreshFormPos()
	self.formLayer:updateFormationData(self.delegate:curFormationInfo())
	-- if self.isResFormation and LuaResBattleManager.isLoadedFormation(self.delegate.flag) then
	-- 	self.formLayer:setAllFormTouchEnable(false)
	-- else
	-- 	self.formLayer:setAllFormTouchEnable(true)
	-- end
	self:refreshFormState()
	self:updateFormMapBtn()
	self:showEnterAnimation()
	self:refreshSegmentBtns()
end

-- 根据阵型的使用情况，刷新当前选择阵型的状态（目前仅是否可拖动）
function LuaUIForm:refreshFormState( ... )
	local isFormTouchEnable = true
	if self.isResFormation then
		if LuaResBattleManager.isLoadedFormation(self.delegate.flag) then
			isFormTouchEnable = false
		elseif not LuaFormationManager.isAvaliableResBattleFormation(self.delegate.flag) then
			isFormTouchEnable = false
		end
	end

	self.formLayer:setAllFormTouchEnable(isFormTouchEnable)
end

function LuaUIForm:refreshSegmentBtns()
	local flag = self.delegate.flag

	for i=1,3 do
		if self.isResFormation then
			local playerData = PlayerMgr.getSingleton():playerWithDBId("", nil)
		    local vipInfo = VipConfMgr.getSingleton():getVipByLevel(playerData.curVIPRank)
			local isClose = i > vipInfo.resFormLimit
			self["soldierBtn_"..i]:setEnabled(not isClose)
			if isClose then
				self["resLoadedIcon_" .. i]:setVisible(true)
				local nextVipLevel = LuaResBattleManager.getResFormVipLimitLevel(i)
				utils.setFrameImgToSprite("vipLimit"..nextVipLevel..".png", self["resLoadedIcon_" .. i])
			-- @07/28 ZLu 增加资源战冷却和占领中的显示判定
			elseif LuaResBattleManager.isLoadedFormation(FormationUseType.Arena+i) then
				self["resLoadedIcon_" .. i]:setVisible(true)
				utils.setFrameImgToSprite("zhanlingzhong.png", self["resLoadedIcon_" .. i])
			elseif not LuaFormationManager.isAvaliableResBattleFormation(FormationUseType.Arena+i) then
				self["resLoadedIcon_" .. i]:setVisible(true)
				utils.setFrameImgToSprite("lengquezhong.png", self["resLoadedIcon_" .. i])
			else
				self["resLoadedIcon_" .. i]:setVisible(false)
			end
		else
			self["resLoadedIcon_" .. i]:setVisible(false)
		end

		if (flag - FormationUseType.Arena) == i then
			self["soldierBtn_" .. i]:selected()
		else
			self["soldierBtn_" .. i]:unselected()
		end
	end
end

function LuaUIForm:init()
	if gCurFormType <= FormationUseType.Arena or gCurFormType >= FormationUseType.Conquest1 then
		self.segmentBtns:setVisible(false)
	end
	if gCurFormType == FormationUseType.Conquest1 or gCurFormType == FormationUseType.Conquest2 then
		if self.limitLabel then
			self.limitLabel:setVisible(true)
			if gCurFormType == FormationUseType.Conquest1 then
				self.limitLabel:setString("神将榜——五星武将才能上阵")
			else
				self.limitLabel:setString("名将榜——三星、四星武将才能上阵")
			end
		end
	else
		if self.limitLabel then
			self.limitLabel:setVisible(false)
		end
	end
	self.limitLabel:setTutorialStepId(26020424)

	self:refreshSegmentBtns()
	self:createTableView()
	self:setTouched()
	local formLayer = require("script/LuaFormationLayer").create(false, false, gCurFormType)
	self.loadLayer:addChild(formLayer)
	for i=1,9 do
		local avatar = formLayer["form_" .. i]
		if avatar then
			self:registeLoadedTouchEvent(avatar)
		end
	end
	self.formLayer = formLayer
	-- @10/16 ZLu 征战阵型提示下一级别的可上阵人数
	if gCurFormType == FormationUseType.Monster then
		self.isShowNextCountTips = true
	else
		self.isShowNextCountTips = false
	end
	formLayer:updateFormationData(self.delegate:curFormationInfo(), self.isShowNextCountTips)
	self:updateFormMapBtn()
	-- if self.isResFormation and LuaResBattleManager.isLoadedFormation(self.delegate.flag) then
	-- 	self.formLayer:setAllFormTouchEnable(false)
	-- else
	-- 	self.formLayer:setAllFormTouchEnable(true)
	-- end
	self:refreshFormState()
	self:checkHasAvaliableSoldier()
end

function LuaUIForm:checkHasAvaliableSoldier()
	local unloadSoldier = false
	for i,v in ipairs(self.soldierArray) do
		if not v._loaded then
			unloadSoldier = true
			break
		end
	end
	if not unloadSoldier then
		self.formLayer:hidePlusBling()
	end
end

function LuaUIForm:createTableView()
	self.soldierArray  = self.delegate:soldierList()
	local container = self.unloadLayer
	local cellWidth    = width
	local width        = container:getContentSize().width
	local height       = container:getContentSize().height
	local cellHPadding = (width - 3*cellWidth) / 2
	local cellVPadding = 12
	local cellHeight   = cellWidth + cellVPadding
	local column       = 3
	local function cellSizeForIndex(table, idx)
		return cellHeight * 1.1, width
	end

	local function numberOfCell( table )
		return math.ceil(#self.soldierArray / 3)
	end

	local function cellForIndex( table, idx )
		local height, width = cellSizeForIndex(table, idx)
		local cell = table:dequeueCell()
		if nil == cell then
			 cell = CCTableViewCell:new()
		end
		-- test
		-- local cell = CCLayer:create()
		for i=1,3 do
			local soldierData = self.soldierArray[idx * 3 + i]
			local soldierLayer
			local children = cell:getChildren()
			if children then
				for k=0,children:count()-1 do
					local child = children:objectAtIndex(k)
					if child and child.touchTag == i then
						soldierLayer = child
						break
					end
				end
			end
			-- 如果没有初始化这个layer
			if soldierLayer == nil then
				if soldierData then
					-- 如果有该位置的武将 再初始化
					local isResBattle = gCurFormType >= FormationUseType.Resource1 and gCurFormType <= FormationUseType.Resource5
					soldierLayer = require("script/formation/LuaFormListItem").create(soldierData, isResBattle)
					soldierLayer:updateUI()
					soldierLayer:setScale(cellWidth/soldierLayer:getContentSize().width)
					cell:addChild(soldierLayer)
					soldierLayer.touchTag = i
					self:registeUnloadTouchEvent(soldierLayer)
					-- soldierLayer:setTag(idx * 3 + i)
					soldierLayer:setPosition(ccp((i-1) * (cellWidth + cellHPadding) + cellWidth/2 ,
						cellWidth/2 +cellVPadding))
					if tonumber(soldierData.id) == 12000048 then
						soldierLayer:setTutorialStepId(36010101)
					end
					if self.isResFormation
						and soldierData._loaded
						and LuaResBattleManager.isLoadedFormation(soldierData._loaded) then
						soldierLayer:setTouchEnabled(false)
					else
						soldierLayer:setTouchEnabled(true)
					end

					if gCurFormType == FormationUseType.Conquest1 then
						soldierLayer:displayMoodState()
						-- 神将榜只有5星武将能上阵
						if tonumber(soldierData.star) == 5 then
							soldierLayer:setTouchEnabled(true)
						else
							soldierLayer:addGray()
							soldierLayer:setTouchEnabled(false)
						end
					elseif gCurFormType == FormationUseType.Conquest2 then
						soldierLayer:displayMoodState()
						-- 神将榜只有3星和4星武将能上阵
						if tonumber(soldierData.star) == 3 or tonumber(soldierData.star) == 4 then
							soldierLayer:setTouchEnabled(true)
						else
							soldierLayer:addGray()
							soldierLayer:setTouchEnabled(false)
						end
					end
				end
			else
				if soldierData then
					soldierLayer:updateSoldierData(soldierData)
					-- soldierLayer:displayAsList()
					-- soldierLayer.touchTag = idx * 3 + i
					soldierLayer:setTag(idx * 3 + i)
					soldierLayer:setVisible(true)

					if self.isResFormation
						and soldierData._loaded
						and LuaResBattleManager.isLoadedFormation(soldierData._loaded) then
						soldierLayer:setTouchEnabled(false)
					else
						soldierLayer:setTouchEnabled(true)
					end

					if gCurFormType == FormationUseType.Conquest1 then
						soldierLayer:displayMoodState()
						-- 神将榜只有5星武将能上阵
						if tonumber(soldierData.star) == 5 then
							soldierLayer:setTouchEnabled(true)
							soldierLayer:removeGray()
						else
							soldierLayer:addGray()
							soldierLayer:setTouchEnabled(false)
						end
					elseif gCurFormType == FormationUseType.Conquest2 then
						soldierLayer:displayMoodState()
						-- 神将榜只有3星和4星武将能上阵
						if tonumber(soldierData.star) == 3 or tonumber(soldierData.star) == 4 then
							soldierLayer:setTouchEnabled(true)
							soldierLayer:removeGray()
						else
							soldierLayer:addGray()
							soldierLayer:setTouchEnabled(false)
						end
					end
					soldierLayer:updateUI()
				else
					soldierLayer:setVisible(false)
				end
			end
		end

		return cell
	end

	local tableView
	local function tableViewScrolled()
		local offset = tableView:getContentOffset()
		self.tableOffsetY = offset.y
	end

	-- 添加tableView
	tableView = CCTableView:create(container:getContentSize())
	tableView:setDirection(kCCScrollViewDirectionVertical)

	tableView:setVerticalFillOrder(kCCTableViewFillTopDown)
	container:addChild(tableView)
	tableView:setPosition(ccp(0,0))
	tableView:setTouchPriority(self:getTouchPriority() - 1)
	tableView:setTouchEnabled(true)

	tableView:registerScriptHandler(cellSizeForIndex, 6)
	tableView:registerScriptHandler(cellForIndex, 7)
	tableView:registerScriptHandler(numberOfCell, 8)
	tableView:registerScriptHandler(tableViewScrolled, 0)
	-- tableView:registerScriptHandler(tableCellTouched, cc.TABLECELL_TOUCHED)
	-- -- tableView:registerScriptHandler(tableCellHeighlight, cc.TABLECELL_HIGH_LIGHT)
	-- -- tableView:registerScriptHandler(tableCellUnheighlight, cc.NUMBER_OF_CELLS_IN_TABLEVIEW)

	tableView:reloadData()
	self.tableView = tableView
end

-- 更新下方的阵型按钮的状态
function LuaUIForm:updateFormMapBtn()
	local index = LuaFormationManager.validFormationMapIndex()
	for i=1,7 do
		local btn = self["formMap_" .. i]
		local lock = self["formLock_" .. i]
		if btn then
			local parent = btn:getParent()
			local eventBtn = tolua.cast(parent:getChildByTag(i), "CCMenuItemImage")
			if eventBtn then
				eventBtn:setEnabled(false)
			end
			btn:setEnabled(false)
			btn:unselected()
		end
		local btnChild = btn:getChildByTag(200)
		if btnChild then btnChild:removeFromParentAndCleanup(true) end
		-- 第七个阵型 暂未开放
		if lock and i ~= 7 then
			lock:setVisible(true)
			self:playLockAnimation(btn)
			local label = lock:getChildByTag(100)
			if not label then
				label = createCommonLabel(LuaFormationManager.getFormationOpenLevel(i) .."级开放", nil, 10,
					CCSize(lock:getContentSize().width * 0.7, 0))
				label:setTag(100)
				lock:addChild(label)
				label:setPosition(ccp(lock:getContentSize().width * 0.55,
					lock:getContentSize().height/2))
			end
		end
	end

	for i,v in ipairs(index) do
		local btn = self["formMap_" .. v]
		local lock = self["formLock_" .. v]
		local btnChild = btn:getChildByTag(200)
		if btnChild then btnChild:removeFromParentAndCleanup(true) end
		if btn then
			local parent = btn:getParent()
			local eventBtn = parent:getChildByTag(v)
			if eventBtn then
				eventBtn:setEnabled(true)
			end
			btn:setEnabled(true)
			if lock then
				lock:setVisible(false)
			end
			local curIndex =  self.delegate._curInfo.fomrmationInfo.index
			if curIndex == tonumber(v) then
				btn:selected()
				self:playOpenAnimation(btn)
			end
		end
	end
end


function LuaUIForm:onExitTransitionDidStart()
	self:unregisterProxy()
	-- 关闭阵型的scheduler
	print("关闭阵型页面")
	for i=1,9 do
		local layer = self.formLayer["form_" .. i]
		layer:stopDisplayBuff()
	end
	if __curPage then
		__curPage:showAllBordersBtn()
		__curPage = nil
	end
end

-- 下方阵型按钮的点击回调方法
function LuaUIForm:onPressform( sender )
    local iCurFormation = curPage.delegate.flag

    if curPage.isResFormation then
        if LuaResBattleManager.isLoadedFormation(iCurFormation) then
            _openWarning("占领中的队伍不能进行此操作")
            return
        elseif LuaCDManager.resBattleFormCD(iCurFormation) 
            and os.time() - LuaCDManager.resBattleFormCD(iCurFormation) < LuaResBattleManager.fightCoolingTime then
            _openWarning("冷却中的队伍不能进行此操作")
            return
        end
    end

	--记录当前激活了哪个阵型
	local tag = sender:getTag()
	curPage._curTag = tag
	curPage:changeMapIndex(tonumber(tag))
end

function LuaUIForm:changeFormationFlag( sender )
	local tag = sender:getTag()
	curPage:changeMapFlag(tag)
end


function LuaUIForm:playOpenAnimation( sprite )
   local animation = create_animation("effect04_.plist", "effect04_", 0.08, 1, 6, 0xffffffff)
   local animationSprite = CCSprite:create()
   -- animationSprite:setPosition(point)
   sprite:addChild(animationSprite)
   animationSprite:setScale(0.5)
   animationSprite:setPosition(ccp(sprite:getContentSize().width/2,
   	sprite:getContentSize().height/2))
   animationSprite:setTag(200)
   animationSprite:runAction(animation)
end

function LuaUIForm:playLockAnimation( sprite )
   local animation = create_animation("effect09_.plist", "effect09_", 0.08, 1, 6, 0xffffffff1)
   local animationSprite = CCSprite:create()
   -- animationSprite:setPosition(point)
   sprite:addChild(animationSprite)
   animationSprite:setScale(0.7)
   animationSprite:setPosition(ccp(sprite:getContentSize().width/2,
   	sprite:getContentSize().height/2))
   animationSprite:setTag(200)
   animationSprite:runAction(animation)
end

function LuaUIFormOpen( scene, jsonStr )
	local node =CCBuilderReaderLoad("LuaUIForm.ccbi", CCBProxy:create(), "LuaUIForm")
	self = tolua.cast(node, "CCLayer");

	if jsonStr ~= nil and jsonStr ~= "" then
		local data = json.decode(jsonStr)
		gCurFormType = data["type"]
	else
		--默认使用推图的阵型
		gCurFormType = FormationUseType.Monster
	end

	if gCurFormType >= FormationUseType.Resource1 and gCurFormType <= FormationUseType.Resource5 then
		self.delegate = require("script/formation/ResBattleFormationDelegate").new(gCurFormType)
		-- @11/18 ZLu 资源战不再主动复制征战阵型
		-- if self.delegate:isBlancForm() then
		-- 	self.delegate:copyTarvenFormation(	)
		-- end
		self.isResFormation = true
	else
		self.delegate = require("script/formation/FormationDataDelegate").new(gCurFormType)
	end
	self.validCount = LuaFormationManager.curValidPosCount(gCurFormType)

	self = LuaUIForm.extend(self)
	curPage = self
	--默认使用阵型【1】，
	curPage._curTag = curPage.delegate._curInfo.fomrmationInfo.index
	if not curPage._curTag then
		curPage._curTag = 1
	end
	closeCheckFlag = true

	if self~= nil then
		self:setTouchPriority(scene:getTouchPriority())
		self:init()
	end

	self:registeNodeEvent()

	scene:addChild(self)
end


return LuaUIForm
