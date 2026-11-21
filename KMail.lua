--[[==========================================================================
  KMail
  适用：魔兽世界：无限（forever 分支，1.60.x 独立客户端）

  做两件事：
    1) 一键收取全部邮件的金币与附件
    2) 通讯录：收藏 / 好友 / 公会 / 最近 / 自己（同账号其他小号），点一下填进收件人栏

  设计原则（重要）：
    · 只读 + 只领取。绝不调用 DeleteInboxItem / ReturnInboxItem，不删信、不退信。
    · 跳过货到付款（COD）与 GM 来信，这两类必须玩家自己手动确认。
    · 每个动作之间留 0.2 秒，并检查服务器是否有未完成命令，不做暴力连点。
    · 所有界面 API 都做存在性检查；系统邮箱界面缺位时，仍可用斜杠命令工作。

  API 依据（Gethe/wow-ui-source 的 forever 分支，2026-11-14 实测）：
    Interface/AddOns/Blizzard_MailFrame/MailFrame.lua
      GetInboxNumItems / GetInboxHeaderInfo / TakeInboxMoney / TakeInboxItem
      HasInboxItem / GetInboxItem / CheckInbox / MailFrameTab_OnClick
      SendMailNameEditBox / UIPanelButtonTemplate / ATTACHMENTS_MAX = 16
      OpenAllMailMixin（官方一键收信的安全规则与 0.15s 节流，本插件照其思路）
    Interface/AddOns/Blizzard_APIDocumentationGenerated/MailInfoDocumentation.lua
      C_Mail.IsCommandPending / C_Mail.HasInboxMoney
      事件 MAIL_SHOW / MAIL_CLOSED / MAIL_SEND_SUCCESS / MAIL_INBOX_UPDATE
    Interface/AddOns/Blizzard_FriendsFrame/Camelot/FriendsFrame.lua:137/450/772-787/1535
      C_FriendList.GetNumFriends / GetFriendInfoByIndex(i).name / ShowFriends()
      C_BattleNet.GetFriendAccountInfo(i).gameAccountInfo.characterName
      BNGetNumFriends()（官方同文件在用）
    Interface/AddOns/Blizzard_APIDocumentationGenerated/FriendListDocumentation.lua
      RequiresFriendList 前置条件（FailureMode = ReturnNothing）、FRIENDLIST_UPDATE
      FriendInfo 结构含 name 字段
    Interface/AddOns/Blizzard_APIDocumentationGenerated/BattleNetDocumentation.lua:148/164/210/510
      GetFriendAccountInfo / GetFriendGameAccountInfo / GetFriendNumGameAccounts
      BNetGameAccountInfo.characterName / .clientProgram
    Interface/AddOns/Blizzard_APIDocumentationGenerated/ClubDocumentation.lua:500/433/611/1808
      C_Club.GetGuildClubId / GetClubMembers / GetMemberInfo(...).name
    Interface/AddOns/Blizzard_APIDocumentationGenerated/GuildInfoDocumentation.lua
      C_GuildInfo.GuildRoster / GUILD_ROSTER_UPDATE
    Interface/AddOns/Blizzard_AutoComplete/AutoComplete.lua:19-26/106/195
      AUTOCOMPLETE_LIST.MAIL = ALL_CHARS（include = ALL，exclude = Bnet）
      → 邮箱收件人自动补全里本来就包含「同账号其他角色」
      官方调用：source(text, maxResults, cursorPosition, true, include, exclude)
    Interface/AddOns/Blizzard_APIDocumentationGenerated/AutoCompleteSharedDocumentation.lua:20/37-38
      Enum.AutoCompleteEntryFlag.AccountCharacter = 128
      Enum.AutoCompletePriority.AccountCharacter = 5 / AccountCharacterSameRealm = 6
    Interface/AddOns/Blizzard_APIDocumentationGenerated/AutoCompleteDocumentation.lua:35-53
      C_AutoComplete.GetAutoCompleteResults(...) → results[].name / .priority
    Interface/AddOns/Blizzard_FrameXMLUtil/Camelot/NameUtil.lua  ← 无限服专用覆盖
      FormatUnitNameForDisplay / GetUnmodifiedUnitFullName：
        local name, surname = UnitName(unit) → name..分隔符..surname
        （注意：自动生成的 UnitDocumentation.lua 把第二返回值写成 unitServer，
          但 Camelot 专用实现明确当作 surname，以专用实现为准）
      SplitPlayerNameIntoParts / GetUnitFirstName / IsPlayerMe
      分隔符 = Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
    Interface/AddOns/Blizzard_GlueXML/ForceRenameFullNameDialog.lua:39-42
      GetNames() → characterName, surname（两段式命名的直接证据）
    Interface/AddOns/Blizzard_CharacterCreate/Camelot/Blizzard_CharacterCreate.lua:826/2955
      C_CharacterCreation.CreateCharacter(name, surname, ...) / IsFullNameValid(name, surname)
    Interface/AddOns/Blizzard_APIDocumentationGenerated/NameUtilDocumentation.lua:11
      C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(fullName)
    Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerInfoDocumentation.lua:358
      C_PlayerInfo.ShouldDisplaySurname()

  v1.1.4 新增（2026-11-17，用户要求）：
    ① 邮箱工具条从「贴邮箱左上角」改为「沿邮箱上沿居中」。
    ② 通讯录每次打开默认落在「自己」页，并顺手补扫同账号角色。
    ③ 一键收取逐条在聊天栏列明收到的金币/物品（名称、数量、发件人、主题），
       结束时汇总金币总量与附件件数。此前只报次数，没有明细。
       取明细用 forever 官方源码返回顺序：
         GetInboxHeaderInfo → 3发件人 4主题 5金币 6COD 8附件数 12GM（MailFrame.lua:340）
         GetInboxItem       → 1名称 2ID 3图标 4数量（MailFrame.lua:712）
       注意 GetInboxItem 数量是第 4 位，与正式服第 3 位不同。

  v1.1.3 新增（2026-11-17，用户要求）：
    ① 通讯录面板支持按 Esc 关闭：注册 UISpecialFrames + OnKeyDown 双保险。
    ② 公会页增加搜索框 + 搜索按钮，只在「公会」页显示，其余页自动收起并清空。
       搜索在已缓存的全量公会名单里做大小写不敏感子串匹配（本地过滤，不重复请求服务器），
       支持回车触发；统计行显示「搜「词」命中 X / 共 Y 人」；点公会标签会主动 GuildRoster() 请求一次。
    面板高度 430 → 466，名单下移 30px 腾出搜索行；窗口宽度与标签/名单行宽不变。

  v1.1.2 修复（2026-11-16，实机反馈「自己页偶尔只有姓，没法发邮件」）：
    无限服角色名是「6+6 姓和名」两段式，全名 = 名 + 官方分隔符 + 姓。
    旧版 SelfName() 只取 UnitName 的第一个返回值，登录登记写进 DB.alts 的是半名，
    收件人栏填半名自然发不出去；自动补全有时也只回半名，所以表现为「偶尔」。
    现改为：UnitName 两返回值 + 运行时官方分隔符拼接（NameUtil 封装兜底）；
    用官方 SplitPlayerNameIntoParts 区分完整名 / 半名；
    自动补全拿到半名时，以「名+分隔符」为前缀再查一次把姓补全；
    PrunePartialAlts 清掉旧存档脏数据，ResolveComplete 在点名字 / 手动输入时自动升级，
    实在补不全的标 [半名] 并在 tooltip 提示，不再静默填进收件人栏。

  v1.1.1 微调（2026-11-14，用户要求）：
    标签顺序改为 自己 / 收藏 / 好友 / 公会 / 最近；
    标签按钮恢复加「自己」之前的 66 宽 / 73 间距，窗口 320 → 386 来容纳 5 个，
    名单行同步加宽到 320 并重新居中。默认打开页仍是「收藏」。

  v1.1.0 新增（2026-11-14，用户要求「加一个『自己』按钮」）：
    通讯录新增「自己」页，列出同一账号的其他角色。
    双通道：① 用 C_AutoComplete 按 AccountCharacter 标志扫描邮箱补全名单；
    ② KMailDB 是账号级 SavedVariables（非 PerCharacter），每个小号登录一次
       就自动登记 UnitName("player")，全账号角色共享，不依赖任何 API。
    手动补漏：/km alt 名字 /km unalt 名字 /km altscan。

  v1.0.2 修复（2026-11-14，实机反馈「好友页带不出列表」）：
    无限服好友界面同时显示两套名单：旧式游戏内好友（C_FriendList）与
    战网好友（C_BattleNet.GetFriendAccountInfo / BNGetNumFriends）。
    官方 FriendsFrame/Camelot/FriendsFrame.lua:772-787、:137 两套都读，
    且切到好友页会调 C_FriendList.ShowFriends() 请求服务器下发名单。
    C_FriendList 所有函数带 RequiresFriendList 前置条件（FailureMode=ReturnNothing），
    没请求过就直接返回 nothing。旧版只读旧式名单且从不 ShowFriends() → 空页。
    现改为三路合并 + 主动刷新 + 监听 FRIENDLIST_UPDATE 后自动重绘。

  v1.0.1 修复（2026-11-14，实机反馈「插件加载了但邮箱界面没反应」）：
    官方 MailFrame.lua 用 RegisterPlayerInteraction(showFunc = MailFrame_Show) 显示窗口，
    MailFrame 自身注册的事件里没有 MAIL_SHOW。旧版只在 MAIL_SHOW 时挂按钮，
    时机错过就永远不出现；且按钮挂在 MailFrame 内部，易被系统 UI 层盖住。
    现改为：独立浮动工具条 + OnUpdate 每 0.4 秒轮询 MailFrame:IsShown()，
    不依赖事件时机、不依赖 MailFrame 在插件加载时已存在，并新增 /km show /km hide。

  未核实项（代码里均有 fallback，不会因此报错）：
    运行时能否读到 CHARACTERNAME_SURNAME_SEPARATOR（读不到用 "-" 兜底，
      判定完整性优先走官方 SplitPlayerNameIntoParts，不靠猜字符）；
    是否存在合法的无姓单段角色名（若有，会被标 [半名]，但仍显示、仍可点击）；
    GetAutoCompleteResults 传空前缀时是否一次列全（故另有 a-z/0-9 逐字母探测）；
    中文角色名能否被逐字母探测到（故有登录自动登记 + 手动 /km alt 兜底）；
    旧式 GetNumGuildMembers / GetGuildRosterInfo 在 forever 是否仍导出（现仅作兜底）；
    战网好友 / 跨服小号角色名是否需要「名字-服务器」后缀；国服客户端字体模板名。
==========================================================================]]

local ADDON_NAME = "KMail"
local PREFIX = "|cff4fc3f7[KMail]|r "

local MAX_ATTACHMENT_SLOT = 16   -- 官方 MailFrame.lua: ATTACHMENTS_MAX = 16
local RETRIEVE_DELAY = 0.20      -- 官方用 0.15，这里放宽一点
local MAX_STALL = 6              -- 同一动作连续无进展次数上限，防死循环
local PAGE_SIZE = 12
local MAX_FAV = 40
local MAX_RECENT = 10
local MAX_ALTS = 30

-- AutoCompleteSharedDocumentation.lua:20 / 37-38 的枚举值；运行时若 Enum 表可用会覆写。
local ALT_FLAG = 128
local PRI_ALT = 5
local PRI_ALT_SAME = 6
local FLAG_ALL = 0xffffffff

local DB
local mainFrame
local grabButton, bookButton
local book, titleText, pageText
local nameButtons = {}
local guildSearchBox, guildSearchBtn     -- 公会页搜索框 / 搜索按钮（仅 guild 页显示）
local guildFilter = ""                   -- 当前搜索词；空 = 显示全部
local guildCache = {}                    -- 公会全量名单缓存（名单异步下发，搜索只在本地过滤，不重取）
local currentTab = "alt"          -- 通讯录打开默认落在「自己」页
local currentPage = 1
local currentList = {}

local bar                    -- 独立浮动工具条，parent = UIParent
local barBuilt = false
local barForced = false      -- /km show 强制显示
local barAnchor = nil        -- nil / "mail" / "screen"，避免反复重定位覆盖玩家拖动
local attachTimer = 0
local mailShowCount = 0
local mailOpen = false
local apiWarned = false
local friendDiag = { legacy = "未查", bnet = "未查" }
local guildDiag = "未查"
local altDiag = "未扫描"
local altScanDone = false
local loginScanTimer = 0
local loginScanDone = false

-- 发邮件按附件自动填标题（邮寄XX等物品）
local subjectHooked = false      -- 是否已把钩子挂到官方 SendMailFrame_Update
local lastAutoSubject = nil      -- 上次由本插件填入的标题；用来识别并覆盖自己的旧值，不碰玩家手输

-- 收取状态
local grabbing = false
local waitTimer = 0
local actions = 0
local lastActionKey = nil
local sameCount = 0
local totalMoney = 0             -- 本次收取的金币总量（铜）
local totalItems = 0             -- 本次收取的附件件数

local TAB_TITLES = {
  fav = "收藏联系人",
  friend = "好友列表",
  guild = "公会成员",
  recent = "最近寄信人",
  alt = "我的其他小号",
}
local TABS = {
  { key = "alt",    label = "自己" },
  { key = "fav",    label = "收藏" },
  { key = "friend", label = "好友" },
  { key = "guild",  label = "公会" },
  { key = "recent", label = "最近" },
}

--------------------------------------------------------------------------------
-- 基础工具
--------------------------------------------------------------------------------
local function Msg(s)
  local text = PREFIX .. tostring(s)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(text, 0.35, 0.78, 1)
  elseif print then
    print(text)
  end
end

local function InitDB()
  if type(KMailDB) ~= "table" then KMailDB = {} end
  DB = KMailDB
  if type(DB.favorites) ~= "table" then DB.favorites = {} end
  if type(DB.recent) ~= "table" then DB.recent = {} end
  -- 账号级存档：同一账号下所有角色共享这一份名单
  if type(DB.alts) ~= "table" then DB.alts = {} end
end

local function IsFav(name)
  for _, v in ipairs(DB.favorites) do
    if v == name then return true end
  end
  return false
end

local function AddFav(name)
  if not name or name == "" then Msg("名字不能为空"); return end
  if IsFav(name) then Msg("已在收藏里：" .. name); return end
  table.insert(DB.favorites, 1, name)
  while #DB.favorites > MAX_FAV do table.remove(DB.favorites) end
  Msg("已收藏：" .. name)
end

local function DelFav(name)
  for i, v in ipairs(DB.favorites) do
    if v == name then
      table.remove(DB.favorites, i)
      Msg("已取消收藏：" .. name)
      return
    end
  end
  Msg("收藏里没有：" .. name)
end

local function AddRecent(name)
  if not name or name == "" then return end
  for i, v in ipairs(DB.recent) do
    if v == name then table.remove(DB.recent, i); break end
  end
  table.insert(DB.recent, 1, name)
  while #DB.recent > MAX_RECENT do table.remove(DB.recent) end
end

local function Unique(t)
  local seen, out = {}, {}
  for _, n in ipairs(t) do
    if n and n ~= "" and not seen[n] then
      seen[n] = true
      table.insert(out, n)
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- 「自己」：同一账号下的其他小号
--   KMailDB 是账号级 SavedVariables（toc 里不是 SavedVariablesPerCharacter），
--   所以每个小号登录一次自动登记，全账号角色都能看到同一份名单。
--------------------------------------------------------------------------------
local function InitAltEnums()
  if type(Enum) == "table" then
    local flags = Enum.AutoCompleteEntryFlag
    if type(flags) == "table" and type(flags.AccountCharacter) == "number" then
      ALT_FLAG = flags.AccountCharacter
    end
    local pri = Enum.AutoCompletePriority
    if type(pri) == "table" then
      if type(pri.AccountCharacter) == "number" then PRI_ALT = pri.AccountCharacter end
      if type(pri.AccountCharacterSameRealm) == "number" then PRI_ALT_SAME = pri.AccountCharacterSameRealm end
    end
  end
end

--------------------------------------------------------------------------------
-- 无限服「6+6 姓和名」：全名 = 名 + 官方分隔符 + 姓
--   Camelot/NameUtil.lua 实证：UnitName(unit) 返回 (name, surname)，
--   官方用 Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR 拼接。
--   旧版只取第一个返回值，名单里存的是半名 → 收件人栏填半名，邮件发不出去。
--------------------------------------------------------------------------------
local function NameSep()
  if type(Constants) == "table" and type(Constants.CharacterNameSeparatorConsts) == "table" then
    local s = Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
    if type(s) == "string" and s ~= "" then return s end
  end
  return "-"   -- 兜底：官方 SplitPlayerNameIntoParts 的模式也是按连字符切
end

-- 返回 (第一段, 是否为完整全名)。优先用官方拆分函数，
-- 它内部就用官方分隔符，不需要我们猜字符。
local function HeadOf(n)
  if not n or n == "" then return nil, false end
  if type(NameUtil) == "table" and type(NameUtil.SplitPlayerNameIntoParts) == "function" then
    local ok, first, surname = pcall(NameUtil.SplitPlayerNameIntoParts, n)
    if ok and first and surname and surname ~= "" then
      return first, true
    end
    return nil, false
  end
  local sep = NameSep()
  local i = n:find(sep, 1, true)
  if i and i > 1 and i < #n then return n:sub(1, i - 1), true end
  return nil, false
end

local function SelfName()
  -- 无限服 UnitName("player") = (name, surname)；第二返回值不是服务器名。
  if type(UnitName) == "function" then
    local ok, first, surname = pcall(UnitName, "player")
    if ok and first and first ~= "" then
      local _, alreadyFull = HeadOf(first)
      if surname and surname ~= "" and not alreadyFull then
        return first .. NameSep() .. surname
      end
      return first
    end
  end
  -- 兜底：官方 Camelot 封装内部也做 name..分隔符..surname
  if type(NameUtil) == "table" then
    if type(NameUtil.GetUnmodifiedUnitFullName) == "function" then
      local ok, full = pcall(NameUtil.GetUnmodifiedUnitFullName, "player")
      if ok and full and full ~= "" then return full end
    end
    if type(NameUtil.FormatUnitNameForDisplay) == "function" then
      local ok, full = pcall(NameUtil.FormatUnitNameForDisplay, "player")
      if ok and full and full ~= "" then return full end
    end
  end
  return nil
end

-- 两个完整名不同 = 两个角色（6+6 允许同名不同姓，绝不能只比第一段）。
-- 只有「半名恰好是自己全名的第一段」才认作自己，用于清掉历史脏数据。
local function IsSelfName(name, me)
  if not me then return false end
  if name == me then return true end
  local _, nameFull = HeadOf(name)
  if nameFull then return false end
  local head, meFull = HeadOf(me)
  return meFull and head == name
end

-- 半名 → 存档里已有的完整名（点列表 / 手动输入时自动升级）
local function ResolveComplete(name)
  if not name or name == "" then return name end
  local _, isFull = HeadOf(name)
  if isFull then return name end
  for _, n in ipairs(DB.alts) do
    local head, full = HeadOf(n)
    if full and head == name then return n end
  end
  return name
end

-- 清掉已被完整名覆盖的半名（旧版留下的脏数据，一次清理写入存档）
local altPruned = 0
local function PrunePartialAlts()
  local heads = {}
  for _, n in ipairs(DB.alts) do
    local head, full = HeadOf(n)
    if full and head then heads[head] = true end
  end
  local kept = {}
  for _, n in ipairs(DB.alts) do
    local _, full = HeadOf(n)
    if full or not heads[n] then
      kept[#kept + 1] = n
    else
      altPruned = altPruned + 1
    end
  end
  DB.alts = kept
end

local function AddAlt(name)
  name = (name or ""):match("^%s*(.-)%s*$")
  if name == "" then return false end
  name = ResolveComplete(name)
  for _, v in ipairs(DB.alts) do
    if v == name then return false end
  end
  table.insert(DB.alts, name)
  while #DB.alts > MAX_ALTS do table.remove(DB.alts, 1) end
  return true
end

local function DelAlt(name)
  name = ResolveComplete(name)
  for i, v in ipairs(DB.alts) do
    if v == name then
      table.remove(DB.alts, i)
      return true
    end
  end
  return false
end

local function RememberSelf()
  local me = SelfName()
  if me then AddAlt(me) end
end

-- 邮箱收件人自动补全里带 AccountCharacter 标志的条目，就是同账号其他角色。
-- 只收 priority = AccountCharacter / AccountCharacterSameRealm 的结果，
-- 即便某些实现把好友、公会也一起返回，也不会混进「自己」页。
local function QueryAlts(prefix, flags, strict)
  if not (C_AutoComplete and type(C_AutoComplete.GetAutoCompleteResults) == "function") then
    return 0, false
  end
  local ok, res = pcall(C_AutoComplete.GetAutoCompleteResults,
                        prefix, 100, #prefix, true, flags, 0)
  if not ok or type(res) ~= "table" then return 0, false end
  local got = 0
  for _, r in ipairs(res) do
    if type(r) == "table" and r.name and r.name ~= "" then
      local pri = r.priority
      -- strict：用 ALL 标志兜底时，只认明确的账号角色优先级，
      -- 免得把好友 / 公会成员当成自己的小号。
      local accept = (not strict and pri == nil) or pri == PRI_ALT or pri == PRI_ALT_SAME
      if accept and AddAlt(r.name) then got = got + 1 end
    end
  end
  return got, true
end

local function ScanAlts(force)
  if not DB then return end
  if altScanDone and not force then return end
  altScanDone = true
  InitAltEnums()
  RememberSelf()
  if not (C_AutoComplete and type(C_AutoComplete.GetAutoCompleteResults) == "function") then
    altDiag = "自动补全接口不可用（靠登录登记 / /km alt）"
    return
  end

  -- 空前缀若能一次列全最省事；否则再按 a-z / 0-9 逐字母探测。
  -- 中文名无法枚举，所以还有「每个小号登录一次即登记」这条更可靠的通道。
  local prefixes = { "" }
  for c = string.byte("a"), string.byte("z") do
    prefixes[#prefixes + 1] = string.char(c)
  end
  for c = string.byte("0"), string.byte("9") do
    prefixes[#prefixes + 1] = string.char(c)
  end

  local called = 0
  local function Pass(flagSet)
    local got, okAny = 0, false
    for _, p in ipairs(prefixes) do
      local n, okq = QueryAlts(p, flagSet, flagSet ~= ALT_FLAG)
      got = got + n
      called = called + 1
      if okq then okAny = true end
    end
    return got, okAny
  end

  local found, anyOK = Pass(ALT_FLAG)
  if found == 0 then
    -- 有些实现把 includeFlags 理解成「必须含全部标志位」，换官方 ALL 再试，
    -- 依旧只按 priority 过滤，不会把好友塞进来。
    local found2, ok2 = Pass(FLAG_ALL)
    found = found + found2
    anyOK = anyOK or ok2
  end

  -- 自动补全偶尔只回「名」不回「姓」。拿这些半名（以及已有全名的第一段）
  -- 拼上官方分隔符当前缀再查一次，把「名-姓」补全。
  local heads = {}
  for _, n in ipairs(DB.alts) do
    local head, full = HeadOf(n)
    if full and head and head ~= "" then
      heads[head] = true
    elseif not full and n ~= "" then
      heads[n] = true
    end
  end
  local expanded = 0
  for head in pairs(heads) do
    local p = head .. NameSep()
    -- 按 AccountCharacter 标志查时允许 priority 缺省；换 ALL 兜底时必须严格核对优先级
    local n1, ok1 = QueryAlts(p, ALT_FLAG, false)
    called = called + 1
    if ok1 then anyOK = true end
    local n2 = 0
    if n1 == 0 then
      n2 = QueryAlts(p, FLAG_ALL, true)
      called = called + 1
    end
    expanded = expanded + n1 + n2
  end
  found = found + expanded
  PrunePartialAlts()

  if not anyOK then
    altDiag = "自动补全调用失败（靠登录登记 / /km alt）"
  elseif found > 0 then
    altDiag = "自动补全新发现 " .. found .. " 个（半名补全 " .. expanded ..
              " 个 · 共查 " .. called .. " 次）"
  else
    altDiag = "自动补全未返回角色（靠登录登记 / /km alt）"
  end
end

local function GetAlts()
  ScanAlts()
  PrunePartialAlts()   -- 旧存档里被完整名覆盖的半名，打开页面时就地清掉
  local me = SelfName()
  local out = {}
  for _, n in ipairs(DB.alts) do
    if not IsSelfName(n, me) then
      -- 能补成全名的就补；补不成的仍在列表里标红，避免「小号凭空消失」
      table.insert(out, ResolveComplete(n))
    end
  end
  local list = Unique(out)
  table.sort(list)
  return list
end

--------------------------------------------------------------------------------
-- 名单来源
--------------------------------------------------------------------------------
-- 官方 FriendsFrame 切到好友页时就会调它，向服务器请求下发好友名单。
-- C_FriendList 的所有函数带 RequiresFriendList 前置条件（失败返回 nothing），
-- 不先请求一次，GetNumFriends 可能拿到 nil，好友页自然就是空的。
local function RefreshFriendList()
  if C_FriendList and type(C_FriendList.ShowFriends) == "function" then
    pcall(C_FriendList.ShowFriends)
  end
end

-- 无限服好友界面里，很多名字其实是战网好友（BNET 按钮），不是旧式游戏内好友。
-- 官方同款写法：FriendsFrameCamelot.lua:137 C_BattleNet.GetFriendAccountInfo(id)
-- 角色名在 accountInfo.gameAccountInfo.characterName（BattleNetDocumentation.lua:521）。
local function GetBNetFriends()
  local out = {}
  if not (C_BattleNet and type(C_BattleNet.GetFriendAccountInfo) == "function") then
    return out, "C_BattleNet 不可用"
  end
  local total = 0
  if type(BNGetNumFriends) == "function" then
    local ok, a = pcall(BNGetNumFriends)
    if ok and type(a) == "number" then total = a end
  end
  if total <= 0 then return out, "战网好友 0 人" end

  local wowClient = BNET_CLIENT_WOW or "WoW"
  for i = 1, total do
    local ok, acc = pcall(C_BattleNet.GetFriendAccountInfo, i)
    if ok and type(acc) == "table" then
      local gi = acc.gameAccountInfo          -- 当前活跃的游戏账号
      if type(gi) == "table" and gi.characterName and gi.characterName ~= ""
         and (not gi.clientProgram or gi.clientProgram == wowClient) then
        table.insert(out, gi.characterName)
      end
      -- 离线 / 多游戏账号的好友：遍历其所有游戏账号补角色名
      if type(C_BattleNet.GetFriendNumGameAccounts) == "function"
         and type(C_BattleNet.GetFriendGameAccountInfo) == "function" then
        local ok2, n = pcall(C_BattleNet.GetFriendNumGameAccounts, i)
        if ok2 and type(n) == "number" then
          for j = 1, n do
            local ok3, g = pcall(C_BattleNet.GetFriendGameAccountInfo, i, j)
            if ok3 and type(g) == "table" and g.characterName and g.characterName ~= ""
               and (not g.clientProgram or g.clientProgram == wowClient) then
              table.insert(out, g.characterName)
            end
          end
        end
      end
    end
  end
  return out, "战网好友 " .. total .. " 人"
end

local function GetFriends()
  local out = {}
  -- ① 旧式游戏内好友（无限服 Camelot 好友界面的 WOW 按钮）
  if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
    local ok, n = pcall(C_FriendList.GetNumFriends)
    friendDiag.legacy = (ok and type(n) == "number") and (n .. " 人") or "读不到（列表未就绪）"
    if ok and type(n) == "number" then
      for i = 1, n do
        local ok2, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
        if ok2 and type(info) == "table" and info.name then
          table.insert(out, info.name)
        end
      end
    end
  -- ② 更老的全局接口兜底
  elseif type(GetNumFriends) == "function" and type(GetFriendInfo) == "function" then
    local ok, n = pcall(GetNumFriends)
    friendDiag.legacy = (ok and type(n) == "number") and (n .. " 人(旧接口)") or "读不到"
    if ok and type(n) == "number" then
      for i = 1, n do
        local ok2, name = pcall(GetFriendInfo, i)
        if ok2 and name then table.insert(out, name) end
      end
    end
  else
    friendDiag.legacy = "接口不存在"
  end
  -- ③ 战网好友（无限服好友界面里大多数名字在这里）
  local bnet, why = GetBNetFriends()
  friendDiag.bnet = why
  for _, n in ipairs(bnet) do table.insert(out, n) end
  return Unique(out)
end

-- forever 分支源码实证（ClubDocumentation.lua:500 / 433 / 611 / 1808）：
--   C_Club.GetGuildClubId() → clubId
--   C_Club.GetClubMembers(clubId) → memberId 数组
--   C_Club.GetMemberInfo(clubId, memberId).name → 角色名
-- 旧版的 GetNumGuildMembers / GetGuildRosterInfo 在 forever 没被官方 UI 调用过，
-- 属于「未核实」，现在只当兜底。
local function GetGuild()
  local out = {}
  guildDiag = "无可用接口"
  if C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo then
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    local ok, clubId = pcall(C_Club.GetGuildClubId)
    if ok and clubId then
      local ok2, ids = pcall(C_Club.GetClubMembers, clubId)
      if ok2 and type(ids) == "table" then
        for _, id in ipairs(ids) do
          local ok3, info = pcall(C_Club.GetMemberInfo, clubId, id)
          if ok3 and type(info) == "table" and info.name and info.name ~= "" then
            table.insert(out, info.name)
          end
        end
        guildDiag = "C_Club " .. #ids .. " 人"
      else
        guildDiag = "公会名单未就绪"
      end
    else
      guildDiag = "没有公会 / 未初始化"
    end
  end
  -- 老式全局接口兜底（全部 pcall，不存在也不报错）
  if #out == 0 and type(GetNumGuildMembers) == "function" and type(GetGuildRosterInfo) == "function" then
    local ok, n = pcall(GetNumGuildMembers)
    if ok and type(n) == "number" and n > 0 then
      for i = 1, n do
        local ok2, name = pcall(GetGuildRosterInfo, i)
        if ok2 and name and name ~= "" then table.insert(out, name) end
      end
      guildDiag = "旧接口 " .. n .. " 人"
    end
  end
  -- 有数据才更新缓存：名单异步下发，未就绪时返回空，别把已有的全量名单清掉
  if #out > 0 then guildCache = Unique(out) end
  return guildCache
end

-- 公会搜索：在本地缓存里按大小写不敏感的子串匹配；词为空则返回全部。
-- 无限服角色名是两段式，玩家可能只记得名或只记得姓，子串匹配两边都能命中。
local function FilterGuild(list, keyword)
  if not keyword or keyword == "" then return list end
  local kw = string.lower(keyword)
  local out = {}
  for _, name in ipairs(list) do
    if string.find(string.lower(name), kw, 1, true) then
      table.insert(out, name)
    end
  end
  return out
end

local function BuildList()
  if currentTab == "fav" then
    currentList = Unique(DB.favorites)
  elseif currentTab == "friend" then
    currentList = GetFriends()
    table.sort(currentList)
  elseif currentTab == "guild" then
    currentList = FilterGuild(GetGuild(), guildFilter)
    table.sort(currentList)
  elseif currentTab == "alt" then
    currentList = GetAlts()
  else
    currentList = Unique(DB.recent)   -- 最近联系人不排序，新的在前
  end
end

--------------------------------------------------------------------------------
-- 收件人填入
--------------------------------------------------------------------------------
local function UseRecipient(name)
  -- 最后一道保险：即使名单里还残存半名，也自动填成完整全名
  name = ResolveComplete(name)
  -- 官方 OpenMailReplyMixin:Reply() 就是这么切到写信页的
  if type(MailFrameTab_OnClick) == "function" then
    pcall(MailFrameTab_OnClick, nil, 2)
  end
  local box = SendMailNameEditBox
  if not box and SendMailFrame and SendMailFrame.NameEditBox then
    box = SendMailFrame.NameEditBox
  end
  if box and box.SetText then
    box:SetText(name)
    Msg("已填入收件人：" .. name)
  else
    Msg("没找到收件人输入框，请手动输入：" .. name)
  end
  if book then book:Hide() end
end

--------------------------------------------------------------------------------
-- 通讯录窗口（纯 Lua 创建，不写 XML，尽量少依赖模板）
--------------------------------------------------------------------------------
local function RefreshBook()
  BuildList()
  -- 搜索框只在公会页出现；离开公会页时收起并清掉筛选，免得下次进来还留着旧词
  if guildSearchBox then
    if currentTab == "guild" then
      guildSearchBox:Show()
      if guildSearchBtn then guildSearchBtn:Show() end
    else
      guildSearchBox:Hide()
      if guildSearchBtn then guildSearchBtn:Hide() end
      guildFilter = ""
      if guildSearchBox:GetText() ~= "" then guildSearchBox:SetText("") end
    end
  end
  local total = #currentList
  local pages = math.max(1, math.ceil(total / PAGE_SIZE))
  if currentPage > pages then currentPage = pages end
  local base = (currentPage - 1) * PAGE_SIZE

  for i = 1, PAGE_SIZE do
    local b = nameButtons[i]
    local name = currentList[base + i]
    b.nameValue = name
    if name then
      local favMark = IsFav(name) and "|cffffd700★|r " or "    "
      local partialMark = ""
      if currentTab == "alt" then
        local _, isFull = HeadOf(name)
        if not isFull then partialMark = "|cffff8a80[半名]|r " end
      end
      b:SetText(favMark .. partialMark .. name)
      b:Show()
    else
      b:Hide()
    end
  end

  titleText:SetText("KMail · " .. (TAB_TITLES[currentTab] or ""))
  if total == 0 then
    if currentTab == "guild" then
      if guildFilter ~= "" then
        pageText:SetText("没找到匹配「" .. guildFilter .. "」的成员，清空搜索框再搜")
      else
        pageText:SetText("读不到公会名单，可用 /km fav 名字 手动收藏")
      end
    elseif currentTab == "fav" then
      pageText:SetText("还没有收藏，右键列表里的名字即可加入")
    elseif currentTab == "friend" then
      pageText:SetText("名单正在刷新 / 或确实没有好友；/km test 可看来源")
    elseif currentTab == "alt" then
      pageText:SetText("换小号上线一次即登记完整全名，或 /km alt 名-姓 手动加")
    else
      pageText:SetText("（暂无名字）")
    end
  else
    local stat = currentPage .. " / " .. pages .. "   共 " .. total .. " 人"
    if currentTab == "guild" and guildFilter ~= "" then
      stat = "搜「" .. guildFilter .. "」命中 " .. total .. " / " .. #guildCache .. " 人"
    end
    pageText:SetText(stat)
  end
end

local function BuildBook()
  book = CreateFrame("Frame", "KMailBook", UIParent)
  -- 5 个标签仍用加「自己」之前的 66 宽 / 73 间距：
  -- 最后一个右边缘 14 + 4*73 + 66 = 372，窗口取 386，左右留白各 14。
  -- 高度 466 → 506：底部翻页按钮 / 页码提示 / 操作说明分三行排开，互不遮挡。
  book:SetSize(386, 506)
  -- 注册到暴雪标准 ESC 关闭列表（UIPanel 通用机制），按 Esc 自动 Hide 该窗口。
  -- 做存在性检查：某些精简客户端若没有这张表，就退回插件自己的 OnKeyDown 处理。
  if type(UISpecialFrames) == "table" then
    tinsert(UISpecialFrames, "KMailBook")
  else
    book:EnableKeyboard(true)
  end
  book:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  book:SetFrameStrata("DIALOG")
  book:EnableMouse(true)
  book:SetMovable(true)
  book:RegisterForDrag("LeftButton")
  book:SetScript("OnDragStart", function(self) self:StartMoving() end)
  book:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  -- 整段装饰单独包 pcall：就算经典内核缺某个 API，也只丢装饰，绝不中断按钮创建
  local okDecor, errDecor = pcall(function()

  -- 纯色工具：经典内核用 WHITE8X8 白纹理 + 顶点染色，最通用；再包 pcall 防中断
  local WHITE = "Interface\\Buttons\\WHITE8X8"
  local function solid(tex, r, g, b, a)
    local ok = pcall(function()
      tex:SetTexture(WHITE)
      tex:SetVertexColor(r, g, b, a or 1)
    end)
    if not ok then tex:Hide() end
  end
  local function box(sub, x1, y1, x2, y2, r, g, b, a)
    local t = book:CreateTexture(nil, "BACKGROUND", nil, sub)
    t:SetPoint("TOPLEFT", book, "TOPLEFT", x1, y1)
    t:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", x2, y2)
    solid(t, r, g, b, a)
    return t
  end
  local function rect(sub, x, y, w, h, r, g, b, a)
    local t = book:CreateTexture(nil, "BACKGROUND", nil, sub)
    t:SetSize(w, h)
    t:SetPoint("TOPLEFT", book, "TOPLEFT", x, y)
    solid(t, r, g, b, a)
    return t
  end

  -- ===== 立体金属外框：5 层内缩，露出「黑→亮金→主金→内阴影」浮雕边 =====
  box(1, 0, 0,  0, 0,  0.03, 0.03, 0.03, 1)
  box(2, 2, -2, -2, 2, 0.85, 0.74, 0.40, 1)   -- 亮金高光
  box(3, 5, -5, -5, 5, 0.46, 0.37, 0.16, 1)   -- 主金
  box(4, 8, -8, -8, 8, 0.02, 0.02, 0.02, 1)   -- 内容内阴影

  -- 内容背景（内缩10，带经典纹理叠加做出质感）
  local bg = book:CreateTexture(nil, "BACKGROUND", nil, 5)
  bg:SetPoint("TOPLEFT", book, "TOPLEFT", 10, -10)
  bg:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -10, 10)
  if bg.SetColorTexture then pcall(bg.SetColorTexture, bg, 0.05, 0.07, 0.10, 0.97)
  else solid(bg, 0.05, 0.07, 0.10, 0.97) end
  local artBg = book:CreateTexture(nil, "BACKGROUND", nil, 6)
  artBg:SetPoint("TOPLEFT", book, "TOPLEFT", 10, -10)
  artBg:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -10, 10)
  artBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
  artBg:SetVertexColor(0.28, 0.34, 0.42, 0.70)

  -- ===== 标题条：黑底 + 金色高光边（文字用按钮同款金黄）=====
  rect(7, 56, -8, 274, 36, 0.02, 0.02, 0.02, 1)   -- 黑底
  rect(8, 56, -8, 274, 2,  0.75, 0.65, 0.35, 1)   -- 上高光(金)
  rect(8, 56, -42, 274, 2, 0.02, 0.02, 0.02, 1)   -- 下阴影

  -- ===== 标签行下方凸起分隔线 =====
  rect(9, 16, -72, 354, 2, 0.75, 0.65, 0.35, 0.9)
  rect(9, 16, -74, 354, 2, 0.02, 0.02, 0.02, 0.9)

  -- ===== 名单区内嵌凹槽：上/左暗（内阴影）、下/右亮（高光）=====
  rect(9, 22, -104, 342, 312, 0.02, 0.03, 0.05, 0.42)
  rect(10, 22, -104, 342, 2, 0.02, 0.02, 0.02, 0.9)   -- 上（暗）
  rect(10, 22, -104, 2, 312, 0.02, 0.02, 0.02, 0.9)   -- 左（暗）
  rect(10, 22, -414, 342, 2, 0.75, 0.65, 0.35, 0.8)   -- 下（亮）
  rect(10, 362, -104, 2, 312, 0.75, 0.65, 0.35, 0.8)   -- 右（亮）

  -- 底部说明区靠名单凹槽的下亮边作分隔，不再重复画分隔线（避免穿过上移后的文字）

  end)  -- pcall 装饰段结束
  if not okDecor then
    -- 装饰失败也要有一层纯色底，避免透明窗口
    local fb = book:CreateTexture(nil, "BACKGROUND")
    fb:SetAllPoints(book)
    pcall(function()
      fb:SetTexture("Interface\\Buttons\\WHITE8X8")
      fb:SetVertexColor(0.05, 0.07, 0.10, 0.96)
    end)
  end

  titleText = book:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleText:SetPoint("TOP", book, "TOP", 0, -18)
  titleText:SetTextColor(1, 0.82, 0, 1)   -- 与按钮文字同款金黄

  local close = CreateFrame("Button", nil, book, "UIPanelButtonTemplate")
  close:SetSize(26, 22)
  close:SetPoint("TOPRIGHT", book, "TOPRIGHT", -10, -10)
  close:SetText("X")
  close:SetScript("OnClick", function() book:Hide() end)

  for i, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, book, "UIPanelButtonTemplate")
    -- 按钮宽度与加「自己」之前完全一致：66 宽 + 73 间距，靠加宽窗口容纳 5 个
    b:SetSize(66, 24)
    b:SetPoint("TOPLEFT", book, "TOPLEFT", 14 + (i - 1) * 73, -46)
    b:SetText(t.label)
    b:SetScript("OnClick", function()
      currentTab = t.key
      currentPage = 1
      -- 进公会页时主动请求一次名单（异步下发，GUILD_ROSTER_UPDATE 到达后再重绘）
      if t.key == "guild" and C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
      end
      if t.key == "friend" then RefreshFriendList() end
      if t.key == "alt" then pcall(ScanAlts) end
      RefreshBook()
    end)
  end

  -- 公会页搜索行（默认隐藏，只有点「公会」才显示）
  guildSearchBox = CreateFrame("EditBox", "KMailGuildSearch", book, "InputBoxTemplate")
  guildSearchBox:SetSize(258, 24)
  guildSearchBox:SetPoint("TOPLEFT", book, "TOPLEFT", 33, -76)
  guildSearchBox:SetAutoFocus(false)
  guildSearchBox:SetMaxLetters(60)
  guildSearchBox:SetFontObject("GameFontHighlight")
  local sh = guildSearchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  sh:SetText("搜索公会成员，输入关键字后点搜索")
  sh:SetPoint("LEFT", guildSearchBox, "LEFT", 6, 0)
  sh:SetTextColor(0.5, 0.5, 0.5, 1)
  guildSearchBox:SetScript("OnTextChanged", function(self)
    if sh then
      if self:GetText() == "" then sh:Show() else sh:Hide() end
    end
  end)
  guildSearchBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    guildFilter = self:GetText() or ""
    currentPage = 1
    RefreshBook()
  end)
  guildSearchBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    book:Hide()
  end)

  guildSearchBtn = CreateFrame("Button", nil, book, "UIPanelButtonTemplate")
  guildSearchBtn:SetSize(56, 24)
  guildSearchBtn:SetPoint("LEFT", guildSearchBox, "RIGHT", 4, 0)
  guildSearchBtn:SetText("搜索")
  guildSearchBtn:SetScript("OnClick", function()
    guildFilter = guildSearchBox:GetText() or ""
    currentPage = 1
    RefreshBook()
    guildSearchBox:ClearFocus()
  end)

  -- ESC 兜底：即使没进 UISpecialFrames，也能关面板（输入焦点在搜索框时由 OnEscapePressed 处理）
  book:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then self:Hide() end
  end)

  for i = 1, PAGE_SIZE do
    local b = CreateFrame("Button", nil, book, "UIPanelButtonTemplate")
    -- 名单行跟着加宽并重新居中：386 - 320 = 66，左右各 33
    b:SetSize(320, 24)
    b:SetPoint("TOPLEFT", book, "TOPLEFT", 33, -110 - (i - 1) * 26)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
      local name = self.nameValue
      if not name then return end
      if button == "RightButton" then
        if currentTab == "alt" then
          if DelAlt(name) then Msg("已移出小号名单：" .. name) end
        else
          if IsFav(name) then DelFav(name) else AddFav(name) end
        end
        RefreshBook()
      else
        UseRecipient(name)
      end
    end)
    b:SetScript("OnEnter", function(self)
      if not self.nameValue then return end
      if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local hint = "左键：填入收件人   右键：加入/移出收藏"
        if currentTab == "alt" then
          hint = "左键：填入收件人   右键：移出小号名单"
          local _, isFull = HeadOf(self.nameValue)
          if not isFull then
            hint = hint .. "\n|cffff8a80这是半名，寄信会失败；/km altscan 或换小号上线一次|r"
          end
        end
        GameTooltip:SetText(hint, 1, 1, 1)
        GameTooltip:Show()
      end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    nameButtons[i] = b
  end

  local prev = CreateFrame("Button", nil, book, "UIPanelButtonTemplate")
  prev:SetSize(70, 22)
  prev:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", 18, 14)
  prev:SetText("上一页")
  prev:SetScript("OnClick", function()
    if currentPage > 1 then currentPage = currentPage - 1; RefreshBook() end
  end)

  local nextBtn = CreateFrame("Button", nil, book, "UIPanelButtonTemplate")
  nextBtn:SetSize(70, 22)
  nextBtn:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -18, 14)
  nextBtn:SetText("下一页")
  nextBtn:SetScript("OnClick", function()
    currentPage = currentPage + 1
    RefreshBook()
  end)

  -- 底部三行整体上移、离底边框留出空间；说明文字缩短避免贴边被裁切
  pageText = book:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  pageText:SetPoint("BOTTOM", book, "BOTTOM", 0, 50)

  local tip = book:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tip:SetPoint("BOTTOM", book, "BOTTOM", 0, 74)
  tip:SetText("拖动可移动 · 右键加收藏 / 移出小号")

  book:Hide()
end

local function OpenBook()
  if not book then
    local ok, err = pcall(BuildBook)
    if not ok or not book then
      Msg("通讯录窗口创建失败：" .. tostring(err))
      return
    end
  end
  currentTab = "alt"    -- 每次打开都先落在「自己」页
  currentPage = 1
  pcall(ScanAlts)       -- 顺手补扫一次同账号角色（已扫过则直接返回）
  RefreshFriendList()   -- 打开通讯录就请求一次好友名单，不用玩家先去按 O
  RefreshBook()
  book:Show()
end

--------------------------------------------------------------------------------
-- 一键收取（照官方 OpenAllMailMixin 的安全规则，但重新实现）
--------------------------------------------------------------------------------
local function CommandPending()
  if C_Mail and type(C_Mail.IsCommandPending) == "function" then
    local ok, v = pcall(C_Mail.IsCommandPending)
    if ok then return v and true or false end
  end
  return false
end

local function FreeBagSlots()
  if C_Container and type(C_Container.CalculateTotalNumberOfFreeBagSlots) == "function" then
    local ok, v = pcall(C_Container.CalculateTotalNumberOfFreeBagSlots)
    if ok and type(v) == "number" then return v end
  end
  return nil   -- 未知则放行，靠 stall 检测兜底
end

-- 金币显示成「12金34银56铜」，不依赖 GetCoinTextureString 是否存在
local function FormatCopper(copper)
  copper = math.floor(tonumber(copper) or 0)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "金" end
  if s > 0 then out[#out + 1] = s .. "银" end
  if c > 0 or #out == 0 then out[#out + 1] = c .. "铜" end
  return table.concat(out)
end

-- forever 分支 GetInboxHeaderInfo 返回顺序（MailFrame.lua:340）：
-- 1 包裹图标 2 信纸图标 3 发件人 4 主题 5 金币 6 货到付款 7 剩余天数
-- 8 附件数 9 已读 10/11 坐标 12 是否GM 13 首附件数量 14 首附件链接
local function InboxHeader(index)
  if type(GetInboxHeaderInfo) ~= "function" then return nil end
  local ok, icon, stationery, sender, subject, money, cod, days, itemCount,
        wasRead, x, y, canReply, isGM, firstQty, firstLink = pcall(GetInboxHeaderInfo, index)
  if not ok then return nil end
  return {
    sender = sender, subject = subject, money = money or 0,
    cod = cod or 0, itemCount = itemCount or 0, isGM = isGM == true,
  }
end

-- 每轮都从第一封重新扫，不怕取件后索引漂移；邮箱最多 100 封，开销可忽略
local function FindAction()
  if type(GetInboxNumItems) ~= "function" or type(GetInboxHeaderInfo) ~= "function" then
    return nil
  end
  local n = GetInboxNumItems() or 0
  for i = 1, n do
    local h = InboxHeader(i)
    if h and not h.isGM and not (h.cod and h.cod > 0) then
      if h.money > 0 then
        return i, "money", nil, h
      end
      if h.itemCount > 0 then
        for slot = 1, MAX_ATTACHMENT_SLOT do
          local has = false
          if type(HasInboxItem) == "function" then
            local ok, v = pcall(HasInboxItem, i, slot)
            has = ok and v and true or false
          elseif type(GetInboxItem) == "function" then
            local ok, v = pcall(GetInboxItem, i, slot)
            has = ok and v ~= nil
          end
          if has then
            -- forever 的 GetInboxItem 返回：名称, ID, 图标, 数量, 品质…
            -- 第 4 个才是数量（正式服是第 3 个，不能照抄）
            local name, count
            if type(GetInboxItem) == "function" then
              local ok, n2, id, tex, cnt = pcall(GetInboxItem, i, slot)
              if ok then name, count = n2, cnt end
            end
            h.itemName = name
            h.itemQty = tonumber(count) or 1
            h.slot = slot
            return i, "item", slot, h
          end
        end
      end
    end
  end
  return nil
end

local function ReportTake(kind, h)
  local from = (h and h.sender) or "未知发件人"
  local subject = (h and h.subject) or ""
  local tail = " · 来自 " .. from
  if subject ~= "" then tail = tail .. " · 主题「" .. subject .. "」" end
  if kind == "money" then
    Msg("已收取：金币 " .. FormatCopper(h and h.money) .. tail)
  else
    local name = (h and h.itemName) or "附件"
    local qty = (h and h.itemQty) or 1
    if qty > 1 then name = name .. " ×" .. qty end
    Msg("已收取：物品 " .. name .. tail)
  end
end

local function UpdateGrabButton()
  if grabButton then grabButton:SetText(grabbing and "停止收取" or "一键收取") end
end

local function StopGrab(reason)
  if not grabbing then
    if reason then Msg(reason) end
    return
  end
  grabbing = false
  waitTimer = 0
  lastActionKey = nil
  sameCount = 0
  UpdateGrabButton()
  if reason then
    Msg(reason .. "（本次 " .. actions .. " 次 · 金币 " .. FormatCopper(totalMoney) ..
        " · 附件 " .. totalItems .. " 件）")
  end
end

local function StartGrab()
  if grabbing then StopGrab("已停止收取"); return end
  if type(GetInboxNumItems) ~= "function" then
    Msg("读不到邮箱接口，插件可能未正确加载；输入 /km test 自检")
    return
  end
  if not mailOpen then
    Msg("提示：没检测到邮箱窗口；命令仍会尝试收取，没反应就先打开邮箱")
  end
  actions = 0
  totalMoney = 0
  totalItems = 0
  waitTimer = 0
  lastActionKey = nil
  sameCount = 0
  grabbing = true
  UpdateGrabButton()
  Msg("开始收取：跳过货到付款与 GM 来信，绝不删信")
end

local function GrabStep(dt)
  if not grabbing then return end
  -- 这里不强行检查 mailOpen：邮箱窗口万一没被检测到，命令模式仍应可用。
  -- 真正的停止交给 MAIL_CLOSED 事件、用户手动停止与 stall 保护。
  if waitTimer > 0 then waitTimer = waitTimer - dt; return end
  if CommandPending() then waitTimer = RETRIEVE_DELAY; return end

  local slots = FreeBagSlots()
  if slots and slots == 0 then StopGrab("背包已满，清包后再收"); return end

  local idx, kind, slot, h = FindAction()
  if not idx then
    StopGrab(actions > 0 and "收取完毕" or "没有可收取的邮件")
    return
  end

  local key = idx .. ":" .. kind .. ":" .. tostring(slot)
  if key == lastActionKey then
    sameCount = sameCount + 1
    if sameCount >= MAX_STALL then
      StopGrab("同一封邮件反复无进展，已停下（多半是背包满或服务器拒绝）")
      return
    end
  else
    sameCount = 0
    lastActionKey = key
  end

  local ok
  if kind == "money" then
    ok = pcall(TakeInboxMoney, idx)
  else
    ok = pcall(TakeInboxItem, idx, slot)
  end
  if not ok then StopGrab("调用收取接口失败，已停下"); return end

  -- 钱/物品在被取走前就从邮件头取好明细，取走后再读会拿不到
  ReportTake(kind, h)
  if kind == "money" then
    totalMoney = totalMoney + ((h and h.money) or 0)
  else
    totalItems = totalItems + ((h and h.itemQty) or 1)
  end
  actions = actions + 1
  waitTimer = RETRIEVE_DELAY
end

--------------------------------------------------------------------------------
-- 邮箱工具条：独立浮层 + 定时轮询，不依赖 MAIL_SHOW 事件的时机
--------------------------------------------------------------------------------
-- 官方 MailFrame.lua 用 RegisterPlayerInteraction(showFunc = MailFrame_Show) 显示窗口，
-- MailFrame 自己注册的事件里没有 MAIL_SHOW。旧版只在 MAIL_SHOW 时挂按钮，
-- 一旦事件没派发、或派发时 MailFrame 还没建好，按钮就永远不出现。
-- 现在：工具条是 UIParent 上的独立浮层（不会被系统 UI 层盖住），
-- 由 OnUpdate 每 0.4 秒看一次 MailFrame:IsShown() 来决定显示/隐藏。
local function BuildBar()
  -- 上次创建到一半失败时，直接复用已有框，避免重复占用全局名
  if _G["KMailBar"] then return _G["KMailBar"] end
  local f = CreateFrame("Frame", "KMailBar", UIParent)
  f:SetSize(232, 36)
  f:SetFrameStrata("DIALOG")
  f:SetFrameLevel(100)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  -- 工具条美化：与通讯录面板同款金边浮雕框（232×36 小尺寸适配）
  local okBarDecor = pcall(function()
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local function solid(tex, r, g, b, a)
      tex:SetTexture(WHITE)
      tex:SetVertexColor(r, g, b, a or 1)
    end
    local function box(sub, x1, y1, x2, y2, r, g, b, a)
      local t = f:CreateTexture(nil, "BACKGROUND", nil, sub)
      t:SetPoint("TOPLEFT", f, "TOPLEFT", x1, y1)
      t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", x2, y2)
      solid(t, r, g, b, a)
    end
    box(1, 0, 0, 0, 0, 0.03, 0.03, 0.03, 1)      -- 外黑底
    box(2, 1, -1, -1, 1, 0.85, 0.74, 0.40, 1)    -- 亮金高光
    box(3, 2, -2, -2, 2, 0.46, 0.37, 0.16, 1)    -- 主金
    box(4, 3, -3, -3, 3, 0.02, 0.02, 0.02, 1)    -- 内容内阴影
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, 5)
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    solid(bg, 0.05, 0.07, 0.10, 0.95)
  end)
  -- 装饰失败兜底：至少保留一层深色底
  if not okBarDecor then
    local fb = f:CreateTexture(nil, "BACKGROUND")
    fb:SetAllPoints(f)
    pcall(function()
      fb:SetTexture("Interface\\Buttons\\WHITE8X8")
      fb:SetVertexColor(0.05, 0.07, 0.10, 0.92)
    end)
  end

  grabButton = CreateFrame("Button", "KMailGrabButton", f, "UIPanelButtonTemplate")
  grabButton:SetSize(106, 24)
  grabButton:SetPoint("LEFT", f, "LEFT", 6, 0)
  grabButton:SetText("一键收取")
  grabButton:SetScript("OnClick", function()
    if grabbing then StopGrab("已手动停止") else StartGrab() end
  end)

  bookButton = CreateFrame("Button", "KMailBookButton", f, "UIPanelButtonTemplate")
  bookButton:SetSize(106, 24)
  bookButton:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  bookButton:SetText("通讯录")
  bookButton:SetScript("OnClick", function() OpenBook() end)

  f:Hide()
  return f
end

local function MailFrameState()
  -- 帧在不同客户端里可能是 table，也可能是 userdata，一律包 pcall 探测
  local ok, exists, shown = pcall(function()
    if not MailFrame or type(MailFrame.IsShown) ~= "function" then
      return false, false
    end
    return true, MailFrame:IsShown() and true or false
  end)
  if not ok then return false, false end
  return exists, shown
end

local function TryAttach()
  if not barBuilt then
    local ok, f = pcall(BuildBar)
    if not ok or not f then
      if not apiWarned then
        apiWarned = true
        Msg("工具条创建失败：" .. tostring(f) .. "；仍可用 /km 命令操作")
      end
      return
    end
    bar = f
    barBuilt = true
  end

  local exists, shown = MailFrameState()
  -- 只在锚点变化时重新定位，否则玩家拖过工具条后会被每 0.4 秒拉回原位
  local wantAnchor = exists and "mail" or "screen"
  if barAnchor ~= wantAnchor then
    bar:ClearAllPoints()
    if exists then
      -- 居中贴在邮箱窗口上沿外侧，跟着窗口走，又不嵌进系统 UI 层里
      bar:SetPoint("BOTTOM", MailFrame, "TOP", 0, 6)
    else
      bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
    barAnchor = wantAnchor
  end

  mailOpen = shown
  if shown or barForced then bar:Show() else bar:Hide() end
end

--------------------------------------------------------------------------------
-- 发邮件：添加附件时自动填标题「邮寄XX等物品」
--   官方 SendMailFrame_Update 在附件增减时调用，且其自带 C.O.D. 逻辑会填纯物品名；
--   我们挂在它后面，把空标题（或自动填出来的旧值）改成统一格式。
--   玩家手写的其它标题一律不碰。
--------------------------------------------------------------------------------
local function AutoFillSendSubject()
  -- 只在发信页显示时处理；用 pcall 包住，任何接口缺失都不影响收信主功能
  local ok = pcall(function()
    if not (SendMailFrame and SendMailFrame:IsShown()) then return end
    local box = SendMailSubjectEditBox
    if not (box and box.GetText and box.SetText) then return end
    if type(HasSendMailItem) ~= "function" or type(GetSendMailItem) ~= "function" then return end

    -- 取第一个附件的物品名（GetSendMailItem 第 1 个返回值 = 物品名）
    local itemName
    local maxSend = ATTACHMENTS_MAX_SEND or 12
    for i = 1, maxSend do
      if HasSendMailItem(i) then
        local n = GetSendMailItem(i)
        if n and n ~= "" then itemName = n end
        break
      end
    end

    local cur = box:GetText() or ""
    if not itemName then
      -- 附件清空了：只清掉我们自己填过的标题，不动玩家手输
      if lastAutoSubject and cur == lastAutoSubject then
        box:SetText("")
        lastAutoSubject = nil
      end
      return
    end

    local want = "邮寄" .. itemName .. "等物品"
    -- 官方 C.O.D. 自动填的纯物品名存在 previousItem，一并视为「可覆盖的自动值」
    local officialAuto = SendMailFrame.previousItem
    if cur == "" or cur == lastAutoSubject or (officialAuto and officialAuto ~= "" and cur == officialAuto) then
      if cur ~= want then box:SetText(want) end
      lastAutoSubject = want
    end
  end)
  if not ok then lastAutoSubject = nil end
end

-- 把钩子挂到官方发信更新函数；Blizzard_MailFrame 可能按需加载，故可在轮询里反复尝试
local function InstallSubjectHook()
  if subjectHooked then return end
  if type(hooksecurefunc) ~= "function" then return end
  if type(SendMailFrame_Update) ~= "function" then return end
  local ok = pcall(function()
    hooksecurefunc("SendMailFrame_Update", function() AutoFillSendSubject() end)
  end)
  if ok then subjectHooked = true end
end

--------------------------------------------------------------------------------
-- 自检：把「哪些接口在，哪些不在」直接打到聊天框
--------------------------------------------------------------------------------
local function SelfTest()
  local v, b, d, toc = "?", "?", "?", "?"
  if type(GetBuildInfo) == "function" then v, b, d, toc = GetBuildInfo() end
  Msg("客户端 " .. tostring(v) .. " · build " .. tostring(b) .. " · 接口号 " .. tostring(toc))
  local checks = {
    { "GetInboxNumItems", GetInboxNumItems },
    { "GetInboxHeaderInfo", GetInboxHeaderInfo },
    { "TakeInboxMoney", TakeInboxMoney },
    { "TakeInboxItem", TakeInboxItem },
    { "HasInboxItem", HasInboxItem },
    { "C_Mail.IsCommandPending", C_Mail and C_Mail.IsCommandPending },
    { "C_Container 背包空位", C_Container and C_Container.CalculateTotalNumberOfFreeBagSlots },
    { "C_FriendList 旧式好友", C_FriendList and C_FriendList.GetFriendInfoByIndex },
    { "C_FriendList.ShowFriends 刷新", C_FriendList and C_FriendList.ShowFriends },
    { "C_BattleNet 战网好友", C_BattleNet and C_BattleNet.GetFriendAccountInfo },
    { "BNGetNumFriends 战网计数", BNGetNumFriends },
    { "C_Club 公会成员", C_Club and C_Club.GetClubMembers },
    { "C_AutoComplete 同账号角色", C_AutoComplete and C_AutoComplete.GetAutoCompleteResults },
    { "NameUtil 无限服全名", NameUtil and NameUtil.FormatUnitNameForDisplay },
    { "姓分隔符常量", Constants and Constants.CharacterNameSeparatorConsts },
    { "GetGuildRosterInfo 公会(旧)", GetGuildRosterInfo },
    { "MailFrame 邮箱窗口", MailFrame },
    { "SendMailNameEditBox 收件人框", SendMailNameEditBox },
    { "KMailBar 工具条", bar },
  }
  for _, c in ipairs(checks) do
    Msg((c[2] and "|cff66bb6a√|r " or "|cffff8a80×|r ") .. c[1])
  end
  local exists, shown = MailFrameState()
  Msg("邮箱窗口：" .. (exists and "已创建" or "未创建") ..
      " · 当前显示：" .. (shown and "是" or "否") ..
      " · MAIL_SHOW 收到 " .. mailShowCount .. " 次")
  Msg("工具条：" .. (barBuilt and "已创建" or "未创建") ..
      " · 当前显示：" .. (bar and bar:IsShown() and "是" or "否") ..
      " · 锚点 " .. tostring(barAnchor) .. " · 收藏 " .. #DB.favorites .. " 人")
  RefreshFriendList()
  local friends = GetFriends()
  Msg("好友名单：旧式 " .. tostring(friendDiag.legacy) .. " · " ..
      tostring(friendDiag.bnet) .. " · 合计 " .. #friends .. " 人")
  local guild = GetGuild()
  Msg("公会名单：" .. tostring(guildDiag) .. " · 合计 " .. #guild .. " 人")
  ScanAlts(true)
  local alts = GetAlts()
  Msg("自己小号：" .. tostring(altDiag) .. " · 已知 " .. #DB.alts ..
      " 个 · 其他 " .. #alts .. " 个（/km altscan 重扫）")
  Msg("本角色全名：" .. tostring(SelfName()) .. " · 姓分隔符 \"" .. NameSep() ..
      "\" · 已清理半名 " .. altPruned .. " 个")
  Msg("名单是空的：把上面几行发我；急用可 /km alt 完整名 / /km fav 名字 手动加。看不到按钮用 /km show")
end

--------------------------------------------------------------------------------
-- 事件与斜杠命令
--------------------------------------------------------------------------------
mainFrame = CreateFrame("Frame")
mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("MAIL_SHOW")
mainFrame:RegisterEvent("MAIL_CLOSED")
mainFrame:RegisterEvent("MAIL_SEND_SUCCESS")
mainFrame:RegisterEvent("MAIL_INBOX_UPDATE")
mainFrame:RegisterEvent("FRIENDLIST_UPDATE")
mainFrame:RegisterEvent("GUILD_ROSTER_UPDATE")

mainFrame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON_NAME then InitDB(); pcall(TryAttach) end
    -- 官方邮箱 UI 可能是按需加载的，它一加载完就立刻贴一次
    if arg1 == "Blizzard_MailFrame" then pcall(TryAttach) end
  elseif event == "PLAYER_LOGIN" then
    InitDB()
    pcall(TryAttach)
    RefreshFriendList()
    RememberSelf()   -- 本角色登记进账号级名单，其他小号登录时同样会登记
  elseif event == "MAIL_SHOW" then
    mailOpen = true
    mailShowCount = mailShowCount + 1
    pcall(TryAttach)
    pcall(InstallSubjectHook)   -- 邮箱一开就挂钩，标题随附件即时更新
  elseif event == "MAIL_CLOSED" then
    mailOpen = false
    lastAutoSubject = nil
    if grabbing then StopGrab("邮箱已关闭") end
    if book then book:Hide() end
    if bar and not barForced then bar:Hide() end
  elseif event == "MAIL_SEND_SUCCESS" then
    lastAutoSubject = nil
    if SendMailNameEditBox and SendMailNameEditBox.GetText then
      local name = SendMailNameEditBox:GetText()
      if name and name ~= "" then AddRecent(name) end
    end
  elseif event == "MAIL_INBOX_UPDATE" then
    -- 服务器来信数变了（例如批量收取过程中有人寄信），下轮会重新全量扫描，无需额外处理
  elseif event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
    -- ShowFriends() / GuildRoster() 之后服务器下发名单，此时重绘对应的页
    local want = (event == "FRIENDLIST_UPDATE") and "friend" or "guild"
    if book and book.IsShown and book:IsShown() and currentTab == want then
      pcall(RefreshBook)
    end
  end
end)

mainFrame:SetScript("OnUpdate", function(self, dt)
  GrabStep(dt)
  -- 登录后 3 秒扫一次同账号角色，此时角色数据已就绪
  if not loginScanDone then
    loginScanTimer = loginScanTimer + dt
    if loginScanTimer >= 3 then
      loginScanDone = true
      pcall(ScanAlts)
    end
  end
  -- 不依赖 MAIL_SHOW：无限服邮箱窗口由 PlayerInteractionManager 显示，
  -- 定时看 MailFrame:IsShown() 最可靠，0.4 秒一次，开销可忽略
  attachTimer = attachTimer + dt
  if attachTimer >= 0.4 then
    attachTimer = 0
    pcall(TryAttach)
    -- 自动填标题：第一次挂钩子 + 轮询兜底（钩子没装上时仍能在编辑框打开时生效）
    pcall(InstallSubjectHook)
    if mailOpen then pcall(AutoFillSendSubject) end
  end
end)

local function Help()
  Msg("命令一览：")
  Msg("/km             打开通讯录（收藏 / 好友 / 公会 / 最近 / 自己）")
  Msg("/km help        显示这份帮助")
  Msg("/km get         一键收取全部金币与附件（不删信）")
  Msg("/km stop        停止收取")
  Msg("/km fav 名字    收藏某人；不带名字则收藏当前收件人")
  Msg("/km unfav 名字  取消收藏")
  Msg("/km alt 名-姓   手动把小号加入「自己」名单（要写完整全名）；不带名字则打开该页")
  Msg("/km unalt 名字  把名字移出小号名单")
  Msg("/km altscan     重新扫描同账号角色")
  Msg("/km show        强制显示工具条；/km hide 恢复自动跟随邮箱")
  Msg("/km test        接口自检，排错第一步")
  Msg("发信加了附件会自动把空标题填成「邮寄XX等物品」，手写了标题则不覆盖")
end

SLASH_KMAIL1 = "/km"
SLASH_KMAIL2 = "/kmail"
SlashCmdList["KMAIL"] = function(msg)
  InitDB()
  msg = msg or ""
  local cmd, rest = msg:match("^(%S+)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  rest = rest or ""

  if cmd == "help" or cmd == "?" then
    Help()
  elseif cmd == "" then
    OpenBook()
  elseif cmd == "get" or cmd == "收" then
    StartGrab()
  elseif cmd == "stop" or cmd == "停" then
    StopGrab("已手动停止")
  elseif cmd == "book" or cmd == "list" or cmd == "通讯录" then
    OpenBook()
  elseif cmd == "fav" or cmd == "收藏" then
    if rest == "" then
      if SendMailNameEditBox and SendMailNameEditBox.GetText then
        rest = SendMailNameEditBox:GetText() or ""
      end
    end
    AddFav(rest)
  elseif cmd == "unfav" or cmd == "取消收藏" then
    DelFav(rest)
  elseif cmd == "alt" or cmd == "小号" then
    if rest == "" then
      currentTab = "alt"
      currentPage = 1
      OpenBook()
    else
      local full = ResolveComplete(rest)
      if AddAlt(full) then
        local _, isFull = HeadOf(full)
        Msg("已加入小号名单：" .. full ..
            (isFull and "" or "（注意：只有半名，寄信会失败，请填完整「名-姓」）"))
      else
        Msg("名单里已有这个名字，或名字为空：" .. rest)
      end
    end
  elseif cmd == "unalt" or cmd == "删小号" then
    if DelAlt(rest) then
      Msg("已移出小号名单：" .. rest)
    else
      Msg("小号名单里没有：" .. rest)
    end
  elseif cmd == "altscan" or cmd == "扫小号" then
    ScanAlts(true)
    Msg("小号扫描：" .. tostring(altDiag) .. " · 已知 " .. #DB.alts ..
        " 个角色 · 清理半名 " .. altPruned .. " 个")
    if book and book.IsShown and book:IsShown() and currentTab == "alt" then
      pcall(RefreshBook)
    end
  elseif cmd == "show" or cmd == "显示" then
    barForced = true
    pcall(TryAttach)
    Msg("工具条已强制显示（可拖动）；输入 /km hide 恢复自动跟随邮箱")
  elseif cmd == "hide" or cmd == "隐藏" then
    barForced = false
    if bar then bar:Hide() end
    Msg("已恢复自动模式：打开邮箱时自动出现")
  elseif cmd == "test" or cmd == "自检" then
    SelfTest()
  else
    Msg("未知命令：" .. cmd .. "  输入 /km help 查看")
  end
end
