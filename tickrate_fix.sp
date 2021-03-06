/*
	SourcePawn is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2008 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.
	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.
	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.
	You should have received a copy of the GNU General Public License along
	with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

//<<<<<<<<<<<<<<<<<<<<< TICKRATE FIXES >>>>>>>>>>>>>>>>>>
//--------------- Fast Pistols & Slow Doors -------------
//*******************************************************

#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

// Cvars
ConVar g_hPistolDelayDualies, g_hPistolDelaySingle, g_hPistolDelayIncapped, hCvarDoorSpeed;

// Floats
float g_fNextAttack[MAXPLAYERS + 1], g_fPistolDelayDualies = 0.1, g_fPistolDelaySingle = 0.2, g_fPistolDelayIncapped = 0.3, fDoorSpeed;

// Cvar Check & Adjust
ConVar g_hCvarGravity;

// Tracking
enum DoorsTypeTracked
{
    DoorsTypeTracked_None = -1,
    DoorsTypeTracked_Prop_Door_Rotating = 0,
    DoorTypeTracked_Prop_Door_Rotating_Checkpoint = 1
};

char g_szDoors_Type_Tracked[][MAX_NAME_LENGTH] = 
{
    "prop_door_rotating",
    "prop_door_rotating_checkpoint"
};

enum struct DoorsData
{
    DoorsTypeTracked DoorsData_Type;
    float DoorsData_Speed;
    bool DoorsData_ForceClose;
}

DoorsData g_ddDoors[2048];

public Plugin myinfo = 
{
	name = "Tickrate Fixes",
	author = "Sir, Griffin",
	description = "Fixes a handful of silly Tickrate bugs",
	version = "1.1",
	url = ""
}

public void OnPluginStart()
{
    // Hook Pistols
    for (int client = 1; client <= MaxClients; client++)
	{
        if (!IsClientInGame(client)) continue;
        SDKHook(client, SDKHook_PostThinkPost, Hook_OnPostThinkPost);
	}
    g_hPistolDelayDualies = CreateConVar("l4d_pistol_delay_dualies","0.1", "Minimum time (in seconds) between dual pistol shots", FCVAR_SPONLY | FCVAR_NOTIFY, true, 0.0, true, 5.0);
    g_hPistolDelaySingle = CreateConVar("l4d_pistol_delay_single","0.2", "Minimum time (in seconds) between single pistol shots", FCVAR_SPONLY | FCVAR_NOTIFY, true, 0.0, true, 5.0);
    g_hPistolDelayIncapped = CreateConVar("l4d_pistol_delay_incapped","0.3", "Minimum time (in seconds) between pistol shots while incapped", FCVAR_SPONLY | FCVAR_NOTIFY, true, 0.0, true, 5.0);

    UpdatePistolDelays();

    HookConVarChange(g_hPistolDelayDualies, Cvar_PistolDelay);
    HookConVarChange(g_hPistolDelaySingle, Cvar_PistolDelay);
    HookConVarChange(g_hPistolDelayIncapped, Cvar_PistolDelay);
    HookEvent("weapon_fire", Event_WeaponFire);

    // Slow Doors
    hCvarDoorSpeed = CreateConVar("tick_door_speed","2.0", "Sets the speed of all prop_door entities on a map. 1.05 means = 105% speed", FCVAR_SPONLY | FCVAR_NOTIFY, true, 0.0, true, 5.0);
    fDoorSpeed = GetConVarFloat(hCvarDoorSpeed);

    HookConVarChange(hCvarDoorSpeed, cvarChanged);
	
    Door_ClearSettingsAll();
    Door_GetSettingsAll();
    Door_SetSettingsAll();
	
    // Gravity
    g_hCvarGravity = FindConVar("sv_gravity");
    if (GetConVarInt(g_hCvarGravity) != 750) SetConVarInt(g_hCvarGravity, 750);
}

public void OnPluginEnd()
{
    Door_ResetSettingsAll();
}

public void OnEntityCreated(int entity, const char[] classname)
{
    for(int i=0;i<sizeof(g_szDoors_Type_Tracked);i++)
	{
        if (StrEqual(classname, g_szDoors_Type_Tracked[i], false))
		{
            CreateTimer(0.2, EntityTimer, entity, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public Action EntityTimer(Handle timer, int entity)
{
    if (!IsValidEntity(entity)) return;
    char classname[128];
    GetEntityClassname(entity, classname, sizeof(classname));

    // Save Original Settings.
    for(int i=0;i<sizeof(g_szDoors_Type_Tracked);i++)
	{
        if (StrEqual(classname, g_szDoors_Type_Tracked[i], false))
		{
            Door_GetSettings(entity,view_as<DoorsTypeTracked>(i));
		}
	}

    // Set Settings.
    Door_SetSettings(entity);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_PreThink, Hook_OnPostThinkPost);
    g_fNextAttack[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_PreThink, Hook_OnPostThinkPost);
}

public void Cvar_PistolDelay(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdatePistolDelays();
}

void UpdatePistolDelays()
{
    g_fPistolDelayDualies = GetConVarFloat(g_hPistolDelayDualies);
    if (g_fPistolDelayDualies < 0.0) g_fPistolDelayDualies = 0.0;
    else if (g_fPistolDelayDualies > 5.0) g_fPistolDelayDualies = 5.0;

    g_fPistolDelaySingle = GetConVarFloat(g_hPistolDelaySingle);
    if (g_fPistolDelaySingle < 0.0) g_fPistolDelaySingle = 0.0;
    else if (g_fPistolDelaySingle > 5.0) g_fPistolDelaySingle = 5.0;

    g_fPistolDelayIncapped = GetConVarFloat(g_hPistolDelayIncapped);
    if (g_fPistolDelayIncapped < 0.0) g_fPistolDelayIncapped = 0.0;
    else if (g_fPistolDelayIncapped > 5.0) g_fPistolDelayIncapped = 5.0;
}

public void Hook_OnPostThinkPost(int client)
{
    // Human survivors only
    if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != 2) return;
    int activeweapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEdict(activeweapon)) return;
    char weaponname[64];
    GetEdictClassname(activeweapon, weaponname, sizeof(weaponname));
    if (strcmp(weaponname, "weapon_pistol") != 0) return;

    float old_value = GetEntPropFloat(activeweapon, Prop_Send, "m_flNextPrimaryAttack");
    float new_value = g_fNextAttack[client];

    // Never accidentally speed up fire rate
    if (new_value > old_value)
	{
        // PrintToChatAll("Readjusting delay: Old=%f, New=%f", old_value, new_value);
        SetEntPropFloat(activeweapon, Prop_Send, "m_flNextPrimaryAttack", new_value);
	}
}

public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != 2) return;
    int activeweapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEdict(activeweapon)) return;
    char weaponname[64];
    GetEdictClassname(activeweapon, weaponname, sizeof(weaponname));
    if (strcmp(weaponname, "weapon_pistol") != 0) return;
    // int dualies = GetEntProp(activeweapon, Prop_Send, "m_hasDualWeapons");
    if (GetEntProp(client, Prop_Send, "m_isIncapacitated"))
	{
        g_fNextAttack[client] = GetGameTime() + g_fPistolDelayIncapped;
	}
    // What is the difference between m_isDualWielding and m_hasDualWeapons ?
    else if (GetEntProp(activeweapon, Prop_Send, "m_isDualWielding"))
	{
        g_fNextAttack[client] = GetGameTime() + g_fPistolDelayDualies;
	}
    else
	{
        g_fNextAttack[client] = GetGameTime() + g_fPistolDelaySingle;
	}
}

public void cvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    fDoorSpeed = GetConVarFloat(hCvarDoorSpeed);
    Door_SetSettingsAll();
}

void Door_SetSettingsAll()
{
    int countEnts=0;
    int entity = -1;

    for(int i=0;i<sizeof(g_szDoors_Type_Tracked);i++)
	{

        while ((entity = FindEntityByClassname(entity, g_szDoors_Type_Tracked[i])) != INVALID_ENT_REFERENCE)
		{

            Door_SetSettings(entity);
            Entity_SetForceClose(entity, false);
            countEnts++;
		}

        entity = -1;
	}
}

void Door_SetSettings(int entity)
{
    Entity_SetSpeed(entity,g_ddDoors[entity].DoorsData_Speed * fDoorSpeed);
}

void Door_ResetSettingsAll()
{

    int countEnts=0;
    int entity = -1;

    for(int i=0;i<sizeof(g_szDoors_Type_Tracked);i++)
	{

        while ((entity = FindEntityByClassname(entity, g_szDoors_Type_Tracked[i])) != INVALID_ENT_REFERENCE)
		{

            Door_ResetSettings(entity);
            countEnts++;
		}

        entity = -1;
	}
} 

void Door_ResetSettings(int entity)
{
    Entity_SetSpeed(entity,g_ddDoors[entity].DoorsData_Speed);
}

void Door_GetSettingsAll()
{
    int countEnts=0;
    int entity = -1;

    for(int i=0;i<sizeof(g_szDoors_Type_Tracked);i++)
	{

        while ((entity = FindEntityByClassname(entity, g_szDoors_Type_Tracked[i])) != INVALID_ENT_REFERENCE)
		{

            Door_GetSettings(entity,view_as<DoorsTypeTracked>(i));
            countEnts++;
		}

        entity = -1;
	} 
}

void Door_GetSettings(int entity,DoorsTypeTracked type)
{
    g_ddDoors[entity].DoorsData_Type = type;
    g_ddDoors[entity].DoorsData_Speed = Entity_GetSpeed(entity);
    g_ddDoors[entity].DoorsData_ForceClose = Entity_GetForceClose(entity);
}

void Door_ClearSettingsAll()
{
    for(int i=0;i<sizeof(g_ddDoors);i++)
	{
		g_ddDoors[i].DoorsData_Type = DoorsTypeTracked_None;
		g_ddDoors[i].DoorsData_Speed = 0.0;
		g_ddDoors[i].DoorsData_ForceClose = false;
	}

}

stock void Entity_SetSpeed(int entity, float speed)
	{
		SetEntPropFloat(entity, Prop_Data, "m_flSpeed", speed);
	}

stock float Entity_GetSpeed(int entity)
	{
		return GetEntPropFloat(entity, Prop_Data, "m_flSpeed");
	}

stock void Entity_SetForceClose(int entity, bool forceClose)
	{
		SetEntProp(entity, Prop_Data, "m_bForceClosed", forceClose);
	}

stock bool Entity_GetForceClose(int entity)
	{
		return view_as<bool>(GetEntProp(entity, Prop_Data, "m_bForceClosed"));
	}