--相当于头文件
require "script/CCBReaderLoad"
require "script/Protocol"
require "script/json"
require "script/LuaCDKey"
require "script/LuaCCItemGet"

local self            = nil
local parent          = nil
local cdKeyItem       = nil
local blackLayer      = nil
local ITEM_HEIGHT     = 50
local ITEM_WIDTH      = 65

local LuaActivityItem = createCCBClase("LuaActivityItem")

function LuaActivityItem:assignCCBMemberVariables()

    self.imgMenu = tolua.cast( self  ["getMenuItem"] , "CCMenuItemImage" )
    local menuSprite = tolua.cast(self.imgMenu,"CCMenuItemSprite")
    local disSprite = tolua.cast(menuSprite:getDisabledImage(),"CCSprite")
    disSprite:addGray()
end


--回调(领取奖励)
function LuaActivityItem.onBtnGetCallBack(pSender,target)
    local activityId = target:getTag()
    print("点击的活动ID"..activityId)    

    if LuaActivityManager.activityIndex == ActivityType.GrowUpFolie then
        local userLevel = UserInfoManager.userLevel()
        if self:userDataVsActivityData(userLevel ,activityId, LuaActivityManager.ActivityGrowUpConfig, "level") then
             local info = {}
             info.type = LuaActivityManager.activityIndex
             info.id = activityId
            _sendRequest(Protocol.CS_Activity_GetRewards, info, true)
        else
            _openWarning("未达到领取等级")
        end
    else
        if LuaActivityManager.canGetReward(LuaActivityManager.activityIndex, activityId) then
            local info = {}
            info.type = LuaActivityManager.activityIndex
            info.id = activityId
            _sendRequest(Protocol.CS_Activity_GetRewards, info, true)
        end
    end

end

--对比玩家属性与活动限制属性
function LuaActivityItem:userDataVsActivityData( userData , _id , _table , activityData )
    for i,v in ipairs(_table) do
        if tonumber(v.id) == tonumber(_id) then
            if tonumber(userData) >= tonumber(v[activityData]) then
                return true
            else
                return false
            end
        end
    end

    return false
end

-------------------------
--输入框
-------------------------
function LuaActivityItem:createInputLayer( )
    local size = parent:getParent():getContentSize()
    blackLayer = CCLayerColor:create(ccc4(0,0,0,160),size.width,size.height)
    blackLayer:setPosition(ccp(0,0))
    parent:getParent():addChild(blackLayer)

    cdKeyItem = createLuaCDKey(parent:getParent())
    cdKeyItem:setPosition(ccp(size.width/2,size.height/2))
end

-------------------------
--根据掉落组ID显示奖励物品
-------------------------
function LuaActivityItem:showActivityItemById( ItemDropId )
    if not ItemDropId then
        print(ItemDropId.."is null")
        return
    end

    local itemDropData = DropManager:getSingleton():GetDropGroupJsonById(ItemDropId)
    local itemTable=json.decode(itemDropData)
    self.itemArray = { }
    for i,v in ipairs(itemTable.info) do
        local itemData = BagManager:getSingleton():GetConfigItemById(v.m_itemid)
        local itemImg  = itemData.m_icon
        local itemType = itemData.m_mainType
        local itemNum  = v.m_num
        local item     = createCCItemGet(self.spriteNode)

        if itemType == 4 then
            item.__outNames["cb_spIcon"]:setScale(0.77)
            item.__outNames["cb_spWill"]:setVisible(true)
        end

        local tempFrame = CCSpriteFrameCache:sharedSpriteFrameCache():spriteFrameByName(itemImg)
        if tempFrame then
            item.__outNames["cb_spIcon"]:setDisplayFrame(tempFrame)
        else
            print("LuaActivityItem  no  found  "..itemImg)
        end

        local pos = ccp(30+(i-1)*ITEM_WIDTH, ITEM_HEIGHT/2)
        -- print("    "..pos.x)
        item:setPosition(pos)
        item.__outNames["cb_lbNumber"]:setString(itemNum)

        local qualityFrame = getItemBorderFrameByColor(itemData.m_quality)
        if qualityFrame then
            item.__outNames["cb_spAnimate"]:setDisplayFrame(qualityFrame)
        end

        item.__outNames["cb_spFrame"]:setVisible(false)

        table.insert(self.itemArray,item)

        local container = self:getParent():getParent():getParent()
        local function onTouchDetail( eventType, x, y )
          if eventType == "began" then
              local pos = item:getParent():convertToNodeSpace(ccp(x,y))
              if item:boundingBox():containsPoint(pos) then
                -- 显示道具详细信息
                container.itemDetailLayer = require("script/CCItemDetail"):create(itemData)
                if container.itemDetailLayer then
                  container.itemDetailLayer:setAnchorPoint(ccp(0.5,0))


                  local targetPos = item:convertToWorldSpace(ccp(0,0))
                    targetPos = container:convertToNodeSpace(targetPos)
                    targetPos = ccp(targetPos.x+item:getContentSize().width/2, targetPos.y+item:getContentSize().height/2)



                  container.itemDetailLayer:setPosition(targetPos)
                  container:addChild(container.itemDetailLayer)
                end
                return true
              end
              return false
          elseif eventType == "ended" then
              -- 关闭道具详细信息
              if container.itemDetailLayer then
                container.itemDetailLayer:removeFromParentAndCleanup(true)
                container.itemDetailLayer = nil
              end
          end
      end

      item:registerScriptTouchHandler(onTouchDetail, false, self:getTouchPriority(), false)
      item:setTouchEnabled(true)
      item:setTouchMode(kCCTouchesOneByOne)
    end
end

function LuaActivityItem:onExitTransitionDidStart(  )
    print("LuaActivityItem:onExitTransitionDidStart")
    self:unregisterProxy()
end

function LuaActivityItem:canGetEffect( )
    for i,v in ipairs(self.itemArray) do
        local animate = create_animation("huangse_.plist", "huangse_", 0.08, 1, 16, 0xffffffff)
        v.__outNames["cb_spFrame"]:runAction(animate)
        v.__outNames["cb_spFrame"]:setVisible(true)
        v.__outNames["cb_spAward"]:setVisible(true)
    end
end


-- 设置是否启用（可点击），并设置按钮文字
function LuaActivityItem:setEnableState( isEnabled, btnStr )
    self.imgMenu:setEnabled(isEnabled)
    self.cb_lbBtnText:setString(btnStr)
end

function LuaActivityItem:setMainPage( page )
    self.mainPage = page
end


----------------------------------------------------------------
--初始房间数据
----------------------------------------------------------------
function LuaActivityItem:init( touchPriority )
    self:setTouchPriority(touchPriority)
   -- must before addChild
    self:assignCCBMemberVariables()
end

----------------------------------------------------------------
--打开界面
----------------------------------------------------------------
function createActivityItem( touchPriority )
    local proxy  = CCBProxy:create()
    local node   = CCBuilderReaderLoad("LuaActivityItem.ccbi", proxy, "LuaActivityItem")
          self   = tolua.cast(node, "CCNode");
          self   = LuaActivityItem.extend(self)

    if self ~= nil then
        self:init( touchPriority )
    end
    parent = scene

    return self
end
