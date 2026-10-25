enum WeaponFlag {
	Wearable,
	AllClassMelee
	Shotgun
	Pistol,
	Katana,
}

const MAX_WEAPONS = 8;

const ID_PARACHUTE = 1101;
const ID_TOOLBOX = 28;

const OBJ_DISPENSER = 0;
const OBJ_TELEPORTER = 1;
const OBJ_SENTRYGUN = 2;
const OBJ_ATTACHMENT_SAPPER = 3;

const TF_CLASS_DEMOMAN = 4;
const TF_CLASS_SCOUT = 1;

local function SafeCreateByClassname(classname) {
    local entity = Entities.CreateByClassname(classname);
    NetProps.SetPropBool(entity, "m_bForcePurgeFixedupStrings", true);
    return entity;
}

local PLAYER_MANAGER = Entities.FindByClassname(null, "tf_player_manager");
local function GetPlayerUserID(player) {
    return NetProps.GetPropIntArray(PLAYER_MANAGER, "m_iUserID", player.entindex());
}

local function ModelFromDefIndex(index) {
    local wearable = SafeCreateByClassname("tf_wearable");
    NetProps.SetPropInt(wearable, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", index);
    NetProps.SetPropBool(wearable, "m_AttributeManager.m_Item.m_bInitialized", true);
    wearable.DispatchSpawn();

	local model = wearable.GetModelName();

	wearable.Kill();

    return model;
}


/**
 * @type {function}
 * @param {CTFPlayer} player
 * @param {integer} id
 * @returns {CEconEntity}
 */
::EquipWearable <- function(player, id) {
    local weapon = SafeCreateByClassname("tf_weapon_parachute");
    NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", ID_PARACHUTE);
    NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true);
    weapon.DispatchSpawn();
    player.Weapon_Equip(weapon);

	local model = ModelFromDefIndex(id);
    local wearable = NetProps.GetPropEntity(weapon, "m_hExtraWearable");
    wearable.SetModelSimple(model);
	weapon.Kill();

    // (optional) recalculates bodygroups on the player
    NetProps.SetPropInt(wearable, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", id);
    SendGlobalGameEvent("post_inventory_application", { userid = GetPlayerUserID(player) });

    // Not cleaned up on resupply otherwise
	wearable.ValidateScriptScope();
	local scope = wearable.GetScriptScope();
	scope.OnGameEvent_post_inventory_application <- function(params) {
		if (GetPlayerFromUserID(params.userid) != player) {
			return;
		}

		wearable.Kill();
	}
	__CollectGameEventCallbacks(scope);

    return wearable;
}

/**
 * @type {function}
 * @param {CTFPlayer} player
 * @param {integer} id
 * @param {integer|null} slot Pass `null` to use a default slot for that weapon, pass an integer [0; 5] to force a certain slot.
 *                            If the requested slot matches with weapon's default slot, the behaviour would be similar to passing `null`.
 * @returns {CEconEntity}
 * @throws {string}
 */
::GiveWeapon <- function(player, id, slot = null) {
    if (!(player instanceof CTFPlayer) || !player.IsValid()) {
        throw "Invalid player was given";
    }

    if (!(id in WEAPON_ID_MAP)) {
        throw format("Invalid weapon id '%s' was given.", id);
    }

	if (slot != null && (slot < 0 || slot > 5)) {
		throw format("Invalid slot '%i' was given. Value should be within [0; 5] range.", slot);
	}

    local data = WEAPON_ID_MAP[id];

	local classname, animations;
	if ("flag" in data) {
		local flag = data.flag;
		switch (flag) {
		// Technically those have a different classname but you can't put a
		// wearable other than `tf_wearable` inside `m_hMyWearables` so it's unused for now
		case WeaponFlag.Wearable:
			return EquipWearable(player, id);
		case WeaponFlag.AllClassMelee:
			classname = [
				"tf_weapon_bat",             // TF_CLASS_SCOUT,
				"tf_weapon_club",            // TF_CLASS_SNIPER,
				"tf_weapon_shovel",          // TF_CLASS_SOLDIER,
				"tf_weapon_bottle",          // TF_CLASS_DEMOMAN,
				"tf_weapon_bonesaw",         // TF_CLASS_MEDIC,
				"tf_weapon_fireaxe",         // TF_CLASS_HEAVYWEAPONS,       HWG uses a fireaxe because he doesn't have a default melee weapon of his own; also I am a terrible person
				"tf_weapon_fireaxe",         // TF_CLASS_PYRO,
				"tf_weapon_knife",           // TF_CLASS_SPY,
				"tf_weapon_wrench",          // TF_CLASS_ENGINEER,
			][player.GetPlayerClass() - 1];
			break;
		case WeaponFlag.Shotgun:
			classname = [
				"tf_weapon_shotgun_soldier", // TF_CLASS_SCOUT,
				"tf_weapon_shotgun_soldier", // TF_CLASS_SNIPER,
				"tf_weapon_shotgun_soldier", // TF_CLASS_SOLDIER,
				"tf_weapon_shotgun_soldier", // TF_CLASS_DEMOMAN,
				"tf_weapon_shotgun_soldier", // TF_CLASS_MEDIC,
				"tf_weapon_shotgun_hwg",     // TF_CLASS_HEAVYWEAPONS,
				"tf_weapon_shotgun_pyro",    // TF_CLASS_PYRO,
				"tf_weapon_shotgun_soldier", // TF_CLASS_SPY,
				"tf_weapon_shotgun_primary", // TF_CLASS_ENGINEER,
			][player.GetPlayerClass() - 1];
			animations = [
				"soldier",                   // TF_CLASS_SCOUT,
				"soldier",                   // TF_CLASS_SNIPER,
				"soldier",                   // TF_CLASS_SOLDIER,
				"soldier",                   // TF_CLASS_DEMOMAN,
				"soldier",                   // TF_CLASS_MEDIC,
				"heavy",                     // TF_CLASS_HEAVYWEAPONS,
				"pyro",                      // TF_CLASS_PYRO,
				"soldier",                   // TF_CLASS_SPY,
				"engineer"                   // TF_CLASS_ENGINEER,
			][player.GetPlayerClass() - 1];
			break;
		case WeaponFlag.Pistol:
			local is_scout = player.GetPlayerClass() == TF_CLASS_SCOUT;
			classname = is_scout ? "tf_weapon_pistol_scout" : "tf_weapon_pistol";
			animations = is_scout ? "scout" : "engineer";
			break;
		case WeaponFlag.Katana:
			classname = "tf_weapon_katana";
			animations = player.GetPlayerClass() == TF_CLASS_DEMOMAN ? "demo" : "soldier";
			break;
		}
	} else {
		classname = data.classname;
		animations = data.animations;
	}

	local weapon = SafeCreateByClassname(classname);
    NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", id);
    NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true);
	NetProps.SetPropBool(weapon, "m_bValidatedAttachedEntity", true);
	weapon.DispatchSpawn();

	// Fix toolbox/sappers crashing the server if missing some netprops
	if (classname == "tf_weapon_builder" || classname == "tf_weapon_sapper") {
		local is_toolbox = id == ID_TOOLBOX;
		// Don't ask, the values are copied from properly spawned items
		NetProps.SetPropInt(weapon, "m_iObjectType", is_toolbox ? 2 : 3);
		NetProps.SetPropInt(weapon, "m_iObjectMode", 0);
		if (is_toolbox) {
			NetProps.SetPropBoolArray(weapon, "m_aBuildableObjectTypes", true, OBJ_DISPENSER);
			NetProps.SetPropBoolArray(weapon, "m_aBuildableObjectTypes", true, OBJ_TELEPORTER);
			NetProps.SetPropBoolArray(weapon, "m_aBuildableObjectTypes", true, OBJ_SENTRYGUN);

			// Shouldn't manipulate slots for the toolbox, since it's normally not present in them
			player.Weapon_Equip(weapon);
			return weapon;
		}

		NetProps.SetPropBoolArray(weapon, "m_aBuildableObjectTypes", true, OBJ_ATTACHMENT_SAPPER);
	}


	slot = slot == null ? weapon.GetSlot() : slot;
	for (local i = 0; i < MAX_WEAPONS; i++) {
		local held_weapon = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i);
        NetProps.SetPropBool(held_weapon, "m_bForcePurgeFixedupStrings", true);

		if (held_weapon == null || held_weapon.GetSlot() != slot)
			continue;

		if (held_weapon == player.GetActiveWeapon()) {
			EntFireByHandle(player, "RunScriptCode", "self.Weapon_Switch(activator)", 0.0, weapon, null);
		}

		local wearable = NetProps.GetPropEntity(held_weapon, "m_hExtraWearable");
		if (wearable != null) {
			wearable.Kill();
		}

		local wearable_viewmodel = NetProps.GetPropEntity(held_weapon, "m_hExtraWearableViewModel");
		if (wearable_viewmodel != null) {
			wearable_viewmodel.Kill();
		}

		held_weapon.Kill();
		break;
	}

	if (slot != weapon.GetSlot()) {
		local classnames = [
			"tf_weapon_cannon"
			"tf_weapon_smg"
			"tf_weapon_bat"
			"tf_weapon_pda_engineer_build"
			"tf_weapon_pda_engineer_destroy"
			"tf_weapon_grapplinghook"
		];

		local dummy = SafeCreateByClassname(classnames[slot]);
		NetProps.SetPropInt(dummy, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", id);
		NetProps.SetPropBool(dummy, "m_AttributeManager.m_Item.m_bInitialized", true);
		// Change dummy's classname so the game calls a search for the original weapon's `classname` when pressing a slot
		NetProps.SetPropString(dummy, "m_iClassname", classname);
		dummy.DispatchSpawn();
		player.Weapon_Equip(dummy);
		// Make the dummy fail checks that allow it to be selected, this way only the original weapon could be found
		// This can either be done by changing classname to anything other than original's weapon classname
		// or changing `m_iSubType` to something other than 0
		NetProps.SetPropString(dummy, "m_iClassname", "");
	}

	player.AddCustomAttribute("disable weapon switch", 1, 0.0);
	player.Weapon_Equip(weapon);
	player.RemoveCustomAttribute("disable weapon switch");

	if (!animations) {
		return weapon;
    }

	local proper_arms = format("models/weapons/c_models/c_%s_arms.mdl", animations);
	if (proper_arms == weapon.GetModelName()) {
		return weapon;
	}

	player.ValidateScriptScope();
	local player_scope = player.GetScriptScope();

	if (!("arms" in player_scope) || !player_scope.arms.IsValid()) {
		local arms = SafeCreateByClassname("tf_wearable_vm");
		arms.SetModelSimple(weapon.GetModelName());
		arms.SetTeam(player.GetTeam());
		arms.DispatchSpawn();

		player.EquipWearableViewModel(arms);
		player_scope.arms <- arms;
	}

	local proper_arms_index = GetModelIndex(proper_arms);
    weapon.SetModelSimple(proper_arms);
    weapon.SetCustomViewModelModelIndex(proper_arms_index);
    NetProps.SetPropInt(weapon, "m_iViewModelIndex", proper_arms_index);

	local vm_weapon = SafeCreateByClassname("tf_wearable_vm");
	vm_weapon.SetModel(ModelFromDefIndex(id));
	vm_weapon.SetTeam(player.GetTeam());
	vm_weapon.DispatchSpawn();
	player.EquipWearableViewModel(vm_weapon);
	NetProps.SetPropEntity(vm_weapon, "m_hWeaponAssociatedWith", weapon);

	local extra_wearable = NetProps.GetPropEntity(weapon, "m_hExtraWearableViewModel");
	NetProps.SetPropEntity(weapon, "m_hExtraWearableViewModel", vm_weapon);
	if (extra_wearable != null) {
		extra_wearable.AcceptInput("SetParent", "!activator", vm_weapon, null);
	}

	weapon.ValidateScriptScope();
	weapon.GetScriptScope().Think <- function() {
		if (player.GetActiveWeapon() == weapon) {
			NetProps.GetPropEntity(player, "m_hViewModel").DisableDraw();
		}
		return -1;
	}
	AddThinkToEnt(weapon, "Think");

	return weapon;
}


// Generated from https://wiki.alliedmods.net/Team_fortress_2_item_definition_indexes
// Keyed by item definition index. 'animations' = class whose viewmodel animations the weapon uses.
::WEAPON_ID_MAP <- {
    // ---- allclass melees ---
    [264] = { flag = WeaponFlag.AllClassMelee },
    [423] = { flag = WeaponFlag.AllClassMelee },
    [474] = { flag = WeaponFlag.AllClassMelee },
    [880] = { flag = WeaponFlag.AllClassMelee },
    [939] = { flag = WeaponFlag.AllClassMelee },
    [954] = { flag = WeaponFlag.AllClassMelee },
    [1013] = { flag = WeaponFlag.AllClassMelee },
    [1071] = { flag = WeaponFlag.AllClassMelee },
    [1123] = { flag = WeaponFlag.AllClassMelee },
    [1127] = { flag = WeaponFlag.AllClassMelee },
    [30758] = { flag = WeaponFlag.AllClassMelee },

	// ---- shotguns ----
	[199] = { flag = WeaponFlag.Shotgun },
	[415] = { flag = WeaponFlag.Shotgun },
	[1141] = { flag = WeaponFlag.Shotgun },
	[1153] = { flag = WeaponFlag.Shotgun },
	[15003] = { flag = WeaponFlag.Shotgun },
	[15016] = { flag = WeaponFlag.Shotgun },
	[15044] = { flag = WeaponFlag.Shotgun },
	[15047] = { flag = WeaponFlag.Shotgun },
	[15085] = { flag = WeaponFlag.Shotgun },
	[15109] = { flag = WeaponFlag.Shotgun },
	[15132] = { flag = WeaponFlag.Shotgun },
	[15133] = { flag = WeaponFlag.Shotgun },
	[15152] = { flag = WeaponFlag.Shotgun },

	// ---- pistols ----
	[160] = { flag = WeaponFlag.Pistol },
	[209] = { flag = WeaponFlag.Pistol },
	[294] = { flag = WeaponFlag.Pistol },
	[15013] = { flag = WeaponFlag.Pistol },
	[15018] = { flag = WeaponFlag.Pistol },
	[15035] = { flag = WeaponFlag.Pistol },
	[15041] = { flag = WeaponFlag.Pistol },
	[15046] = { flag = WeaponFlag.Pistol },
	[15056] = { flag = WeaponFlag.Pistol },
	[15060] = { flag = WeaponFlag.Pistol },
	[15061] = { flag = WeaponFlag.Pistol },
	[15100] = { flag = WeaponFlag.Pistol },
	[15101] = { flag = WeaponFlag.Pistol },
	[15102] = { flag = WeaponFlag.Pistol },
	[15126] = { flag = WeaponFlag.Pistol },
	[15148] = { flag = WeaponFlag.Pistol },
	[30666] = { flag = WeaponFlag.Pistol },

	[357] = { flag = WeaponFlag.Katana },

	// ---- scout ----
	[0] = { classname = "tf_weapon_bat", animations = "scout" },
	[13] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[23] = { classname = "tf_weapon_pistol", animations = "scout" },
	[44] = { classname = "tf_weapon_bat_wood", animations = "scout" },
	[45] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[46] = { classname = "tf_weapon_lunchbox_drink", animations = "scout" },
	[163] = { classname = "tf_weapon_lunchbox_drink", animations = "scout" },
	[190] = { classname = "tf_weapon_bat", animations = "scout" },
	[200] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[220] = { classname = "tf_weapon_handgun_scout_primary", animations = "scout" },
	[221] = { classname = "tf_weapon_bat_fish", animations = "scout" },
	[222] = { classname = "tf_weapon_jar_milk", animations = "scout" },
	[317] = { classname = "tf_weapon_bat", animations = "scout" },
	[325] = { classname = "tf_weapon_bat", animations = "scout" },
	[349] = { classname = "tf_weapon_bat", animations = "scout" },
	[355] = { classname = "tf_weapon_bat", animations = "scout" },
	[448] = { classname = "tf_weapon_soda_popper", animations = "scout" },
	[449] = { classname = "tf_weapon_handgun_scout_secondary", animations = "scout" },
	[450] = { classname = "tf_weapon_bat", animations = "scout" },
	[452] = { classname = "tf_weapon_bat", animations = "scout" },
	[572] = { classname = "tf_weapon_bat_fish", animations = "scout" },
	[648] = { classname = "tf_weapon_bat_giftwrap", animations = "scout" },
	[660] = { classname = "tf_weapon_bat", animations = "scout" },
	[669] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[772] = { classname = "tf_weapon_pep_brawler_blaster", animations = "scout" },
	[773] = { classname = "tf_weapon_handgun_scout_secondary", animations = "scout" },
	[799] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[808] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[812] = { classname = "tf_weapon_cleaver", animations = "scout" },
	[833] = { classname = "tf_weapon_cleaver", animations = "scout" },
	[888] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[897] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[906] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[915] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[964] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[973] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[999] = { classname = "tf_weapon_bat_fish", animations = "scout" },
	[1078] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[1103] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[1121] = { classname = "tf_weapon_jar_milk", animations = "scout" },
	[1145] = { classname = "tf_weapon_lunchbox_drink", animations = "scout" },
	[15002] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15015] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15021] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15029] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15036] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15053] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15065] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15069] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15106] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15107] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15108] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15131] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15151] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[15157] = { classname = "tf_weapon_scattergun", animations = "scout" },
	[30667] = { classname = "tf_weapon_bat", animations = "scout" },
	// ---- soldier ----
	[6] = { classname = "tf_weapon_shovel", animations = "soldier" },
	[10] = { classname = "tf_weapon_shotgun_soldier", animations = "soldier" },
	[18] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[127] = { classname = "tf_weapon_rocketlauncher_directhit", animations = "soldier" },
	[128] = { classname = "tf_weapon_shovel", animations = "soldier" },
	[129] = { classname = "tf_weapon_buff_item", animations = "soldier" },
	[133] = { classname = "tf_wearable", flag = WeaponFlag.Wearable },
	[154] = { classname = "tf_weapon_shovel", animations = "soldier" },
	[196] = { classname = "tf_weapon_shovel", animations = "soldier" },
	[205] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[226] = { classname = "tf_weapon_buff_item", animations = "soldier" },
	[228] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[237] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[354] = { classname = "tf_weapon_buff_item", animations = "soldier" },
	[414] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[416] = { classname = "tf_weapon_shovel", animations = "soldier" },
	[441] = { classname = "tf_weapon_particle_cannon", animations = "soldier" },
	[442] = { classname = "tf_weapon_raygun", animations = "soldier" },
	[444] = { classname = "tf_wearable", flag = WeaponFlag.Wearable },
	[447] = { classname = "tf_weapon_shovel", animations = "soldier" },
	[513] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[658] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[730] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[775] = { classname = "tf_weapon_shovel", animations = "soldier" },
	[800] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[809] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[889] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[898] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[907] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[916] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[965] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[974] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[1001] = { classname = "tf_weapon_buff_item", animations = "soldier" },
	[1085] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	// Works fine but there's also `tf_weapon_parachute_primary` and `tf_weapon_parachute_secondary`
	[1101] = { classname = "tf_weapon_parachute", animations = "soldier" },
	[1104] = { classname = "tf_weapon_rocketlauncher_airstrike", animations = "soldier" },
	[15006] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15014] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15028] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15043] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15052] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15057] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15081] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15104] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15105] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15129] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15130] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	[15150] = { classname = "tf_weapon_rocketlauncher", animations = "soldier" },
	// ---- pyro ----
	[2] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[12] = { classname = "tf_weapon_shotgun_pyro", animations = "pyro" },
	[21] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[38] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[39] = { classname = "tf_weapon_flaregun", animations = "pyro" },
	[40] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[153] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[192] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[208] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[214] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[215] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[326] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[348] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[351] = { classname = "tf_weapon_flaregun", animations = "pyro" },
	[457] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[466] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[593] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[594] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[595] = { classname = "tf_weapon_flaregun_revenge", animations = "pyro" },
	[659] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[739] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[740] = { classname = "tf_weapon_flaregun", animations = "pyro" },
	[741] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[798] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[807] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[813] = { classname = "tf_weapon_breakable_sign", animations = "pyro" },
	[834] = { classname = "tf_weapon_breakable_sign", animations = "pyro" },
	[887] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[896] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[905] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[914] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[963] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[972] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[1000] = { classname = "tf_weapon_fireaxe", animations = "pyro" },
	[1081] = { classname = "tf_weapon_flaregun", animations = "pyro" },
	[1146] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[1178] = { classname = "tf_weapon_rocketlauncher_fireball", animations = "pyro" },
	[1179] = { classname = "tf_weapon_rocketpack", animations = "pyro" },
	[1180] = { classname = "tf_weapon_jar_gas", animations = "pyro" },
	[1181] = { classname = "tf_weapon_slap", animations = "pyro" },
	[15005] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15017] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15030] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15034] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15049] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15054] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15066] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15067] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15068] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15089] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15090] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15115] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[15141] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	[30474] = { classname = "tf_weapon_flamethrower", animations = "pyro" },
	// ---- demo ----
	[1] = { classname = "tf_weapon_bottle", animations = "demo" },
	[19] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[20] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[130] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[131] = { classname = "tf_wearable_demoshield", flag = WeaponFlag.Wearable },
	[132] = { classname = "tf_weapon_sword", animations = "demo" },
	[172] = { classname = "tf_weapon_sword", animations = "demo" },
	[191] = { classname = "tf_weapon_bottle", animations = "demo" },
	[206] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[207] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[265] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[266] = { classname = "tf_weapon_sword", animations = "demo" },
	[307] = { classname = "tf_weapon_stickbomb", animations = "demo" },
	[308] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[327] = { classname = "tf_weapon_sword", animations = "demo" },
	[404] = { classname = "tf_weapon_sword", animations = "demo" },
	[405] = { classname = "tf_wearable", flag = WeaponFlag.Wearable },
	[406] = { classname = "tf_wearable_demoshield", flag = WeaponFlag.Wearable },
	[482] = { classname = "tf_weapon_sword", animations = "demo" },
	[608] = { classname = "tf_wearable", flag = WeaponFlag.Wearable },
	[609] = { classname = "tf_weapon_bottle", animations = "demo" },
	[661] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[797] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[806] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[886] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[895] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[904] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[913] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[962] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[971] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[996] = { classname = "tf_weapon_cannon", animations = "demo" },
	[1007] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[1082] = { classname = "tf_weapon_sword", animations = "demo" },
	[1099] = { classname = "tf_wearable_demoshield", flag = WeaponFlag.Wearable },
	[1144] = { classname = "tf_wearable_demoshield", flag = WeaponFlag.Wearable },
	[1150] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[1151] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[15009] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15012] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15024] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15038] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15045] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15048] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15077] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[15079] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[15082] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15083] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15084] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15091] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[15092] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[15113] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15116] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[15117] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[15137] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15138] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15142] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	[15155] = { classname = "tf_weapon_pipebomblauncher", animations = "demo" },
	[15158] = { classname = "tf_weapon_grenadelauncher", animations = "demo" },
	// ---- heavy ----
	[5] = { classname = "tf_weapon_fists", animations = "heavy" },
	[11] = { classname = "tf_weapon_shotgun_hwg", animations = "heavy" },
	[15] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[41] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[42] = { classname = "tf_weapon_lunchbox", animations = "heavy" },
	[43] = { classname = "tf_weapon_fists", animations = "heavy" },
	[159] = { classname = "tf_weapon_lunchbox", animations = "heavy" },
	[195] = { classname = "tf_weapon_fists", animations = "heavy" },
	[202] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[239] = { classname = "tf_weapon_fists", animations = "heavy" },
	[298] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[310] = { classname = "tf_weapon_fists", animations = "heavy" },
	[311] = { classname = "tf_weapon_lunchbox", animations = "heavy" },
	[312] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[331] = { classname = "tf_weapon_fists", animations = "heavy" },
	[424] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[425] = { classname = "tf_weapon_shotgun_hwg", animations = "heavy" },
	[426] = { classname = "tf_weapon_fists", animations = "heavy" },
	[433] = { classname = "tf_weapon_lunchbox", animations = "heavy" },
	[587] = { classname = "tf_weapon_fists", animations = "heavy" },
	[654] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[656] = { classname = "tf_weapon_fists", animations = "heavy" },
	[793] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[802] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[811] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[832] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[850] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[863] = { classname = "tf_weapon_lunchbox", animations = "heavy" },
	[882] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[891] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[900] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[909] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[958] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[967] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[1002] = { classname = "tf_weapon_lunchbox", animations = "heavy" },
	[1084] = { classname = "tf_weapon_fists", animations = "heavy" },
	[1100] = { classname = "tf_weapon_fists", animations = "heavy" },
	[1184] = { classname = "tf_weapon_fists", animations = "heavy" },
	[1190] = { classname = "tf_weapon_lunchbox", animations = "heavy" },
	[15004] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15020] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15026] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15031] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15040] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15055] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15086] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15087] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15088] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15098] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15099] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15123] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15124] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15125] = { classname = "tf_weapon_minigun", animations = "heavy" },
	[15147] = { classname = "tf_weapon_minigun", animations = "heavy" },
	// ---- engineer ----
	[7] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[9] = { classname = "tf_weapon_shotgun_primary", animations = "engineer" },
	[22] = { classname = "tf_weapon_pistol", animations = "engineer" },
	[25] = { classname = "tf_weapon_pda_engineer_build", animations = "engineer" },
	[26] = { classname = "tf_weapon_pda_engineer_destroy", animations = "engineer" },
	[28] = { classname = "tf_weapon_builder", animations = "engineer" },
	[140] = { classname = "tf_weapon_laser_pointer", animations = "engineer" },
	[141] = { classname = "tf_weapon_sentry_revenge", animations = "engineer" },
	[142] = { classname = "tf_weapon_robot_arm", animations = "engineer" },
	[155] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[169] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[197] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[329] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[527] = { classname = "tf_weapon_shotgun_primary", animations = "engineer" },
	[528] = { classname = "tf_weapon_mechanical_arm", animations = "engineer" },
	[588] = { classname = "tf_weapon_drg_pomson", animations = "engineer" },
	[589] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[662] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[737] = { classname = "tf_weapon_pda_engineer_build", animations = "engineer" },
	[795] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[804] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[884] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[893] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[902] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[911] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[960] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[969] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[997] = { classname = "tf_weapon_shotgun_building_rescue", animations = "engineer" },
	[1004] = { classname = "tf_weapon_sentry_revenge", animations = "engineer" },
	[1086] = { classname = "tf_weapon_laser_pointer", animations = "engineer" },
	[15073] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[15074] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[15075] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[15114] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[15139] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[15140] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[15156] = { classname = "tf_weapon_wrench", animations = "engineer" },
	[30668] = { classname = "tf_weapon_laser_pointer", animations = "engineer" },
	// ---- medic ----
	[8] = { classname = "tf_weapon_bonesaw", animations = "medic" },
	[17] = { classname = "tf_weapon_syringegun_medic", animations = "medic" },
	[29] = { classname = "tf_weapon_medigun", animations = "medic" },
	[35] = { classname = "tf_weapon_medigun", animations = "medic" },
	[36] = { classname = "tf_weapon_syringegun_medic", animations = "medic" },
	[37] = { classname = "tf_weapon_bonesaw", animations = "medic" },
	[173] = { classname = "tf_weapon_bonesaw", animations = "medic" },
	[198] = { classname = "tf_weapon_bonesaw", animations = "medic" },
	[204] = { classname = "tf_weapon_syringegun_medic", animations = "medic" },
	[211] = { classname = "tf_weapon_medigun", animations = "medic" },
	[304] = { classname = "tf_weapon_bonesaw", animations = "medic" },
	[305] = { classname = "tf_weapon_crossbow", animations = "medic" },
	[411] = { classname = "tf_weapon_medigun", animations = "medic" },
	[412] = { classname = "tf_weapon_syringegun_medic", animations = "medic" },
	[413] = { classname = "tf_weapon_bonesaw", animations = "medic" },
	[663] = { classname = "tf_weapon_medigun", animations = "medic" },
	[796] = { classname = "tf_weapon_medigun", animations = "medic" },
	[805] = { classname = "tf_weapon_medigun", animations = "medic" },
	[885] = { classname = "tf_weapon_medigun", animations = "medic" },
	[894] = { classname = "tf_weapon_medigun", animations = "medic" },
	[903] = { classname = "tf_weapon_medigun", animations = "medic" },
	[912] = { classname = "tf_weapon_medigun", animations = "medic" },
	[961] = { classname = "tf_weapon_medigun", animations = "medic" },
	[970] = { classname = "tf_weapon_medigun", animations = "medic" },
	[998] = { classname = "tf_weapon_medigun", animations = "medic" },
	[1003] = { classname = "tf_weapon_bonesaw", animations = "medic" },
	[1079] = { classname = "tf_weapon_crossbow", animations = "medic" },
	[1143] = { classname = "tf_weapon_bonesaw", animations = "medic" },
	[15008] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15010] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15025] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15039] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15050] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15078] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15097] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15121] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15122] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15145] = { classname = "tf_weapon_medigun", animations = "medic" },
	[15146] = { classname = "tf_weapon_medigun", animations = "medic" },
	// ---- sniper ----
	[3] = { classname = "tf_weapon_club", animations = "sniper" },
	[14] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[16] = { classname = "tf_weapon_smg", animations = "sniper" },
	[56] = { classname = "tf_weapon_compound_bow", animations = "sniper" },
	[57] = { classname = "tf_wearable_razorback", flag = WeaponFlag.Wearable },
	[58] = { classname = "tf_weapon_jar", animations = "sniper" },
	[171] = { classname = "tf_weapon_club", animations = "sniper" },
	[193] = { classname = "tf_weapon_club", animations = "sniper" },
	[201] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[203] = { classname = "tf_weapon_smg", animations = "sniper" },
	[230] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[231] = { classname = "tf_wearable", flag = WeaponFlag.Wearable },
	[232] = { classname = "tf_weapon_club", animations = "sniper" },
	[401] = { classname = "tf_weapon_club", animations = "sniper" },
	[402] = { classname = "tf_weapon_sniperrifle_decap", animations = "sniper" },
	[526] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[642] = { classname = "tf_wearable", flag = WeaponFlag.Wearable },
	[664] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[751] = { classname = "tf_weapon_charged_smg", animations = "sniper" },
	[752] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[792] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[801] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[851] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[881] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[890] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[899] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[908] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[957] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[966] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[1005] = { classname = "tf_weapon_compound_bow", animations = "sniper" },
	[1083] = { classname = "tf_weapon_jar", animations = "sniper" },
	[1092] = { classname = "tf_weapon_compound_bow", animations = "sniper" },
	[1098] = { classname = "tf_weapon_sniperrifle_classic", animations = "sniper" },
	[1105] = { classname = "tf_weapon_jar", animations = "sniper" },
	[1149] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15000] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15001] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15007] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15019] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15022] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15023] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15032] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15033] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15037] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15058] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15059] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15070] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15071] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15072] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15076] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15110] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15111] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15112] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15134] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15135] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15136] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[15153] = { classname = "tf_weapon_smg", animations = "sniper" },
	[15154] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	[30665] = { classname = "tf_weapon_sniperrifle", animations = "sniper" },
	// ---- spy ----
	[4] = { classname = "tf_weapon_knife", animations = "spy" },
	[24] = { classname = "tf_weapon_revolver", animations = "spy" },
	[27] = { classname = "tf_weapon_pda_spy", animations = "spy" },
	[30] = { classname = "tf_weapon_invis", animations = "spy" },
	[59] = { classname = "tf_weapon_invis", animations = "spy" },
	[60] = { classname = "tf_weapon_invis", animations = "spy" },
	[61] = { classname = "tf_weapon_revolver", animations = "spy" },
	[161] = { classname = "tf_weapon_revolver", animations = "spy" },
	[194] = { classname = "tf_weapon_knife", animations = "spy" },
	[210] = { classname = "tf_weapon_revolver", animations = "spy" },
	[212] = { classname = "tf_weapon_invis", animations = "spy" },
	[224] = { classname = "tf_weapon_revolver", animations = "spy" },
	[225] = { classname = "tf_weapon_knife", animations = "spy" },
	[297] = { classname = "tf_weapon_invis", animations = "spy" },
	[356] = { classname = "tf_weapon_knife", animations = "spy" },
	[460] = { classname = "tf_weapon_revolver", animations = "spy" },
	[461] = { classname = "tf_weapon_knife", animations = "spy" },
	[525] = { classname = "tf_weapon_revolver", animations = "spy" },
	[574] = { classname = "tf_weapon_knife", animations = "spy" },
	[638] = { classname = "tf_weapon_knife", animations = "spy" },
	[649] = { classname = "tf_weapon_knife", animations = "spy" },
	[665] = { classname = "tf_weapon_knife", animations = "spy" },
	[727] = { classname = "tf_weapon_knife", animations = "spy" },
	[735] = { classname = "tf_weapon_builder", animations = "spy" },
	[736] = { classname = "tf_weapon_builder", animations = "spy" },
	[794] = { classname = "tf_weapon_knife", animations = "spy" },
	[803] = { classname = "tf_weapon_knife", animations = "spy" },
	[810] = { classname = "tf_weapon_sapper", animations = "spy" },
	[831] = { classname = "tf_weapon_sapper", animations = "spy" },
	[883] = { classname = "tf_weapon_knife", animations = "spy" },
	[892] = { classname = "tf_weapon_knife", animations = "spy" },
	[901] = { classname = "tf_weapon_knife", animations = "spy" },
	[910] = { classname = "tf_weapon_knife", animations = "spy" },
	[933] = { classname = "tf_weapon_sapper", animations = "spy" },
	[947] = { classname = "tf_weapon_invis", animations = "spy" },
	[959] = { classname = "tf_weapon_knife", animations = "spy" },
	[968] = { classname = "tf_weapon_knife", animations = "spy" },
	[1006] = { classname = "tf_weapon_revolver", animations = "spy" },
	[1080] = { classname = "tf_weapon_sapper", animations = "spy" },
	[1102] = { classname = "tf_weapon_sapper", animations = "spy" },
	[1142] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15011] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15027] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15042] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15051] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15062] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15063] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15064] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15094] = { classname = "tf_weapon_knife", animations = "spy" },
	[15095] = { classname = "tf_weapon_knife", animations = "spy" },
	[15096] = { classname = "tf_weapon_knife", animations = "spy" },
	[15103] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15118] = { classname = "tf_weapon_knife", animations = "spy" },
	[15119] = { classname = "tf_weapon_knife", animations = "spy" },
	[15127] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15128] = { classname = "tf_weapon_revolver", animations = "spy" },
	[15143] = { classname = "tf_weapon_knife", animations = "spy" },
	[15144] = { classname = "tf_weapon_knife", animations = "spy" },
	[15149] = { classname = "tf_weapon_revolver", animations = "spy" },
}