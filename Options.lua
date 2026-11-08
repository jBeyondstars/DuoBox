--------------------------------------------------------------------------------
-- DuoBox options panel: every /duo setting and action without typing commands.
-- Opened by /duo, the minimap button or Options > AddOns > DuoBox.
-- Settings go through ns.Set (same side effects as the commands), actions
-- through ns.Command (same code and chat feedback as the commands).
--------------------------------------------------------------------------------

local _, ns = ...

local function DB() return ns.GetDB() end
local Print = ns.Print

local WIDTH, HEIGHT = 620, 540 -- 620 wide: 7 tabs; 540 high: the warrior panel's icon list at the bottom of DuoRelay
local TABS = 7
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
	local tabW = (WIDTH - 44 - 4 * (TABS - 1)) / TABS
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
	if SecretFree(UnitIsPlayer("target")) and not SecretFree(UnitIsUnit("target", "player")) then
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
		(value and ("Le " .. r[2] .. " mene, l'autre le suit.") or "Le dps (chasseur, guerrier) mene, le heal (pretre) le suit.")
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
	"Affiche la barre de cast, l'orientation et les voyants pour les deplacer (coin bas-droit : taille). Recliquer pour enregistrer.")
moveBtn.Refresh = function(self)
	self:SetText(ns.IsMoveMode() and "|cffffd040Terminer le deplacement|r" or "Deplacer cast / orientation / voyants")
end
controls[#controls + 1] = moveBtn
Button(general, COL2 - 6, -268, BW, "Afficher l'etat dans le chat", Run("status"),
	"Resume des reglages et de l'unite du partenaire detectee.")
Button(general, 0, -294, BW, "Sorts du bouton Rotation", function()
	ns.Command("rotation")
	local rotation = _G.DuoBoxRotation
	if rotation and rotation:IsShown() then
		rotation:ClearAllPoints()
		rotation:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
		rotation:Raise()
	end
end, "Choisit les sorts du bouton Rotation et leur ordre, une liste par classe (aussi clic droit sur le bouton).")

Note(general, COL2 - 6, -299, 222):SetText("|cff999999Toutes ces options existent aussi en commande : /duo help.|r")

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

Header(alerts, COL2, -176, "Voyant du guerrier")
Toggle(alerts, COL2, -194, "lightSound", "Son quand il reste rouge",
	"Optionnel, desactive par defaut. Apres 1 s de rouge, puis toutes les 3 s : un son different pour trop loin, "
	.. "mal oriente, et n'attaque pas / sans cible. Suit aussi l'option Son. /duo lightsound on|off")

-- Event light (ProcLight.lua): the partner's reactive spells, one checkbox per spell of its class
Header(alerts, 0, -236, "Voyant des evenements du partenaire")
Toggle(alerts, 0, -254, "procLight", "Afficher le voyant",
	"L'icone du sort s'affiche des qu'il s'allume chez le partenaire (Fulgurance apres une esquive, Execution "
	.. "sous 20 %...) et disparait des qu'il s'eteint : fenetre finie, sort lance, cible morte, fin du combat. "
	.. "Doree et clignotante : pret. Grise : pas assez de rage. A laisser actif sur les deux persos. "
	.. "Deplacer : bouton Deplacer (ou /duo move), coin bas-droit : taille. /duo proc on|off, "
	.. "/duo proc debug (sur le guerrier, en combat) : ce que le client repond.")
local procNote = Note(alerts, COL2, -260, 256)
local procBoxes, procRows = {}, 0
for _, list in pairs(ns.PROCS or {}) do procRows = math.max(procRows, #list) end
for i = 1, procRows do
	local cb = CheckBox(alerts, 16, -282 - (i - 1) * 24, "")
	cb:SetScript("OnClick", function(self) ns.SetProcHidden(self.id, not self:GetChecked()) end)
	cb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.label:GetText())
		GameTooltip:AddLine("Coche : le voyant s'allume pour ce sort. Decoche : ignore.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	cb:SetScript("OnLeave", GameTooltip_Hide)
	cb:Hide()
	procBoxes[i] = cb
end
local CLASS_FR = { WARRIOR = "guerrier", ROGUE = "voleur", HUNTER = "chasseur", PALADIN = "paladin",
	PRIEST = "pretre", MAGE = "mage", WARLOCK = "demoniste", DRUID = "druide", SHAMAN = "chaman" }

-- The spells of the partner's class (the partner must be in the group: its class comes from its unit)
local function RefreshProcs()
	local unit = ns.PartnerUnit()
	local name = unit and SecretFree(UnitName(unit))
	local class = unit and SecretFree((select(2, UnitClass(unit))))
	local list = class and ns.PROCS[class]
	if not unit then
		procNote:SetText("|cff999999Partenaire hors du groupe : les sorts de sa classe s'afficheront ici.|r")
	elseif not list then
		procNote:SetText(("|cff999999%s (%s) n'a pas de sort evenement connu.|r"):format(name or "Le partenaire",
			CLASS_FR[class] or "?"))
	else
		procNote:SetText(("Sorts de %s (%s) a signaler :"):format(name or "partenaire", CLASS_FR[class] or class))
	end
	for i, cb in ipairs(procBoxes) do
		local p = list and list[i]
		cb:SetShown(p ~= nil)
		if p then
			cb.id = p.id
			cb.label:SetText(("%s |cff999999(%s)|r"):format(ns.SpellNameIcon(p.id) or p.id, p.hint))
			cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 4), 0, 0)
			cb:SetChecked(not ns.ProcHidden(p.id))
		end
	end
end

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

Header(auto, 0, -184, "Touche d'interaction")
Toggle(auto, 0, -202, "interactEnemy", "La cible ennemie avant les objets et PNJ proches",
	"Quand ta cible est un ennemi vivant (ou celle du partenaire s'il combat), la touche d'interaction va sur ta cible "
	.. "(attaque, et marche jusqu'a elle avec le Click-to-Move) au lieu de l'objet ou du PNJ le plus proche. "
	.. "En combat : pendant tout le combat (le jeu refuse ce changement en plein combat). "
	.. "Ennemi mort et combat fini : elle ramasse de nouveau. /duo interact : etat. Active par defaut sur le guerrier.")

Header(auto, 0, -236, "Donjon")
Toggle(auto, 0, -254, "dungeon", "Mode donjon : les assists prennent la cible du tank",
	"Boutons d'attaque, bouton Assister, Rotation et lignes /assist des macros D-xxx prennent la cible du tank "
	.. "au lieu de celle du partenaire. Follow, Parler et les soins du pretre restent sur le partenaire. "
	.. "A activer sur les deux persos. /duo dungeon on|off")

local tankEdit = CreateFrame("EditBox", nil, auto, "InputBoxTemplate")
tankEdit:SetSize(150, 20)
tankEdit:SetPoint("TOPLEFT", 6, -282)
tankEdit:SetAutoFocus(false)
tankEdit:SetMaxLetters(48)
local function ApplyTank(name)
	name = (name or ""):match("^%s*(.-)%s*$")
	ns.Command("tank " .. (name ~= "" and name or "auto"))
end
tankEdit:SetScript("OnEnterPressed", function(self) ApplyTank(self:GetText()); self:ClearFocus() end)
tankEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns.RefreshOptions() end)
tankEdit.Refresh = function(self) if not self:HasFocus() then self:SetText(DB().tank or "") end end
Tooltip(tankEdit, "Nom du tank", "Vide (ou Auto) : le membre du groupe au role Tank (clic droit sur son portrait > Role).")
controls[#controls + 1] = tankEdit
Button(auto, 166, -281, 90, "Ma cible", function()
	if SecretFree(UnitIsPlayer("target")) then
		ApplyTank(SecretFree(UnitName("target")))
	else
		Print("cible le tank puis reessaie.")
	end
end, "Prend le joueur cible comme tank.")
Button(auto, 262, -281, 80, "Auto", function() ApplyTank("") end,
	"Le membre du groupe au role Tank (clic droit sur son portrait > Role > Tank, ou appel aux roles).")
local dungeonState = Note(auto, 0, -306, 450)

--------------------------------------------------------------------------------
-- Page 4: DuoRelay, the external two-PC tool (GUIDE.md section 7). One column:
-- the labels are long.
--------------------------------------------------------------------------------

local relay = NewPage("DuoRelay")

Header(relay, 0, 0, "DuoRelay (deux PC)")
Toggle(relay, 0, -18, "pickupRelay", "Ramassage relaye (Ctrl + clic droit)",
	"Desactive par defaut, a activer sur les deux persos, avec DuoRelay lance. Ctrl + clic droit sur un objet "
	.. "(filon, plante, objet de quete) : le partenaire ne ramasse que si son objet le plus proche porte le meme nom. "
	.. "Sinon il ne fait rien et ton ecran dit ce qu'il vise. Meme type d'objet, pas forcement le meme exemplaire. "
	.. "Hors combat seulement. Utilise la touche Ctrl+Maj+F9 chez le partenaire (GUIDE.md, section 7).")
	:HookScript("OnClick", function() if ns.RefreshPickupRelay then ns.RefreshPickupRelay() end end)
Toggle(relay, 0, -42, "relayPanel", "Panneau des sorts du guerrier",
	"Sur le pretre, desactive par defaut, avec DuoRelay lance sur les deux PC. Un clic sur une icone fait lancer "
	.. "le sort au guerrier : DuoRelay presse sa touche de barre sur le PC 2 (rien ne se passe dans ce jeu). "
	.. "Icone N = declencheur \"pixel\": N de DuoRelay.json. Fenetre ou plein ecran fenetre. "
	.. "Recharges estimees sur les icones (le jeu les cache en combat) : meme version de DuoBox sur le guerrier. "
	.. "/duo panneau sorts <liste> : changer les icones (GUIDE.md, section 7).")
Slider(relay, 0, -66, "relayPanelPerRow", "Icones par rangee (panneau guerrier)", 1, ns.RELAY_PANEL_MAX or 12, 1, "%d",
	"Nombre d'icones sur chaque rangee du panneau des sorts du guerrier : 4 avec 8 sorts = 2 rangees de 4. "
	.. "12 = une seule rangee.")
Toggle(relay, 0, -112, "relayPanelTooltip", "Infobulles des sorts (panneau guerrier)",
	"Decoche : survoler une icone du panneau n'affiche plus l'infobulle du sort. Le clic fonctionne pareil.")

Header(relay, 0, -146, "Commandes du guerrier depuis le pretre (le pretre ne les recoit jamais)")
Toggle(relay, 0, -164, "relayCamera", "Camera du guerrier : Ctrl+Z maintenu et la souris",
	"Sur le pretre, desactive par defaut, avec DuoRelay lance sur les deux PC et le relais ON. Maintenir Ctrl+Z et "
	.. "bouger la souris : la camera du guerrier tourne sur le PC 2 comme avec sa propre souris, le curseur du pretre "
	.. "reste immobile. Ctrl+Z n'arrive jamais au jeu du pretre. Un clic de souris pendant ce temps rend la souris au "
	.. "pretre (la camera du guerrier s'arrete). Ne demarre pas si un bouton de la souris est deja enfonce.")
Toggle(relay, 22, -188, "relayCameraTurn", "Le guerrier tourne avec (clic droit chez lui ; decoche : clic gauche, camera seule)",
	"Coche : DuoRelay maintient le clic droit chez le guerrier, il tourne avec sa camera (comme un clic droit glisse). "
	.. "Decoche : le clic gauche, seule la camera tourne.")
Toggle(relay, 0, -212, "relayMoves", "Deplacements du guerrier : Ctrl+Q / Ctrl+D pas chasses, Ctrl+S reculer",
	"Sur le pretre, desactive par defaut, avec DuoRelay lance sur les deux PC et le relais ON. Tant que Ctrl+Q est "
	.. "enfonce, le guerrier fait un pas chasse a gauche (Ctrl+D : a droite, Ctrl+S : il recule). Le pretre ne recoit "
	.. "jamais ces touches. Chez le guerrier : Q = Deplacement lateral gauche, S = Reculer, et la fleche droite a lier a "
	.. "Deplacement lateral droit. Touches modifiables dans DuoRelay.json (moves).")
Note(relay, 0, -240, 560):SetText("|cff999999Coche, DuoBox dessine 4 petits carres en haut a gauche de l'ecran : "
	.. "DuoRelay ne prend Ctrl+Z, Ctrl+Q, Ctrl+S et Ctrl+D au jeu du pretre que pendant qu'il les voit (relais ON, WoW au "
	.. "premier plan, fenetre ou plein ecran fenetre). Ctrl reste enfonce chez le pretre : ses macros Ctrl = soi-meme. "
	.. "GUIDE.md, section 7.|r")

-- One box per icon of the warrior's spell panel (/duo panneau sorts), 3 per row in panel order
Header(relay, 0, -300, "Icones du panneau des sorts du guerrier (decoche = masquee)")
local relayBoxes = {}
for i = 1, ns.RELAY_PANEL_MAX or 12 do
	local cb = CheckBox(relay, ((i - 1) % 3) * 165, -318 - math.floor((i - 1) / 3) * 20, "")
	cb:SetSize(20, 20)
	cb.label:SetFontObject("GameFontHighlightSmall")
	cb:SetScript("OnClick", function(self) ns.SetRelayPanelHidden(self.entry, not self:GetChecked()) end)
	cb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.name or "")
		GameTooltip:AddLine(("Coche : l'icone %d est dans le panneau. Decoche : masquee ; les autres icones "
			.. "gardent leur numero (\"pixel\" de DuoRelay.json). /duo panneau sorts : changer la liste.")
			:format(self.index or 0), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	cb:SetScript("OnLeave", GameTooltip_Hide)
	cb:Hide()
	relayBoxes[i] = cb
end
controls[#controls + 1] = { Refresh = function()
	local list = ns.RelayPanelEntries and ns.RelayPanelEntries() or {}
	for i, cb in ipairs(relayBoxes) do
		local e = list[i]
		cb:SetShown(e ~= nil)
		if e then
			cb.entry, cb.name, cb.index = e.entry, e.name, i
			cb.label:SetText(("%d |T%s:0|t %s"):format(i, e.icon or "Interface\\Icons\\INV_Misc_QuestionMark", e.name))
			cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 4), 0, 0)
			cb:SetChecked(not e.hidden)
		end
	end
end }

--------------------------------------------------------------------------------
-- Page 5: Display
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
	"Distance estimee pour calculer l'angle quand le familier n'est pas au contact. Avec un guerrier (corps a corps), 3 m sont utilises.")
Button(display, COL2, -118, 200, "Diagnostic orientation", Run("facing debug"),
	"Affiche dans le chat les valeurs que le client peut lire.")
local moveBtn2 = Button(display, COL2, -144, 200, "", Run("move"),
	"Affiche la barre de cast, l'orientation et les voyants pour les deplacer (coin bas-droit : taille). Recliquer pour enregistrer.")
moveBtn2.Refresh = moveBtn.Refresh
controls[#controls + 1] = moveBtn2
Toggle(display, COL2, -174, "meleeLight", "Voyant du guerrier (portee / orientation)",
	"Grand voyant chez le partenaire pendant les combats du guerrier : vert = attaque sa cible au corps a corps, "
	.. "rouge = trop loin, mal oriente (a la premiere attaque ratee), n'attaque pas ou sans cible. "
	.. "Le bouton ci-dessus (ou /duo move) permet de le glisser, et le coin bas-droit de le redimensionner. "
	.. "A laisser actif sur les deux persos. /duo light on|off, /duo light debug (sur le guerrier) : ce que le client repond.")

Header(display, COL2, -212, "Mesure")
Toggle(display, COL2, -230, "journal", "Journal de combat (pour l'analyse)",
	"Desactive par defaut. Note chaque combat (voyant, cibles, touches, erreurs) dans le fichier SavedVariables "
	.. "et lance le journal de combat du jeu (avance : positions). A lire avec tools/analyze_fights.py. "
	.. "N'agit pas sur le jeu. /duo journal on|off, /duo journal : resume.")

Header(display, COL2, -266, "Cone d'orientation du partenaire")
Toggle(display, COL2, -284, "facingCone", "Cone aux pieds du partenaire",
	"Desactive par defaut. Un cone jaune sous le partenaire montre vers ou il est tourne (le guerrier frappe ce qui "
	.. "est devant lui, jusqu'a 90 degres de chaque cote). Accroche a sa barre de nom : les barres de nom amies "
	.. "sont activees avec l'option (Maj+V pour les masquer), et Blizzard les bloque en donjon (pas de cone). "
	.. "Angle estime : la camera doit etre derriere ton perso (faux pendant une rotation au clic gauche). "
	.. "A activer seulement de ce cote ; DuoBox doit etre a jour sur les deux PC. /duo cone on|off, /duo cone debug.")
Slider(display, COL2, -312, "coneHeight", "Hauteur de la pointe", 20, 300, 10, "%d%%",
	"Plus : la pointe du cone descend. Moins : elle monte. A regler pour qu'elle tombe aux pieds du partenaire.")

Header(display, 0, -200, "Detections de metiers sur la minimap")
Toggle(display, 0, -218, "tracking", "Partager les detections (experimental)",
	"A activer sur les deux persos. Lit les infobulles des vrais points jaunes puis affiche les reperes chez le partenaire. "
	.. "GatherLite est requis pour scanner : ses emplacements connus guident le scan. "
	.. "La minimap est deplacee brievement sous le curseur toutes les 5 s ; elle peut clignoter. "
	.. "Pause en combat et pendant la rotation de camera. Les reperes expirent apres 15 s sans confirmation.")
local trackingState = Note(display, 0, -250, 230) -- left column: the facing cone is on the right
Button(display, 0, -290, 200, "Scanner maintenant", Run("tracking scan"),
	"Lance un passage de verification si une detection de minerais ou de plantes est active.")

--------------------------------------------------------------------------------
-- Page 6: RestedXP
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
-- Page 7: Profiles (Profiles.lua)
--------------------------------------------------------------------------------

local profPage = NewPage("Profils")

StaticPopupDialogs.DUOBOX_CONFIRM = {
	text = "%s", button1 = YES or "Oui", button2 = NO or "Non",
	OnAccept = function(self, data)
		local action = data or self.data
		if action then action() end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Runs the action, after a Yes in a popup when there is a question
local function Confirm(question, action)
	if not question then return action() end
	StaticPopup_Show("DUOBOX_CONFIRM", question, nil, action)
end

Header(profPage, 0, 0, "Profils de reglages (communs aux persos de ce compte WoW)")
local profState = Note(profPage, 0, -18, 490)

local profEdit = CreateFrame("EditBox", nil, profPage, "InputBoxTemplate")
profEdit:SetSize(180, 20)
profEdit:SetPoint("TOPLEFT", 6, -42)
profEdit:SetAutoFocus(false)
profEdit:SetMaxLetters(32)

local function SaveProfile()
	local name = profEdit:GetText():match("^%s*(.-)%s*$")
	profEdit:ClearFocus()
	if name == "" then
		Print("donne un nom au profil.")
		return
	end
	local profile, key = ns.ProfileInfo(name)
	Confirm(profile and key ~= ns.ActiveProfile() and ("Remplacer le profil %s par les reglages actuels ?"):format(key),
		function() ns.Command("profile save " .. name) end)
end

profEdit:SetScript("OnEnterPressed", SaveProfile)
profEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns.RefreshOptions() end)
profEdit.Refresh = function(self) if not self:HasFocus() then self:SetText(ns.ActiveProfile() or "") end end
Tooltip(profEdit, "Nom du profil", "Par exemple Quetes ou Donjon. Prerempli avec le profil actif.")
controls[#controls + 1] = profEdit
Button(profPage, 196, -41, 120, "Enregistrer", SaveProfile,
	"Enregistre les reglages actuels de ce perso sous ce nom. Un profil du meme nom est remplace.")

Header(profPage, 0, -76, "Profils enregistres")
local profMore = Note(profPage, 180, -78, 310)

local function LoadProfile(name)
	if InCombatLockdown() then
		Print("un profil se charge hors combat.")
		return
	end
	local active, changed = ns.ActiveProfile()
	Confirm((not active or changed) and ("Charger le profil %s ?\nLes reglages actuels de ce perso, pas enregistres, seront remplaces.")
		:format(name), function() ns.Command("profile load " .. name) end)
end

local ROWS, ROW_H = 7, 24
local profRows, profOffset = {}, 0
local profList = CreateFrame("Frame", nil, profPage)
profList:SetPoint("TOPLEFT", 0, -94)
profList:SetSize(490, ROWS * ROW_H)
profList:EnableMouseWheel(true)

for i = 1, ROWS do
	local row = CreateFrame("Frame", nil, profList)
	row:SetSize(490, ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetWidth(170)
	row.name:SetJustifyH("LEFT")
	row.by = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.by:SetPoint("LEFT", 180, 0)
	row.by:SetWidth(134)
	row.by:SetJustifyH("LEFT")
	Button(row, 318, -1, 82, "Charger", function() LoadProfile(row.profile) end,
		"Remplace les reglages de ce perso par ceux du profil (hors combat).")
	Button(row, 404, -1, 86, "Supprimer", function()
		Confirm(("Supprimer le profil %s ?"):format(row.profile), function() ns.Command("profile delete " .. row.profile) end)
	end, "Supprime le profil pour tous les persos de ce compte.")
	profRows[i] = row
end

local function ClassColored(name, class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not c then return name end
	return ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), name)
end

local function RefreshProfiles()
	local names = ns.ProfileNames()
	profOffset = math.max(0, math.min(profOffset, #names - ROWS))
	local active = ns.ActiveProfile()
	for i, row in ipairs(profRows) do
		local name = names[profOffset + i]
		row:SetShown(name ~= nil)
		if name then
			local info = ns.ProfileInfo(name)
			row.profile = name
			row.name:SetText(name == active and ("|cffffd040%s|r"):format(name) or name)
			row.by:SetText(info.by and ("par " .. ClassColored(info.by, info.class)) or "")
		end
	end
	profMore:SetText(#names == 0 and "|cff999999Aucun : saisis un nom puis Enregistrer.|r"
		or #names > ROWS and ("|cff999999%d-%d sur %d (molette)|r"):format(profOffset + 1, profOffset + ROWS, #names) or "")
end

profList:SetScript("OnMouseWheel", function(_, delta)
	profOffset = profOffset - delta
	RefreshProfiles()
end)
controls[#controls + 1] = { Refresh = RefreshProfiles }

Note(profPage, 0, -272, 490):SetText("|cff999999Un profil contient tous les reglages du panneau sauf le partenaire, "
	.. "le role et le tank, plus les sorts du bouton Rotation. Les positions restent propres a chaque perso. "
	.. "Les profils sont enregistres pour ce compte WoW sur ce PC : l'autre PC a les siens. /duo profile|r")

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
	dungeonState:SetText(ns.DungeonStatus and ns.DungeonStatus() or "")
	RefreshProcs()
	local active, changed = ns.ActiveProfile()
	profState:SetText(not active and "Aucun profil actif sur ce perso."
		or changed and ("Profil actif : |cffffd040%s|r, |cffff9933modifie depuis|r : Enregistrer pour le mettre a jour."):format(active)
		or ("Profil actif : |cffffd040%s|r (a jour)."):format(active))
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
