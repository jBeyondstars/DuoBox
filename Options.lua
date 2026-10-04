--------------------------------------------------------------------------------
-- DuoBox options panel: every /duo setting and action without typing commands.
-- Opened by /duo, the minimap button or Options > AddOns > DuoBox.
-- Settings go through ns.Set (same side effects as the commands), actions
-- through ns.Command (same code and chat feedback as the commands).
--------------------------------------------------------------------------------

local _, ns = ...

local function DB() return ns.GetDB() end
local Print = ns.Print

local WIDTH, HEIGHT = 500, 420
local COL2 = 240 -- x of the second column, inside a page

local panel = CreateFrame("Frame", "DuoBoxOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(WIDTH, HEIGHT)
panel:SetPoint("CENTER")
panel:SetFrameStrata("DIALOG")
panel:SetToplevel(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetClampedToScreen(true)
if panel.SetBackdrop then
	panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
end
panel:Hide()
tinsert(UISpecialFrames, "DuoBoxOptions") -- Escape closes the panel

panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panel.title:SetPoint("TOP", 0, -16)
panel.title:SetText("DuoBox")

local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local controls = {}   -- every widget with a Refresh method
local refreshing = false

local function Tooltip(frame, title, text)
	if not text then return end
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function Header(page, x, y, text)
	local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function Note(page, x, y, width)
	local fs = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetWidth(width)
	fs:SetJustifyH("LEFT")
	return fs
end

local function CheckBox(page, x, y, label, tip)
	local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", x, y)
	local fs = cb.Text or cb.text or cb:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject("GameFontHighlight")
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
	fs:SetText(label)
	cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 4), 0, 0) -- the label is clickable too
	cb.label = fs
	Tooltip(cb, label, tip)
	return cb
end

-- Checkbox bound to a boolean setting
local function Toggle(page, x, y, key, label, tip)
	local cb = CheckBox(page, x, y, label, tip)
	cb:SetScript("OnClick", function(self) ns.Set(key, self:GetChecked() and true or false) end)
	cb.Refresh = function(self) self:SetChecked(DB()[key] and true or false) end
	controls[#controls + 1] = cb
	return cb
end

-- Slider bound to a number setting
local function Slider(page, x, y, key, label, minV, maxV, step, fmt, tip)
	local s = CreateFrame("Slider", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(200, 17)
	s:SetPoint("TOPLEFT", x + 4, y - 18)
	s:SetHitRectInsets(0, 0, -6, -6)
	if s.SetBackdrop then
		s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
			tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
	end
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
	s.title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	s.title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
	s.title:SetText(label)
	s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	s.value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3)
	s:SetScript("OnValueChanged", function(self, v)
		v = tonumber(("%.4f"):format(math.floor(v / step + 0.5) * step))
		self.value:SetText(fmt:format(v))
		if not refreshing and DB()[key] ~= v then ns.Set(key, v) end
	end)
	Tooltip(s, label, tip)
	s.Refresh = function(self)
		local v = DB()[key] or minV
		self:SetValue(v)
		self.value:SetText(fmt:format(v))
	end
	controls[#controls + 1] = s
	return s
end

local function Button(page, x, y, width, label, onClick, tip)
	local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	Tooltip(b, label, tip)
	return b
end

-- Runs a /duo command, then refreshes the panel (done by the slash handler)
local function Run(cmd) return function() ns.Command(cmd) end end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

local pages, tabs = {}, {}

local function SelectTab(i)
	for n, page in ipairs(pages) do
		page:SetShown(n == i)
		if n == i then tabs[n]:LockHighlight() else tabs[n]:UnlockHighlight() end
	end
	DB().optionsTab = i
end

local function NewPage(label)
	local i = #pages + 1
	local page = CreateFrame("Frame", nil, panel)
	page:SetPoint("TOPLEFT", 22, -78)
	page:SetPoint("BOTTOMRIGHT", -22, 18)
	page:Hide()
	pages[i] = page
	local tabW = (WIDTH - 44 - 4 * 4) / 5
	local tab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	tab:SetSize(tabW, 24)
	tab:SetPoint("TOPLEFT", 22 + (i - 1) * (tabW + 4), -42)
	tab:SetText(label)
	tab:SetScript("OnClick", function() SelectTab(i) end)
	tabs[i] = tab
	return page
end

--------------------------------------------------------------------------------
-- Page 1: General (partner, role, actions)
--------------------------------------------------------------------------------

local general = NewPage("General")

Header(general, 0, 0, "Partenaire")
local partnerState = Note(general, 0, -18, 450)

local partnerEdit = CreateFrame("EditBox", nil, general, "InputBoxTemplate")
partnerEdit:SetSize(150, 20)
partnerEdit:SetPoint("TOPLEFT", 6, -38)
partnerEdit:SetAutoFocus(false)
partnerEdit:SetMaxLetters(48)

local function ApplyPartner(name)
	name = (name or ""):match("^%s*(.-)%s*$")
	if name == "" then
		ns.Set("partner", nil)
		Print("partenaire efface (n'importe quel membre du groupe sera utilise).")
		ns.RefreshOptions()
	else
		ns.Command("partner " .. name)
	end
end

partnerEdit:SetScript("OnEnterPressed", function(self) ApplyPartner(self:GetText()); self:ClearFocus() end)
partnerEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns.RefreshOptions() end)
partnerEdit.Refresh = function(self) if not self:HasFocus() then self:SetText(DB().partner or "") end end
controls[#controls + 1] = partnerEdit

Button(general, 166, -37, 60, "OK", function() ApplyPartner(partnerEdit:GetText()); partnerEdit:ClearFocus() end,
	"Enregistre le nom saisi (a faire sur les 2 persos). Un nom vide efface le partenaire.")

local function SecretFree(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

Button(general, 232, -37, 110, "Ma cible", function()
	local name
	if UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
		name = SecretFree(UnitName("target"))
	elseif GetNumGroupMembers() == 2 then
		name = SecretFree(UnitName("party1"))
	end
	if name then
		ApplyPartner(name)
	else
		Print("cible le perso partenaire (ou groupe-toi avec lui) puis reessaie.")
	end
end, "Prend le joueur cible, ou le seul autre membre du groupe.")

Header(general, 0, -72, "Role")
local roleState = Note(general, 250, -74, 200)
local roleButtons = {}
for i, r in ipairs({ { nil, "Auto (pretre = heal)" }, { "heal", "Heal" }, { "dps", "DPS" } }) do
	local value = r[1]
	local cb = CheckBox(general, ({ 0, 160, 240 })[i], -90, r[2],
		value and ("Force le role " .. r[2] .. ".") or "Le pretre est heal, les autres classes dps.")
	cb:SetScript("OnClick", function() ns.Set("role", value); ns.RefreshOptions() end)
	cb.Refresh = function(self) self:SetChecked(DB().role == value) end
	controls[#controls + 1] = cb
	roleButtons[i] = cb
end

Header(general, 0, -120, "Meneur (le main, l'autre le suit)")
local leaderState = Note(general, 250, -122, 200)
for i, r in ipairs({ { nil, "Auto (le dps mene)" }, { "heal", "Heal" }, { "dps", "DPS" } }) do
	local value = r[1]
	local cb = CheckBox(general, ({ 0, 160, 240 })[i], -136, r[2],
		(value and ("Le " .. r[2] .. " mene, l'autre le suit.") or "Le dps (chasseur) mene, le heal (pretre) le suit.")
		.. " Envoye au partenaire s'il est dans le groupe.")
	cb:SetScript("OnClick", function() ns.Set("leader", value); ns.RefreshOptions() end)
	cb.Refresh = function(self) self:SetChecked(DB().leader == value) end
	controls[#controls + 1] = cb
end

Header(general, 0, -170, "Actions")
local BW = 222
Button(general, 0, -190, BW, "Creer / maj les macros", Run("macros"),
	"Cree les macros D-xxx de ta classe (onglet perso de /macro). Hors combat.")
Button(general, COL2 - 6, -190, BW, "Raccourcis clavier", function()
	ns.Command("keys")
	local keys = _G.DuoBoxKeys
	if keys and keys:IsShown() then
		keys:ClearAllPoints()
		keys:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
		keys:Raise()
	end
end, "Associe une touche a chaque bouton de la barre.")
Button(general, 0, -216, BW, "Tester l'alerte", Run("test"),
	"Joue l'alerte (son + clignotement). Passe sur l'autre fenetre pour verifier qu'elle sonne en fond.")
Button(general, COL2 - 6, -216, BW, "Appliquer les CVars", Run("cvars"),
	"Son en arriere-plan (pour entendre les alertes) et auto-loot.")
Button(general, 0, -242, BW, "Inviter le partenaire", function() DuoBoxBtnInvite:Click() end,
	"Invite le partenaire dans le groupe.")
Button(general, COL2 - 6, -242, BW, "Comparer les quetes", function() DuoBoxBtnQuests:Click() end,
	"Partage tes quetes qui manquent au partenaire.")
local moveBtn = Button(general, 0, -268, BW, "", Run("move"),
	"Affiche la barre de cast et l'orientation pour les deplacer (coin bas-droit : taille). Recliquer pour enregistrer.")
moveBtn.Refresh = function(self)
	self:SetText(ns.IsMoveMode() and "|cffffd040Terminer le deplacement|r" or "Deplacer cast / orientation")
end
controls[#controls + 1] = moveBtn
Button(general, COL2 - 6, -268, BW, "Afficher l'etat dans le chat", Run("status"),
	"Resume des reglages et de l'unite du partenaire detectee.")

Note(general, 0, -300, 450):SetText("|cff999999Toutes ces options existent aussi en commande : /duo help.|r")

--------------------------------------------------------------------------------
-- Page 2: Alerts
--------------------------------------------------------------------------------

local alerts = NewPage("Alertes")

Header(alerts, 0, 0, "Signal")
Toggle(alerts, 0, -18, "sound", "Son", "Joue un son a chaque alerte (meme fenetre en fond, voir les CVars).")
Toggle(alerts, 0, -42, "flash", "Clignoter (barre des taches)", "Fait clignoter l'icone de la fenetre WoW.")

Header(alerts, 0, -80, "Quetes")
Toggle(alerts, 0, -98, "turnin", "Quete rendue par le partenaire",
	"Alerte quand le partenaire rend une quete qui est encore dans ton journal.")
Toggle(alerts, 0, -122, "acceptAlert", "Quete pas prise par le suiveur",
	"Alerte quand le perso qui suit n'a toujours pas une quete 10 s apres que le meneur l'a prise.")
Toggle(alerts, 0, -146, "lootAlert", "Objet de quete non ramasse",
	"Alerte quand le partenaire a ramasse un objet de quete unique (0/1) que tu n'as pas.")

Button(alerts, 0, -188, 200, "Tester l'alerte", Run("test"))

Header(alerts, COL2, 0, "Seuils")
Slider(alerts, COL2, -22, "hpPartner", "PV du partenaire", 5, 95, 5, "%d%%",
	"Alerte quand la vie du partenaire passe sous ce seuil.")
Slider(alerts, COL2, -70, "hpPet", "PV du familier (cote pretre)", 5, 95, 5, "%d%%",
	"Alerte du pretre quand la vie du familier du chasseur passe sous ce seuil.")
Slider(alerts, COL2, -118, "manaPartner", "Mana du partenaire (cote dps)", 5, 95, 5, "%d%%",
	"Alerte du chasseur quand le mana du pretre passe sous ce seuil.")

--------------------------------------------------------------------------------
-- Page 3: Automation
--------------------------------------------------------------------------------

local auto = NewPage("Automatisme")

Header(auto, 0, 0, "Venant du partenaire")
Toggle(auto, 0, -18, "autoInvite", "Accepter ses invitations de groupe")
Toggle(auto, 0, -42, "autoQuest", "Accepter les quetes qu'il partage")
Toggle(auto, 0, -66, "autoRez", "Accepter ses resurrections")

Header(auto, 0, -104, "Quetes")
Toggle(auto, 0, -122, "autoShare", "Partager automatiquement les quetes acceptees",
	"Chaque quete prise est partagee au partenaire.")
Toggle(auto, 0, -146, "autoNpc", "Bouton Parler / D-Talk : accepter et rendre les quetes du PNJ",
	"Apres le bouton Parler (ou la macro D-Talk), DuoBox accepte et rend les quetes du PNJ pendant 20 s.")

--------------------------------------------------------------------------------
-- Page 4: Display
--------------------------------------------------------------------------------

local display = NewPage("Affichage")

Header(display, 0, 0, "Cadres")
Toggle(display, 0, -18, "frame", "Cadre de statut du partenaire", "PV, mana et follow du partenaire.")
Toggle(display, 0, -42, "bar", "Barre de boutons", "Follow / Cibler / Echange... (Maj + glisser pour la deplacer).")
Toggle(display, 0, -66, "castbar", "Barre de cast du suiveur", "Les sorts et erreurs du perso qui suit, affiches chez le meneur.")
Toggle(display, 0, -90, "minimap", "Bouton de la minimap", "Clic : ce panneau. Clic droit : raccourcis. Glisser : deplacer.")
Slider(display, 0, -122, "barScale", "Taille de la barre", 0.5, 2, 0.05, "%.2f")
if ns.FEATURES.combatMonitor then
	Toggle(display, 0, -166, "combatMonitor", "Signal des sorties de combat",
		"Signal visuel lu par VoiceKeys/combat_monitor.py (chasseur uniquement).")
end

Header(display, COL2, 0, "Orientation du pretre")
Toggle(display, COL2, -18, "facing", "Indicateur d'orientation", "Indique au chasseur si le pretre fait face a la cible (quand le pretre suit).")
Toggle(display, COL2, -42, "facingInvert", "Inverser gauche / droite", "Si la direction indiquee est fausse.")
Slider(display, COL2, -74, "facingDist", "Distance chasseur - cible", 5, 40, 1, "%d m",
	"Distance estimee pour calculer l'angle quand le familier n'est pas au contact.")
Button(display, COL2, -118, 200, "Diagnostic orientation", Run("facing debug"),
	"Affiche dans le chat les valeurs que le client peut lire.")
local moveBtn2 = Button(display, COL2, -144, 200, "", Run("move"),
	"Affiche la barre de cast et l'orientation pour les deplacer. Recliquer pour enregistrer.")
moveBtn2.Refresh = moveBtn.Refresh
controls[#controls + 1] = moveBtn2

Header(display, 0, -200, "Detections de metiers sur la minimap")
Toggle(display, 0, -218, "tracking", "Partager les detections (experimental)",
	"A activer sur les deux persos. Lit les infobulles des vrais points jaunes puis affiche les reperes chez le partenaire. "
	.. "GatherLite est requis pour scanner : ses emplacements connus guident le scan. "
	.. "La minimap est deplacee brievement sous le curseur toutes les 5 s ; elle peut clignoter. "
	.. "Pause en combat et pendant la rotation de camera. Les reperes expirent apres 15 s sans confirmation.")
local trackingState = Note(display, 0, -250, 450)
Button(display, 0, -290, 200, "Scanner maintenant", Run("tracking scan"),
	"Lance un passage de verification si une detection de minerais ou de plantes est active.")

--------------------------------------------------------------------------------
-- Page 5: RestedXP
--------------------------------------------------------------------------------

local rxpPage = NewPage("RestedXP")

Header(rxpPage, 0, 0, "Objectifs du partenaire dans le guide")
Toggle(rxpPage, 0, -18, "rxp", "Afficher la progression du partenaire",
	"Chaque objectif du guide RestedXP montre aussi la progression du partenaire.")
Toggle(rxpPage, 0, -42, "rxpHold", "Attendre que le partenaire ait aussi fini",
	"Un objectif n'est valide que lorsque les deux persos l'ont termine.")
Button(rxpPage, 0, -80, 200, "Resynchroniser", Run("rxp sync"), "Renvoie les journaux de quetes des deux persos.")
local rxpState = Note(rxpPage, 0, -114, 450)

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function RefreshLive()
	local db = DB()
	local unit = ns.PartnerUnit()
	local name = unit and SecretFree(UnitName(unit))
	if not db.partner then
		partnerState:SetText("|cffff9933Aucun partenaire defini|r : saisis son nom (sans le royaume).")
	elseif name then
		partnerState:SetText(("|cff40ff40%s est dans le groupe|r (%s)."):format(name, unit))
	else
		partnerState:SetText(("|cffffd040%s n'est pas dans le groupe.|r"):format(db.partner))
	end
	roleState:SetText(("Role actuel : |cffffd040%s|r"):format(ns.Role()))
	leaderState:SetText(ns.IsLeader() and "|cff40ff40Tu menes|r" or "|cffffd040Tu suis le partenaire|r")
	rxpState:SetText(ns.RXPState and ("Etat : " .. ns.RXPState()) or "")
	trackingState:SetText(ns.TrackingState and ns.TrackingState() or "")
end

function ns.RefreshOptions()
	if not panel:IsShown() then return end
	refreshing = true
	for _, c in ipairs(controls) do c:Refresh() end
	refreshing = false
	RefreshLive()
end

local elapsed = 0
panel:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.5 then return end
	elapsed = 0
	RefreshLive()
end)

panel:SetScript("OnShow", function()
	SelectTab(DB().optionsTab or 1)
	ns.RefreshOptions()
end)

function ns.ToggleOptions()
	panel:SetShown(not panel:IsShown())
end

--------------------------------------------------------------------------------
-- Minimap button (left click: panel, right click: key bindings, drag: move)
--------------------------------------------------------------------------------

local mm = CreateFrame("Button", "DuoBoxMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local mmBg = mm:CreateTexture(nil, "BACKGROUND")
mmBg:SetSize(20, 20)
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBg:SetPoint("TOPLEFT", 7, -5)
local mmIcon = mm:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(17, 17)
mmIcon:SetTexture("Interface\\Icons\\Spell_Holy_PrayerOfHealing02")
mmIcon:SetPoint("TOPLEFT", 7, -6)
local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(53, 53)
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetPoint("TOPLEFT")
mm:Hide()

local function PlaceMinimapButton()
	local angle = math.rad(DB().minimapAngle or 200)
	local x, y = math.cos(angle), math.sin(angle)
	local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
	if GetMinimapShape and GetMinimapShape() == "SQUARE" then
		x = math.max(-w, math.min(x * w * 1.42, w))
		y = math.max(-h, math.min(y * h * 1.42, h))
	else
		x, y = x * w, y * h
	end
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function ns.UpdateMinimapButton()
	PlaceMinimapButton()
	mm:SetShown(DB().minimap)
end

local function DragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	DB().minimapAngle = math.floor(math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360)
	PlaceMinimapButton()
end

mm:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", DragUpdate); GameTooltip:Hide() end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnClick", function(_, button)
	if button == "RightButton" then ns.Command("keys") else ns.ToggleOptions() end
end)
mm:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("DuoBox")
	GameTooltip:AddLine("Clic : options et actions", 1, 1, 1)
	GameTooltip:AddLine("Clic droit : raccourcis clavier", 1, 1, 1)
	GameTooltip:AddLine("Glisser : deplacer le bouton", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end)
mm:SetScript("OnLeave", GameTooltip_Hide)

--------------------------------------------------------------------------------
-- Entry in the game options (Options > AddOns > DuoBox): opens the panel
--------------------------------------------------------------------------------

local function RegisterGameOptions()
	local canvas = CreateFrame("Frame")
	canvas.name = "DuoBox"
	local t = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText("DuoBox")
	local open = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
	open:SetSize(220, 24)
	open:SetPoint("TOPLEFT", 16, -48)
	open:SetText("Ouvrir le panneau DuoBox")
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
		if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
		panel:Show()
	end)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(canvas, "DuoBox"))
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(canvas)
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
	ns.UpdateMinimapButton()
	pcall(RegisterGameOptions)
end)
