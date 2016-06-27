
require("script/debug")

LuaGirlManager = LuaGirlManager or {}

TravelGirlData = {
    "GirlId",       --佳人ID
    "LikeValue",    --好感度
}
TravelGirlData = CreatEnumTable(TravelGirlData, 1)

TravelEventType = {
    "Normal",       --普通事件
    "Girl",         --佳人事件
}
TravelEventType = CreatEnumTable(TravelEventType, 1)

function onLuaGirlManagerMsg(msgId, _json)
    local data = json.decode(_json)
    if msgId == Protocol.SC_Palace_EndReduceFavorTime then
        LuaGirlManager._remainTime = data.endTimeSec

    elseif msgId == Protocol.SC_GetTravel then
        print("获取到游历数据")
        if data.rtn == 0 then
            LuaGirlManager.travelGirlList = {}
            for i,v in ipairs(data.info) do
                local t = {tonumber(v[TravelGirlData.GirlId]), v[TravelGirlData.LikeValue]}
                table.insert(LuaGirlManager.travelGirlList, t)
            end
            LuaGirlManager.traveledCount = data.num
            print("已游历次数"..LuaGirlManager.traveledCount)
        end
        dump(LuaGirlManager.travelGirlList)

    elseif msgId == Protocol.SC_NotifyTravelCount then
        if data.rtn == 0 then
            LuaGirlManager.traveledCount = data.new
        end
    end
end

function LuaGirlManager.registeEvent()
    LuaGirlManager.eventProxy = MyLuaProxy.newProxy("LuaGirlManager.lua")
    LuaGirlManager.eventProxy:addMsgListener( Protocol.SC_Palace_EndReduceFavorTime, "onLuaGirlManagerMsg")
    LuaGirlManager.eventProxy:addMsgListener( Protocol.SC_GetTravel, "onLuaGirlManagerMsg")
    LuaGirlManager.eventProxy:addMsgListener( Protocol.SC_NotifyTravelCount, "onLuaGirlManagerMsg")
end

function LuaGirlManager.loadLocalConfig( ... )
    ConfigParse.loadConfig(LuaGirlManager, "_dialogConfig", "travel_dialog.txt", {"id"})
    ConfigParse.loadConfig(LuaGirlManager, "_eventConfig", "travel_event.txt", {"id", "type", "prev", "factor", "girlID", "dialogID"})
end

function LuaGirlManager.init( ... )
    if LuaGirlManager._init then return end
    LuaGirlManager._init = true

    LuaGirlManager._remainTime = 0
    
    LuaGirlManager.registeEvent()
    LuaGirlManager.loadLocalConfig()

    LuaGirlManager.maxTravelGirlCount = 3
    LuaGirlManager.travelGirlList = {}--当前攻略中的佳人数据
    LuaGirlManager.traveledCount = 0--已游历次数

    LuaGirlManager.selectGirlIndex = 1--UI操作选择的已激活后宫索引记录
    LuaGirlManager.activeGirlList = nil--已激活的后宫数据列表

    LuaGirlManager.firstEventId = 32021901--首次游历（孙尚香）事件
    LuaGirlManager.firstGirlId = 13010019-- 孙尚香
end

function LuaGirlManager.getDialogById(id )
	for k,v in pairs(LuaGirlManager._dialogConfig) do
        if v.id == id then
            return v
        end
    end
end

function LuaGirlManager.getEventById( id )
    for k,v in pairs(LuaGirlManager._eventConfig) do
        if v.id == id then
            return v
        end
    end
end

-- 生成筛选后的事件子集，每次有后宫记录、好感度变化都需要调用重新生成
function LuaGirlManager.createRandomTable(  )
    LuaGirlManager._girlEvent = {}

    local needInitNormalEvent = true
    if LuaGirlManager._normalEvent then
        needInitNormalEvent = false
    else
        LuaGirlManager._normalEvent = {}
    end

    --根据配置的随机权重，生成新的用于计算的有效数值
    local factorGirl = 0
    local factorNormal = 0

    --计算当前攻略中的后宫数量
    local activeGirlCount = LuaGirlManager.getInTravelGirlCount()

    for k,v in pairs(LuaGirlManager._eventConfig) do
        --普通事件直接添加到随机列表中
        if v.type == TravelEventType.Girl then
            --后宫事件需要满足：该后宫正在攻略中，且前置攻略度满足条件
            local isTravelingGirl = false
            for index,girl in pairs(LuaGirlManager.travelGirlList) do
                if girl[TravelGirlData.GirlId] == v.girlID then
                    if girl[TravelGirlData.LikeValue] == v.prev then
                        factorGirl = factorGirl + v.factor
                        table.insert(LuaGirlManager._girlEvent, {v,factorGirl})
                    end
                    isTravelingGirl = true
                    break
                end
            end

            --没有处在攻略中状态的后宫，但正在攻略中的后宫数量未满，则没有前置攻略度条件的对话可加入随机列表
            -- 目前同时攻略的后宫最大数量为3
            if not isTravelingGirl and activeGirlCount < LuaGirlManager.maxTravelGirlCount and v.prev == 0 then
                local girlData = GirlsMgr:getSingleton():getGirlById(v.girlID)
                --如果该后宫还没有激活
                if not girlData.isActive then
                    factorGirl = factorGirl + v.factor
                    table.insert(LuaGirlManager._girlEvent, {v, factorGirl})
                end
            end
        elseif needInitNormalEvent and v.type == TravelEventType.Normal then
            factorNormal = factorNormal + v.factor
            table.insert(LuaGirlManager._normalEvent, {v,factorNormal})
        end
    end

    --最后一个元素记录最大随机区间值
    table.insert(LuaGirlManager._girlEvent, factorGirl)
    if needInitNormalEvent then
        table.insert(LuaGirlManager._normalEvent, factorNormal)
    end
    -- dump(LuaGirlManager._girlEvent)
    -- dump(LuaGirlManager._normalEvent)
end

-- 从指定随机列表中随机一个事件
function LuaGirlManager.getRandomEvent( eventList )
    -- 事件列表的数据结构，包含一个辅助随机值计算的数据，长度需大于1
    if #eventList <= 1 then return end

    local rad = math.random(0,eventList[#eventList])
    for k,v in ipairs(eventList) do
        if rad <= v[2] then
            return v[1]
        end
    end
end

-- 获取一个事件
function LuaGirlManager.getNextEvent( ... )
    -- 如果当前玩家没有后宫，固定开始指定后宫的事件
    if GirlsMgr:getSingleton():getActiveCount() <= 0 then
        local firstEvent = LuaGirlManager.getEventById(LuaGirlManager.firstEventId)
        if firstEvent then
            return firstEvent
        end
    end

    -- return LuaGirlManager.getRandomEvent(LuaGirlManager._girlEvent)

    local randomType = math.random(1, 10)
    if randomType < 8 then
        return LuaGirlManager.getRandomEvent(LuaGirlManager._normalEvent)
    else
        if LuaGirlManager._girlEvent[#LuaGirlManager._girlEvent] > 0 then
            return LuaGirlManager.getRandomEvent(LuaGirlManager._girlEvent)
        else
            return LuaGirlManager.getRandomEvent(LuaGirlManager._normalEvent)
        end
    end
end

-- 获取好感度不减的剩余天数
function LuaGirlManager.getRemainTime( ... )
    return LuaGirlManager._remainTime
end

-- 获取正在攻略中的佳人数量
function LuaGirlManager.getInTravelGirlCount( ... )
    local girlCount = 0
    for k,v in ipairs(LuaGirlManager.travelGirlList) do
        if v then
            girlCount = girlCount+1
        end
    end
    print("获取当前正在攻略中的佳人数量"..girlCount)
    return girlCount
end

-- 获取攻略中的佳人的好感度
function LuaGirlManager.getLikeValueByGirlId( girlId )
    print("获取佳人好感度"..girlId)
    dump(LuaGirlManager.travelGirlList)
    for i,v in ipairs(LuaGirlManager.travelGirlList) do
        if v[TravelGirlData.GirlId] == girlId then
            return v[TravelGirlData.LikeValue]
        end
    end
    return 0
end

-- 增加佳人好感度
function LuaGirlManager.addGirlLikeValue( girlId )
    print("调整攻略中佳人好感数据")
    dump(LuaGirlManager.travelGirlList)
    for i,v in ipairs(LuaGirlManager.travelGirlList) do
        if v[TravelGirlData.GirlId] == girlId then
            print("正在攻略的佳人")
            v[TravelGirlData.LikeValue] = v[TravelGirlData.LikeValue]+1
            return
        end
    end
    if LuaGirlManager.getInTravelGirlCount() > LuaGirlManager.maxTravelGirlCount then return end
    print("新增加的佳人")
    table.insert(LuaGirlManager.travelGirlList, {girlId, 1})
end

-- 当获得了后宫
function LuaGirlManager.onCatchGirl( girlId )
    local girlList = {}
    for i,v in ipairs(LuaGirlManager.travelGirlList) do
        if v[TravelGirlData.GirlId] ~= girlId then
            table.insert(girlList, v)
        end
    end
    LuaGirlManager.travelGirlList = girlList
end

-- 获取需要和服务器同步的佳人数据json
function LuaGirlManager.getGirlRecordDataJson( ... )
    local data = {}
    for i,v in ipairs(LuaGirlManager.travelGirlList) do
        table.insert(data, v)
    end
    return data
end

LuaGirlManager.init()
