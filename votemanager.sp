#pragma semicolon 1

#include <sourcemod>
#include <geoip>

#pragma newdecls required

#define PLUGIN_VERSION "1.5.7"
#define TEAM_SPECTATOR 1
#define TEAM_INFECTED 3
#define VOTE_DELAY 5.0
#define VOTE_DURATION 30.0

public Plugin myinfo =
{
	name = "L4D Vote Manager 2",
	author = "Madcap",
	description = "Control permissions on voting and make voting respect admin levels.",
	version = PLUGIN_VERSION,
	url = "http://maats.org"
};

// cvar handles
ConVar	lobbyAccess, difficultyAccess, levelAccess, restartAccess, kickAccess, kickImmunity, sendToLog, vetoAccess, passVoteAccess, voteTimeout,
		voteNoTimeoutAccess, customAccess, voteNotify, survivalMap, survivalLobby, survivalRestart, tankKickImmunity, alltalkAccess, YesNoVoteAnnounce;
 
// custom vote variables
bool inVoteTimeout[MAXPLAYERS+1], hasVoted[MAXPLAYERS+1], customVoteInProgress = false;  
char customVote[128]="";
int customVotesMax, customYesVotes, customNoVotes;

// exploit fix
bool voteInProgress = false;
bool postVoteDelay = false;
//bool playerVoted[MAXPLAYERS+1]; // currently unused, possible future use

public void OnPluginStart()
{
	RegConsoleCmd("custom_vote",CustomVote_Handler);
	RegConsoleCmd("Vote",Vote_Handler);

	RegConsoleCmd("callvote",Callvote_Handler);
	RegConsoleCmd("veto",Veto_Handler);
	RegConsoleCmd("passvote",PassVote_Handler);
	
	lobbyAccess         = CreateConVar("l4d_vote_lobby_access",           "",  "Access level needed to start a return to lobby vote");
	difficultyAccess    = CreateConVar("l4d_vote_difficulty_access",      "",  "Access level needed to start a change difficulty vote");
	levelAccess         = CreateConVar("l4d_vote_level_access",           "",  "Access level needed to start a change level vote");
	restartAccess       = CreateConVar("l4d_vote_restart_access",         "",  "Access level needed to start a restart level vote");
	kickAccess          = CreateConVar("l4d_vote_kick_access",            "",  "Access level needed to start a kick vote");
	kickImmunity        = CreateConVar("l4d_vote_kick_immunity",          "1", "Make votekick respect admin immunity",0,true,0.0,true,1.0);
	vetoAccess          = CreateConVar("l4d_vote_veto_access",            "z", "Access level needed to veto a vote");
	passVoteAccess      = CreateConVar("l4d_vote_pass_access",            "z", "Access level needed to pass a vote");
	voteTimeout         = CreateConVar("l4d_vote_timeout",                "0", "Players must wait (timeout) this many seconds between votes. 0 = no timeout",0,true,0.0);
	voteNoTimeoutAccess = CreateConVar("l4d_vote_no_timeout_access",      "",  "Access level needed to not have vote timeout.");
	sendToLog           = CreateConVar("l4d_vote_log",                    "0", "Log voting data",0,true,0.0,true,1.0);
	customAccess        = CreateConVar("l4d_custom_vote_access",          "z", "Access level needed to call custom votes.");
	voteNotify          = CreateConVar("l4d_vote_notify_access",          "",  "Who sees certain vote related notices. If blank everyone sees them.");
	survivalMap         = CreateConVar("l4d_vote_surv_map_access",        "",  "Access level needed to switch Survival maps.");
	survivalRestart     = CreateConVar("l4d_vote_surv_restart_access",    "",  "Access level needed to restart Survival maps.");
	survivalLobby       = CreateConVar("l4d_vote_surv_lobby_access",      "",  "Access level needed to return to lobby on Survival maps.");
	tankKickImmunity   	= CreateConVar("l4d_vote_tank_kick_immunity",     "1", "Make tanks immune to vote kicking.",0,true,0.0,true,1.0);
	YesNoVoteAnnounce  	= CreateConVar("l4d_Vote_Announce",               "1", "Show clients' Yes or No votes to all",0,true,0.0,true,1.0);
	alltalkAccess	   	= CreateConVar("l4d_vote_alltalk_access",	      "z",  "Access level needed to start an alltalk vote");
	
	//HookEvent("vote_started", EventVoteStart);
	//HookEvent("vote_passed", EventVoteEnd);
	//HookEvent("vote_failed", EventVoteEnd);
	
	AutoExecConfig(true, "votemanager2");

	CreateConVar("l4d_votemanager2", PLUGIN_VERSION, "Version number for Vote Manager 2 Plugin", FCVAR_REPLICATED|FCVAR_NOTIFY);
}


// wrapper for PrintToChatAll
// if client is not 0 then that client will be notified regardless of notify access
public void Notify(int client, char[] format, any ...)
{
	char buffer[512];
	VFormat(buffer,sizeof(buffer),format,3);

	char notify[16];
	GetConVarString(voteNotify, notify, sizeof(notify)); 

	for(int i=1;i<=MaxClients;i++)
	{
		if  (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i) && i!=client && ((strlen(notify)==0) || (GetUserFlagBits(i)&ReadFlagString(notify)!=0)))
		{
			//if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i) && i!=client)
			//{
				PrintToChat(i, buffer);
			//}
		}
	}
	
	if (client>0 && IsClientInGame(client) && IsClientConnected(client) && !IsFakeClient(client))
	{
		PrintToChat(client, buffer);
	}
}


// flip voteInProgress flag when a vote ends
public Action TimerVoteEnd(Handle timer)
{
	voteInProgress = false;
	postVoteDelay = true;
	CreateTimer(VOTE_DELAY, VoteDelay,0,TIMER_FLAG_NO_MAPCHANGE);		
}


// flip voteInProgress after a short while
public Action VoteDelay(Handle timer, int client)
{
	postVoteDelay = false;
}


// reset timeouts every map
public void OnMapStart()
{
	for(int i=0;i<sizeof(inVoteTimeout);i++) 
		inVoteTimeout[i]=false;
		
	customVoteInProgress = false;
	voteInProgress = false;
	postVoteDelay = false;
}


// reset client's timeout value when they connect
public void OnClientConnected(int client)
{
	inVoteTimeout[client]=false;
}


// wrapper logging function with built in checking to see if logging is enabled
public void LogVote(int client, char[] format, any ...)
{

	// sample usage: LogVote(client,"was prevented from starting a %s vote",voteName)

	if (GetConVarBool(sendToLog))
	{
		char buffer[512];
		VFormat(buffer,sizeof(buffer),format,3);
		char name[MAX_NAME_LENGTH]="";
		char steamid[32]="";
			
		if (client==0)
		{
			name="Server";
			steamid="ServerID";
		}
		else
		{
			GetClientName(client,name,sizeof(name));
			GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		}
	
		LogMessage("<%s><%s> %s",name,steamid,buffer);
	
	}
}


// return true if client can make the vote
public int hasVoteAccess(int client, char voteName[32])
{

	// rcon always has access
	if (client==0)
		return true;

	char acclvl[16];
	char gmode[32];
	
	GetConVarString(FindConVar("mp_gamemode"), gmode, sizeof(gmode));

	bool survival = false;
	if (strcmp(gmode, "survival", false) == 0)
		survival=true;
		
	if (strcmp(voteName,"ReturnToLobby",false) == 0) 
	{
		if (survival)
			GetConVarString(survivalLobby,acclvl,sizeof(acclvl));
		else	
			GetConVarString(lobbyAccess,acclvl,sizeof(acclvl));
	}
	else if (strcmp(voteName,"ChangeDifficulty",false) == 0) 
	{
		GetConVarString(difficultyAccess,acclvl,sizeof(acclvl));
	}
	else if (strcmp(voteName,"ChangeMission",false) == 0) 
	{
		GetConVarString(levelAccess,acclvl,sizeof(acclvl));
	}
	else if (strcmp(voteName,"RestartGame",false) == 0) 
	{
		if (survival)
			GetConVarString(survivalRestart,acclvl,sizeof(acclvl));
		else
			GetConVarString(restartAccess,acclvl,sizeof(acclvl));
	}
	else if (strcmp(voteName,"Kick",false) == 0) 
	{
		GetConVarString(kickAccess,acclvl,sizeof(acclvl));
	}
	else if (strcmp(voteName,"Veto",false) == 0) 
	{
		GetConVarString(vetoAccess,acclvl,sizeof(acclvl));
	}
	else if (strcmp(voteName,"PassVote",false) == 0) 
	{
		GetConVarString(passVoteAccess,acclvl,sizeof(acclvl));
	}
	else if (strcmp(voteName,"Custom",false) == 0) 
	{
		GetConVarString(customAccess,acclvl,sizeof(acclvl));
	}
	else if (strcmp(voteName,"ChangeChapter",false) == 0) 
	{
		// can chagnechapter be used outside of survival?
		GetConVarString(survivalMap,acclvl,sizeof(acclvl));	
	}
        else if (strcmp(voteName,"ChangeAllTalk",false) == 0) 
	{
		GetConVarString(alltalkAccess,acclvl,sizeof(acclvl));
	}
	// voteName does not match a known vote type
	else return false;

	// no permissions set
	if (strlen(acclvl) == 0)
		return true;

	// check permissions
	if (GetUserFlagBits(client)&ReadFlagString(acclvl) == 0)
		return false;

	return true;

}


//return true if client is in time out right now (considering access)
public int isInVoteTimeout(int client)
{

	// check if timeout is even activated
	if (GetConVarBool(voteTimeout))
	{
	
		char acclvl[16];
		GetConVarString(voteNoTimeoutAccess,acclvl,sizeof(acclvl));
	
		// if the client is excempt from timeout
		if (GetUserFlagBits(client)&ReadFlagString(acclvl) != 0)
			return false;
			
		return inVoteTimeout[client];
	}
	
	return false;
}


// check a vote name against the known possible votes
public int isValidVote(char voteName[32])
{

	if ((strcmp(voteName,"Kick",false) == 0) ||
		(strcmp(voteName,"ReturnToLobby",false) == 0) ||
		(strcmp(voteName,"ChangeDifficulty",false) == 0) ||
		(strcmp(voteName,"ChangeMission",false) == 0) ||
		(strcmp(voteName,"RestartGame",false) == 0) ||
		(strcmp(voteName,"Custom",false) == 0) ||
		(strcmp(voteName,"ChangeChapter",false) == 0) ||
		(strcmp(voteName,"ChangeAllTalk",false) == 0))
		return true;
		
	return false;	
}


public Action Callvote_Handler(int client, int args)
{

	// return Plugin_Handled;  - to prevent the vote from going through
	// return Plugin_Continue; - to allow the vote to go like normal

	char voteName[32];
	char initiatorName[MAX_NAME_LENGTH];
	GetClientName(client, initiatorName, sizeof(initiatorName));
	GetCmdArg(1,voteName,sizeof(voteName));

	
	// test code
	//char fullCommand[256];
	//GetCmdArgString(fullCommand, sizeof(fullCommand));
	//PrintToChatAll("%s", fullCommand);

	// vote examples:
	// ChangeDifficulty Easy
	// RestartGame
	// ChangeMission Smalltown
	// ChangeChapter 16
	// callvote Kick <client #>

	
	if (voteInProgress)
	{
		PrintToChat(client, "\x04[VOTE] \x01You cannot start a vote until the current vote ends.");
		LogVote(client, "tried starting a %s vote but a vote is in progress.",voteName);
		return Plugin_Handled;
	}

	if (postVoteDelay)
	{
		PrintToChat(client, "\x04[VOTE] \x01Must wait \x03%f seconds \x01between votes.", VOTE_DELAY);
		LogVote(client, "tried starting a %s vote but it is too soon since the last vote.",voteName);
		return Plugin_Handled;
	}
	
	if (!isValidVote(voteName))
	{
	       	PrintToChat(client,"\x04[VOTE] \x01Invalid vote type: %s",voteName);
	       	LogVote(client, "tried to start an invalid vote type: %s", voteName);
	       	return Plugin_Handled;
	}

	if (isInVoteTimeout(client))
	{
		LogVote(client, "cannot start a %s vote.  Reason: Timeout",voteName);
		PrintToChat(client, "\x04[VOTE] \x01You must wait \x03%.1f seconds \x01between votes.",GetConVarFloat(voteTimeout));
		return Plugin_Handled;		
	}

	if (hasVoteAccess(client, voteName))
	{

		//  put them in timeout (even if vote won't go through)
		inVoteTimeout[client]=true;
		
		// set a timer to take them out of timeout
		float timeout = GetConVarFloat(voteTimeout);
		if (timeout > 0.0)
			CreateTimer(timeout, TimeOutOver, client,TIMER_FLAG_NO_MAPCHANGE);

	
		// confirmed player has access to the vote type, now handle any logic for specific types of vote
		// (currently only defined for kick votes)

		if (strcmp(voteName,"Kick",false) == 0)
		{
			// this function must return either Plugin_Handled or Plugin_Continue
			return Kick_Vote_Logic(client, args);
		}
		
		if (strcmp(voteName,"Custom",false) == 0)
		{
			// this function must return either Plugin_Handled or Plugin_Continue
			return Custom_Vote_Logic(client, args);
		}

		voteInProgress = true;
		CreateTimer(VOTE_DURATION,TimerVoteEnd,0,TIMER_FLAG_NO_MAPCHANGE);
		
		// no more custom logic for votes, continue with normal vote behavior
		LogVote(client, "started a %s vote",voteName);
		//PrintToChatAll("\x04[VOTE] \x03%s \x01initiated a \x03%s \x01vote.", initiatorName, voteName);
		Notify(client, "\x04[VOTE] \x03%s \x01initiated a \x03%s \x01vote.", initiatorName, voteName);
		return Plugin_Continue;
				
	}
	else
	{
		// player does not have access to this vote
		LogVote(client, "was prevented from starting a %s vote.  Reason: Access",voteName);
		//PrintToChatAll("\x04[VOTE] \x03%s \x01tried to start a \x03%s \x01vote! Access denied", initiatorName, voteName);
		Notify(client, "\x04[VOTE] \x03%s \x01tried to start a \x03%s \x01vote! Access denied", initiatorName, voteName);
		return Plugin_Handled;
	}

}


public Action TimeOutOver(Handle timer, int client)
{
	inVoteTimeout[client] = false;
}


// special logic for handling kick votes
public Action Kick_Vote_Logic(int client, int args)
{

	// return Plugin_Handled;  - to prevent the vote from going through
	// return Plugin_Continue; - to allow the vote to go like normal

	char initiatorName[MAX_NAME_LENGTH];
	GetClientName(client, initiatorName, sizeof(initiatorName));

	char arg2[12];
	GetCmdArg(2, arg2, sizeof(arg2));
	int target = GetClientOfUserId(StringToInt(arg2));

	// check that the person targeted for kicking is actually a client
	if ((target<=0) || (!IsClientInGame(target)))
	{
		LogVote(client, "was prevented from starting a Kick vote on client %s.  Reason: Invalid Target", arg2);
		Notify(client, "\x04[VOTE] \x03%s \x01tried to start a Kick Vote against \x03%s \x01but that is not a valid target.", initiatorName,arg2);
		PrintToChat(client, "\x04[VOTE] \x01If you are trying to call a manual kick vote the format is: 'callvote kick <user id>'");
		return Plugin_Handled;
	}

	char targetName[MAX_NAME_LENGTH];
	GetClientName(target, targetName, sizeof(targetName));



	// tanks cannot be kicked if the convar is set to 1
	if (GetConVarBool(tankKickImmunity) && (GetClientTeam(target) == TEAM_INFECTED) && IsPlayerAlive(target))
	{
		char model[128];
		GetClientModel(target, model, sizeof(model));
		if (StrContains(model, "hulk", false) > 0)
		{
			LogVote(client, "was prevented from starting a Kick vote on %s.  Reason: Tank", targetName);
			//PrintToChatAll("\x04[VOTE] \x03%s \x01tried to start a Kick Vote against \x03%s \x01but tanks cannot be kicked.",initiatorName,targetName);
			Notify(client,"\x04[VOTE] \x03%s \x01tried to start a Kick Vote against \x03%s \x01but tanks cannot be kicked.",initiatorName,targetName);
			return Plugin_Handled;
		}
	}
	
	// Forbid Spectator team from kicking
	if (GetClientTeam(client) == TEAM_SPECTATOR)
	{
		LogVote(client, "was prevented from starting a Kick vote on %s.  Reason: Spectator", targetName);
		//PrintToChatAll("\x04[VOTE] \x03%s \x01tried to start a Kick Vote against \x03%s \x01but spectators are not allowed to kick.",initiatorName,targetName);
		Notify(client, "\x04[VOTE] \x03%s \x01tried to start a Kick Vote against \x03%s \x01but spectators are not allowed to kick.",initiatorName,targetName);
		return Plugin_Handled;
	}

        // If the "kickImmunity" flag is set, we have to check admin rights of the client and target
	if (GetConVarBool(kickImmunity))
	{
		//player log file code. name and steamid only
		char steamid[128];
	
		GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
		if (FindAdminByIdentity(AUTHMETHOD_STEAM, steamid) != INVALID_ADMIN_ID)
		{
                	// client does not have permisison to kick target
			LogVote(client, "was prevented from starting a Kick vote on %s.  Reason: Target Immunity", targetName);
			//PrintToChatAll("\x04[VOTE] \x03%s \x01tried to start a Kick Vote against \x03%s \x01but failed.",initiatorName,targetName);
			Notify(client, "\x04[VOTE] \x03%s \x01tried to start a Kick Vote against \x03%s \x01but failed.",initiatorName,targetName);
			return Plugin_Handled;
	        }
	}
	
	voteInProgress = true;
	CreateTimer(VOTE_DURATION,TimerVoteEnd,0,TIMER_FLAG_NO_MAPCHANGE);
	
	LogVote(client, "started a Kick vote on %s.",targetName);
	//PrintToChatAll("\x04[VOTE] \x03%s \x01is starting a Kick Vote against \x03%s",initiatorName,targetName);
	Notify(client, "\x04[VOTE] \x03%s \x01is starting a Kick Vote against \x03%s",initiatorName,targetName);
	return Plugin_Continue;
}


public Action Veto_Handler(int client, int args)
{
	
	if (!voteInProgress || postVoteDelay) 
	{
		LogVote(client, "vetoed but there is no current vote.");
		if (client!=0)
		{
			PrintToChat(client, "\x04[VOTE] \x01No current vote to veto."); 
		}
		
		return Plugin_Handled;
	}
	
	// special case, if someone does `rcon veto` instead of just `veto` then the veto comes from the server
	// anyone with rcon access would have full access to veto?
	if (client==0)
	{

		Veto();
	
		LogVote(client,"has vetoed a vote.");
		PrintToChatAll("\x04[VOTE] \x03CONSOLE \x01has vetoed this vote.");
		//Notify(0, "\x04[VOTE] \x03CONSOLE \x01has vetoed this vote.");
		return Plugin_Continue;
	
	}

	char vetoerName[MAX_NAME_LENGTH];	
	GetClientName(client, vetoerName, sizeof(vetoerName));
	
	if (hasVoteAccess(client, "Veto"))
	{	
		Veto();
		
		LogVote(client,"has vetoed a vote.");
		//PrintToChatAll("\x04[VOTE] \x03%s \x01has vetoed this vote.",vetoerName);
		Notify(client, "\x04[VOTE] \x03%s \x01has vetoed this vote.",vetoerName);
		return Plugin_Continue;
		
	}
	LogVote(client,"failed to veto vote. Reason: Access");
	//PrintToChatAll("\x04[VOTE] \x03%s \x01tried to veto a vote but failed.",vetoerName);
	Notify(client, "\x04[VOTE] \x03%s \x01tried to veto a vote but failed.",vetoerName);
	return Plugin_Handled;
}


public void Veto()
{
	int count=MaxClients;
	for(int i=1;i<=count;i++)
	{
		if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
		{
			FakeClientCommandEx(i,"Vote No");
		}
	}
}


public Action PassVote_Handler(int client, int args)
{

	if (!voteInProgress || postVoteDelay) 
	{
		LogVote(client, "passed the vote but there is no current vote.");
		if (client!=0)
		{
			PrintToChat(client, "\x04[VOTE] \x01No current vote to pass."); 
		}
		return Plugin_Handled;
	}
	
	// special case, if someone does `rcon passvote` instead of just `passvote` then the veto comes from the server
	// anyone with rcon access would have full access to veto?
	if (client==0)
	{

		PassVote();
	
		LogVote(client,"has passed a vote.");
		PrintToChatAll("\x04[VOTE] \x03CONSOLE \x01passed this vote.");
		//Notify(0, "\x04[VOTE] \x03CONSOLE \x01passed this vote.");
		return Plugin_Continue;
	
	}

	char passerName[MAX_NAME_LENGTH];	
	GetClientName(client, passerName, sizeof(passerName));
	
	if (hasVoteAccess(client, "PassVote"))
	{	
		PassVote();
		
		LogVote(client,"has passed a vote.");
		//PrintToChatAll("\x04[VOTE] \x03%s \x01has passed this vote.",passerName);
		Notify(client, "\x04[VOTE] \x03%s \x01has passed this vote.",passerName);
		return Plugin_Continue;
		
	}
	LogVote(client,"failed to veto vote. Reason: Access");
	//PrintToChatAll("\x04[VOTE] \x03%s \x01tried to pass a vote but failed.",passerName);
	Notify(client, "\x04[VOTE] \x03%s \x01tried to pass a vote but failed.",passerName);
	return Plugin_Handled;
}


public void PassVote()
{
	int count=MaxClients;
	for(int i=1;i<=count;i++)
	{
		if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
		{
			FakeClientCommandEx(i,"Vote Yes");
		}
	}
}


public Action CustomVote_Handler(int client, int args)
{
	// no checking needed here, everything will be checked in due time
	
	char initiatorName[MAX_NAME_LENGTH];
	GetClientName(client, initiatorName, sizeof(initiatorName));
	
	// can't start a new vote while we're in one already
	if (!voteInProgress)
	{

		int leng1=GetCmdArg(1, customVote, sizeof(customVote));
		
		if (leng1==0)
		{
			PrintToConsole(client, "Usage: custom_vote \"<question to vote on>\" ");
			return Plugin_Handled;
		}
		
		// determine who can vote on this
		int i;
		customVotesMax=0;
		for(i=1;i<sizeof(hasVoted);i++)
		{
			hasVoted[i]=true;
			
			if (i<=MaxClients && IsClientConnected(i) && !IsFakeClient(i))
			{
				customVotesMax++;
				hasVoted[i]=false;
			}
		}
		
		customNoVotes=0;
		customYesVotes=0;

		LogVote(client,"attempting custom vote. Issue: %s ", customVote);
		
		FakeClientCommandEx(client, "callvote Custom"); 

	}
	else
	{
		LogVote(client, "tried to start a Custom vote but one is already in progress.");
		//PrintToChatAll("\x04[VOTE] \x03%s \x01tried starting a Custom vote but one is already in progress.",initiatorName);
		Notify(client, "\x04[VOTE] \x03%s \x01tried starting a Custom vote but one is already in progress.",initiatorName);
	}
	
	return Plugin_Handled;
}


public Action Custom_Vote_Logic(int client, int args)
{

	char initiatorName[MAX_NAME_LENGTH];
	GetClientName(client, initiatorName, sizeof(initiatorName));

	if (!customVoteInProgress)
	{
		Handle voteEvent = CreateEvent("vote_started");
		SetEventString(voteEvent,"issue","#L4D_TargetID_Player");
		SetEventString(voteEvent,"param1",customVote);
		SetEventInt(voteEvent,"team",-1);
		SetEventInt(voteEvent,"initiator",GetClientUserId(client));
		FireEvent(voteEvent);
		
		Handle voteChangeEvent = CreateEvent("vote_changed");
		SetEventInt(voteChangeEvent,"yesVotes",0);
		SetEventInt(voteChangeEvent,"noVotes",0);
		SetEventInt(voteChangeEvent,"potentialVotes",customVotesMax);
		FireEvent(voteChangeEvent);

		// just like the built in behavior, the initiator votes yes
		FakeClientCommandEx(client,"Vote Yes");
		
		voteInProgress = true;
		CreateTimer(VOTE_DURATION,TimerVoteEnd,0,TIMER_FLAG_NO_MAPCHANGE);
		
		LogVote(client, "started a Custom vote.");
		//PrintToChatAll("\x04[VOTE] \x03%s \x01is starting a Custom vote.",initiatorName);
		Notify(client, "\x04[VOTE] \x03%s \x01is starting a Custom vote.",initiatorName);
		
		CreateTimer(30.0, EndCustomVote, client,TIMER_FLAG_NO_MAPCHANGE);
		
		customVoteInProgress=true;
		
	}	
	
	return Plugin_Handled;
}


public Action Vote_Handler(int client, int args)
{

	char voterName[MAX_NAME_LENGTH];
	GetClientName(client, voterName, sizeof(voterName));
	

	char vote[8];
	GetCmdArg(1,vote,sizeof(vote));
	if (GetConVarBool(YesNoVoteAnnounce) && voteInProgress && !hasVoted[client])
	{
	PrintToChatAll("\x04[VOTE] \x03%s \x01voted \x03%s.",voterName,vote);	
    }
	// if it's a custom vote handle it specially
	if (customVoteInProgress && !hasVoted[client])
	{
		
		if (strcmp(vote,"Yes",true) == 0)
		{
			customYesVotes++;
		}
		else if (strcmp(vote,"No",true) == 0)
		{
			customNoVotes++;
		}
		
		hasVoted[client]=true;

		Handle voteChangeEvent = CreateEvent("vote_changed");
		SetEventInt(voteChangeEvent,"yesVotes",customYesVotes);
		SetEventInt(voteChangeEvent,"noVotes",customNoVotes);
		SetEventInt(voteChangeEvent,"potentialVotes",customVotesMax);
		FireEvent(voteChangeEvent);

		if ((customYesVotes+customNoVotes)==customVotesMax)
		{
			CreateTimer(2.0, EndCustomVote, client,TIMER_FLAG_NO_MAPCHANGE);
		}
	
		return Plugin_Handled;
		
	}

	// otherwise do normal behavior
	return Plugin_Continue;
}


// after a certain amount of time just end the vote regardless
public Action EndCustomVote(Handle timer, int client)
{

	if (customVoteInProgress)
	{

		Handle voteEndEvent = CreateEvent("vote_ended");
		FireEvent(voteEndEvent);
	
		if (customYesVotes > customNoVotes)
		{
			char param1[128];
			Format(param1, sizeof(param1), "Vote succeeds: %s", customVote);
		
			Handle votePassEvent = CreateEvent("vote_passed");
			SetEventString(votePassEvent,"details","#L4D_TargetID_Player");
			SetEventString(votePassEvent,"param1",param1);
			SetEventInt(votePassEvent,"team",-1);
			FireEvent(votePassEvent);
		
			LogVote(client, "Custom vote passed. Vote:%s ",customVote);
				
		}
		else
		{				
			Handle voteFailEvent = CreateEvent("vote_failed");
			SetEventInt(voteFailEvent,"team",0);
			FireEvent(voteFailEvent);
		
			LogVote(client, "Custom vote failed. Vote:%s ",customVote);
		}
	
	}
	customVoteInProgress=false;
}