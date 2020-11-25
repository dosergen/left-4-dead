#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

#define PLUGIN_VERSION "2.0"

public Plugin myinfo =
{
	name = "L4D SM Respawn",
	author = "AtomicStryker & Ivailosp",
	description = "Let's you respawn Players by console",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=96249"
}

static float g_pos[3];
static Handle hRoundRespawn = null;
static Handle hBecomeGhost = null;
static Handle hState_Transition = null;
static Handle hGameConf = null;

public void OnPluginStart()
{
	char game_name[24];
	GetGameFolderName(game_name, sizeof(game_name));
	if (!StrEqual(game_name, "left4dead2", false) && !StrEqual(game_name, "left4dead", false))
	{
		SetFailState("Plugin only supports Left 4 Dead 1 & 2.");
	}

	LoadTranslations("common.phrases");
	hGameConf = LoadGameConfigFile("l4drespawn");
	
	CreateConVar("l4d_sm_respawn_version", PLUGIN_VERSION, "L4D SM Respawn Version", FCVAR_SPONLY | FCVAR_NOTIFY);
	RegAdminCmd("sm_respawn", Command_Respawn, ADMFLAG_BAN, "sm_respawn <player1> [player2] ... [playerN] - respawn all listed players and teleport them where you aim");

	if (hGameConf != null)
	{
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "RoundRespawn");
		hRoundRespawn = EndPrepSDKCall();
		if (hRoundRespawn == null) SetFailState("L4D_SM_Respawn: RoundRespawn Signature broken");
		
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "BecomeGhost");
		PrepSDKCall_AddParameter(SDKType_PlainOldData , SDKPass_Plain);
		hBecomeGhost = EndPrepSDKCall();
		if (hBecomeGhost == null && StrEqual(game_name, "left4dead2", false))
			LogError("L4D_SM_Respawn: BecomeGhost Signature broken");

		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "State_Transition");
		PrepSDKCall_AddParameter(SDKType_PlainOldData , SDKPass_Plain);
		hState_Transition = EndPrepSDKCall();
		if (hState_Transition == null && StrEqual(game_name, "left4dead2", false))
			LogError("L4D_SM_Respawn: State_Transition Signature broken");
	}
	else
	{
		SetFailState("could not find gamedata file at addons/sourcemod/gamedata/l4drespawn.txt , you FAILED AT INSTALLING");
	}
}

public Action Command_Respawn(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_respawn <player1> [player2] ... [playerN] - respawn all listed players");
		return Plugin_Handled;
	}
	
	char arg1[MAX_TARGET_LENGTH];
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS];
	int target_count;
	bool tn_is_ml;
	
	GetCmdArg(1, arg1, sizeof(arg1));
 
	if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MAXPLAYERS,
			0,				// no filtering
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		/* This function replies to the admin with a failure message */
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (int i = 0; i < target_count; i++)
	{
		RespawnPlayer(client, target_list[i]);
	}
	
	return Plugin_Handled;
}

static void RespawnPlayer(int client, int player_id)
{
	switch(GetClientTeam(player_id))
	{
		case 2:
		{
			if(IsPlayerAlive(player_id))
			{
				ReplyToCommand(client, "[SM] You Dumb? Target is still alive!");
				return;
			}
			bool canTeleport = SetTeleportEndPoint(client);
		
			SDKCall(hRoundRespawn, player_id);
			
			//CheatCommand(player_id, "give", "first_aid_kit");
			//CheatCommand(player_id, "give", "smg");
			
			if(canTeleport)
			{
				PerformTeleport(client,player_id,g_pos);
			}
			ShowActivity2(client, "[SM] ", "Respawned target '%N'", player_id);
		}
		
		case 3:
		{
			char game_name[24];
			GetGameFolderName(game_name, sizeof(game_name));
			if (StrEqual(game_name, "left4dead", false)) 
			{
				ReplyToCommand(client, "[SM] Failed! Target is not survivor");
				return;
			}
		
			SDKCall(hState_Transition, player_id, 8);
			SDKCall(hBecomeGhost, player_id, 1);
			SDKCall(hState_Transition, player_id, 6);
			SDKCall(hBecomeGhost, player_id, 1);
			ShowActivity2(client, "[SM] ", "Respawned target '%N'", player_id);
		}
		case 1:
		{
			ReplyToCommand(client, "[SM] Failed! Target is spectator");
		}
	}
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
	return entity > MaxClients || !entity;
} 

static bool SetTeleportEndPoint(int client)
{
	float vAngles[3], vOrigin[3];
	
	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);
	
	//get endpoint for teleport
	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);
	
	if(TR_DidHit(trace))
	{
		float vBuffer[3], vStart[3];

		TR_GetEndPosition(vStart, trace);
		GetVectorDistance(vOrigin, vStart, false);
		float Distance = -35.0;
		GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);
		g_pos[0] = vStart[0] + (vBuffer[0]*Distance);
		g_pos[1] = vStart[1] + (vBuffer[1]*Distance);
		g_pos[2] = vStart[2] + (vBuffer[2]*Distance);
	}
	else
	{
		PrintToChat(client, "[SM] %s", "Could not teleport player after respawn");
		CloseHandle(trace);
		return false;
	}
	CloseHandle(trace);
	return true;
}

void PerformTeleport(int client, int target, float pos[3])
{
	pos[2]+=40.0;
	TeleportEntity(target, pos, NULL_VECTOR, NULL_VECTOR);
	
	LogAction(client,target, "\"%L\" teleported \"%L\" after respawning him" , client, target);
}

stock void CheatCommand(int client, char[] command, char arguments[]="")
{
	int userflags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, arguments);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userflags);
}