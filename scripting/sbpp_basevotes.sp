#pragma semicolon 1

#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <sourcebanspp>
#include <sourcecomms>
#include <sbpp_basevotes>
#include <autoexecconfig>

#pragma newdecls required

public Plugin myinfo =
{
	name = "[SBPP] Basic Votes",
	author = "ampere",
	description = "Fork of SourceMod's Basic Votes plugin to support SourceBans++",
	version = "1.1",
	url = "github.com/maxijabase"
};

#define VOTE_NO "###no###"
#define VOTE_YES "###yes###"

#define GENERIC_COUNT 5
#define ANSWER_SIZE 64

Menu g_hVoteMenu = null;

ConVar g_Cvar_Limits[5] = {null, ...};
ConVar g_Cvar_Voteban = null;
ConVar g_Cvar_Votemute = null;
ConVar g_Cvar_Votegag = null;
ConVar g_Cvar_RequireReason = null;
ConVar g_Cvar_ReasonTimeout = null;
//ConVar g_Cvar_VoteSay = null;

enum VoteType
{
	VoteType_Map,
	VoteType_Kick,
	VoteType_Ban,
	VoteType_Mute,
	VoteType_Gag,
	VoteType_Question
}

VoteType g_voteType = VoteType_Question;

// Menu API does not provide us with a way to pass multiple peices of data with a single
// choice, so some globals are used to hold stuff.
//
int g_voteTarget;		/* Holds the target's user id */

#define VOTE_NAME	0
#define VOTE_AUTHID	1
#define	VOTE_IP		2
char g_voteInfo[3][65];	/* Holds the target's name, authid, and IP */

char g_voteArg[256];	/* Used to hold ban/kick reasons or vote questions */

// Reason requirement system
bool g_bWaitingForReason[MAXPLAYERS + 1];	/* Tracks if player needs to provide reason */
int g_iReasonTarget[MAXPLAYERS + 1];		/* Target userid for the reason */
SBPP_VoteType g_eReasonVoteType[MAXPLAYERS + 1];	/* Type of vote requiring reason */
Handle g_hReasonTimeout[MAXPLAYERS + 1];	/* Timeout timer for reason waiting */

// Global forwards
GlobalForward g_hFwd_OnVoteInitiated;
GlobalForward g_hFwd_OnVoteInitiated_Post;
GlobalForward g_hFwd_OnPlayerVoted;
GlobalForward g_hFwd_OnVoteEnded;
GlobalForward g_hFwd_OnVoteActionExecute;
GlobalForward g_hFwd_OnVoteActionExecute_Post;

TopMenu hTopMenu;

#include "basevotes/sbpp_votekick.sp"
#include "basevotes/sbpp_voteban.sp"
#include "basevotes/sbpp_votemap.sp"
#include "basevotes/sbpp_votecomms.sp"

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("basevotes.phrases");
	LoadTranslations("plugin.basecommands");
	LoadTranslations("basebans.phrases");
	
	// Create global forwards
	g_hFwd_OnVoteInitiated = new GlobalForward("SBPP_OnVoteInitiated", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_String, Param_String);
	g_hFwd_OnVoteInitiated_Post = new GlobalForward("SBPP_OnVoteInitiated_Post", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String, Param_String);
	g_hFwd_OnPlayerVoted = new GlobalForward("SBPP_OnPlayerVoted", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String);
	g_hFwd_OnVoteEnded = new GlobalForward("SBPP_OnVoteEnded", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String, Param_String, Param_String, Param_Cell, Param_Cell, Param_Cell, Param_Float);
	g_hFwd_OnVoteActionExecute = new GlobalForward("SBPP_OnVoteActionExecute", ET_Event, Param_Cell, Param_Cell, Param_String, Param_String, Param_String, Param_Cell);
	g_hFwd_OnVoteActionExecute_Post = new GlobalForward("SBPP_OnVoteActionExecute_Post", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_String, Param_String, Param_Cell);
	
	RegAdminCmd("sm_votemap", Command_Votemap, ADMFLAG_VOTE|ADMFLAG_CHANGEMAP, "sm_votemap <mapname> [mapname2] ... [mapname5] ");
	RegAdminCmd("sm_votekick", Command_Votekick, ADMFLAG_VOTE|ADMFLAG_KICK, "sm_votekick <player> [reason]");
	RegAdminCmd("sm_voteban", Command_Voteban, ADMFLAG_VOTE|ADMFLAG_BAN, "sm_voteban <player> [reason]");
	RegAdminCmd("sm_votemute", Command_Votemute, ADMFLAG_VOTE|ADMFLAG_CHAT, "sm_votemute <player> [reason]");
	RegAdminCmd("sm_votegag", Command_Votegag, ADMFLAG_VOTE|ADMFLAG_CHAT, "sm_votegag <player> [reason]");
	RegAdminCmd("sm_vote", Command_Vote, ADMFLAG_VOTE, "sm_vote <question> [Answer1] [Answer2] ... [Answer5]");

	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("basevotes");

	g_Cvar_Limits[0] = AutoExecConfig_CreateConVar("sm_vote_map", "0.60", "percent required for successful map vote.", 0, true, 0.05, true, 1.0);
	g_Cvar_Limits[1] = AutoExecConfig_CreateConVar("sm_vote_kick", "0.60", "percent required for successful kick vote.", 0, true, 0.05, true, 1.0);	
	g_Cvar_Limits[2] = AutoExecConfig_CreateConVar("sm_vote_ban", "0.60", "percent required for successful ban vote.", 0, true, 0.05, true, 1.0);
	g_Cvar_Limits[3] = AutoExecConfig_CreateConVar("sm_vote_mute", "0.60", "percent required for successful mute vote.", 0, true, 0.05, true, 1.0);
	g_Cvar_Limits[4] = AutoExecConfig_CreateConVar("sm_vote_gag", "0.60", "percent required for successful gag vote.", 0, true, 0.05, true, 1.0);
	g_Cvar_Voteban = AutoExecConfig_CreateConVar("sm_voteban_time", "30", "length of ban in minutes.", 0, true, 0.0);
	g_Cvar_Votemute = AutoExecConfig_CreateConVar("sm_votemute_time", "30", "length of mute in minutes.", 0, true, 0.0);
	g_Cvar_Votegag = AutoExecConfig_CreateConVar("sm_votegag_time", "30", "length of gag in minutes.", 0, true, 0.0);
	g_Cvar_RequireReason = AutoExecConfig_CreateConVar("sm_vote_require_reason", "1", "Require players to provide a written reason for voteban/votekick commands.", 0, true, 0.0, true, 1.0);
	g_Cvar_ReasonTimeout = AutoExecConfig_CreateConVar("sm_vote_reason_timeout", "30", "Timeout in seconds for players to provide a reason for voteban/votekick commands.", 0, true, 5.0, true, 300.0);	

	AutoExecConfig_CleanFile();
	AutoExecConfig_ExecuteFile();
	
	/* Account for late loading */
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(topmenu);
	}
	
	g_SelectedMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	g_MapList = new Menu(MenuHandler_Map, MenuAction_DrawItem|MenuAction_Display);
	g_MapList.SetTitle("%T", "Please select a map", LANG_SERVER);
	g_MapList.ExitBackButton = true;
	
	char mapListPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, mapListPath, sizeof(mapListPath), "configs/adminmenu_maplist.ini");
	SetMapListCompatBind("sm_votemap menu", mapListPath);
}

public void OnConfigsExecuted()
{
	if (!LibraryExists("sourcebans++"))
	{
		SetFailState("SourceBans++ library not found");
	}

	if (!LibraryExists("sourcecomms++"))
	{
		SetFailState("SourceComms++ library not found");
	}
}

public void OnAllPluginsLoaded()
{
	// Check for conflicting stock basevotes plugin
	char filename[200];
	BuildPath(Path_SM, filename, sizeof(filename), "plugins/basevotes.smx");
	if (FileExists(filename))
	{
		char disabledPath[200];
		BuildPath(Path_SM, disabledPath, sizeof(disabledPath), "plugins/disabled");
		
		// Create disabled folder if it doesn't exist
		if (!DirExists(disabledPath))
		{
			CreateDirectory(disabledPath, 511);
		}
		
		char newfilename[200];
		BuildPath(Path_SM, newfilename, sizeof(newfilename), "plugins/disabled/basevotes.smx");
		
		ServerCommand("sm plugins unload basevotes");
		
		if (FileExists(newfilename))
		{
			DeleteFile(newfilename);
		}
		
		if (RenameFile(newfilename, filename))
		{
			LogMessage("Stock basevotes.smx was unloaded and moved to plugins/disabled/basevotes.smx");
		}
	}
	
	g_mapCount = LoadMapList(g_MapList);
}

public void OnClientDisconnect(int client)
{
	// Clear reason waiting state when player disconnects
	ClearReasonWaiting(client);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// Check if this player is waiting to provide a reason
	if (g_bWaitingForReason[client] && IsClientInGame(client))
	{
		// Get the target player
		int target = GetClientOfUserId(g_iReasonTarget[client]);
		
		// Check if target is still valid
		if (target == 0)
		{
			PrintToChat(client, "[SM] %t", "Player no longer available");
			ClearReasonWaiting(client);
			return Plugin_Handled;
		}
		
		// Store the reason and proceed with the vote
		strcopy(g_voteArg, sizeof(g_voteArg), sArgs);
		
		// Clear the waiting state
		ClearReasonWaiting(client);
		
		// Proceed with the vote based on type
		switch (g_eReasonVoteType[client])
		{
			case SBPP_VoteType_Ban:
			{
				DisplayVoteBanMenu(client, target);
			}
			case SBPP_VoteType_Kick:
			{
				DisplayVoteKickMenu(client, target);
			}
		}
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void OnAdminMenuReady(Handle aTopMenu)
{
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

	/* Block us from being called twice */
	if (topmenu == hTopMenu)
	{
		return;
	}
	
	/* Save the Handle */
	hTopMenu = topmenu;
	
	/* Build the "Voting Commands" category */
	TopMenuObject voting_commands = hTopMenu.FindCategory(ADMINMENU_VOTINGCOMMANDS);

	if (voting_commands != INVALID_TOPMENUOBJECT)
	{
		hTopMenu.AddItem("sm_votekick", AdminMenu_VoteKick, voting_commands, "sm_votekick", ADMFLAG_VOTE|ADMFLAG_KICK);
		hTopMenu.AddItem("sm_voteban", AdminMenu_VoteBan, voting_commands, "sm_voteban", ADMFLAG_VOTE|ADMFLAG_BAN);
		hTopMenu.AddItem("sm_votemute", AdminMenu_VoteMute, voting_commands, "sm_votemute", ADMFLAG_VOTE|ADMFLAG_CHAT);
		hTopMenu.AddItem("sm_votegag", AdminMenu_VoteGag, voting_commands, "sm_votegag", ADMFLAG_VOTE|ADMFLAG_CHAT);
		hTopMenu.AddItem("sm_votemap", AdminMenu_VoteMap, voting_commands, "sm_votemap", ADMFLAG_VOTE|ADMFLAG_CHANGEMAP);
	}
}

public Action Command_Vote(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_vote <question> [Answer1] [Answer2] ... [Answer5]");
		return Plugin_Handled;	
	}
	
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] %t", "Vote in Progress");
		return Plugin_Handled;
	}
		
	if (!TestVoteDelay(client))
	{
		return Plugin_Handled;
	}
	
	char text[256];
	GetCmdArgString(text, sizeof(text));

	char answers[GENERIC_COUNT][ANSWER_SIZE];
	int answerCount;	
	int len = BreakString(text, g_voteArg, sizeof(g_voteArg));
	int pos = len;
	
	char answers_list[GENERIC_COUNT * (ANSWER_SIZE + 3)];
	
	while (args > 1 && pos != -1 && answerCount < GENERIC_COUNT)
	{	
		pos = BreakString(text[len], answers[answerCount], sizeof(answers[]));
		answerCount++;
		
		if (pos != -1)
		{
			len += pos;
		}	
	}
	g_voteType = VoteType_Question;
	
	g_hVoteMenu = new Menu(Handler_VoteCallback, MENU_ACTIONS_ALL);
	g_hVoteMenu.SetTitle("%s", g_voteArg);
	
	if (answerCount < 2)
	{
		g_hVoteMenu.AddItem(VOTE_YES, "Yes");
		g_hVoteMenu.AddItem(VOTE_NO, "No");
		Format(answers_list, sizeof(answers_list), " \"Yes\" \"No\"");
	}
	else
	{
		for (int i = 0; i < answerCount; i++)
		{
			g_hVoteMenu.AddItem(answers[i], answers[i]);
			Format(answers_list, sizeof(answers_list), "%s \"%s\"", answers_list, answers[i]);
		}	
	}
	
	LogAction(client, -1, "\"%L\" initiated a generic vote (question \"%s\" / answers%s).", client, g_voteArg, answers_list);
	ShowActivity2(client, "[SM] ", "%t", "Initiate Vote", g_voteArg);
	
	g_hVoteMenu.ExitButton = false;
	g_hVoteMenu.DisplayVoteToAll(20);		
	
	return Plugin_Handled;	
}

public int Handler_VoteCallback(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete g_hVoteMenu;
	}
	else if (action == MenuAction_Select)
	{
		// Track individual player votes - param1 = client, param2 = item index
		if (g_voteType != VoteType_Question && IsClientInGame(param1))
		{
			char item[64];
			menu.GetItem(param2, item, sizeof(item));
			
			// Determine if they voted yes or no
			SBPP_VoteChoice choice = view_as<SBPP_VoteChoice>(strcmp(item, VOTE_YES) == 0 || param2 == 0);
			
			// Call the forward
			Forward_OnPlayerVoted(param1, view_as<SBPP_VoteType>(g_voteType), choice, g_voteInfo[VOTE_NAME]);
		}
	}
	else if (action == MenuAction_Display)
	{
	 	if (g_voteType != VoteType_Question)
	 	{
			char title[64];
			menu.GetTitle(title, sizeof(title));
			
	 		char buffer[255];
			Format(buffer, sizeof(buffer), "%T", title, param1, g_voteInfo[VOTE_NAME]);

			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(buffer);
		}
	}
	else if (action == MenuAction_DisplayItem)
	{
		char display[64];
		menu.GetItem(param2, "", 0, _, display, sizeof(display));
	 
	 	if (strcmp(display, "No") == 0 || strcmp(display, "Yes") == 0)
	 	{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", display, param1);

			return RedrawMenuItem(buffer);
		}
	}
	/* else if (action == MenuAction_Select)
	{
		VoteSelect(menu, param1, param2);
	}*/
	else if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
	{
		PrintToChatAll("[SM] %t", "No Votes Cast");
	}	
	else if (action == MenuAction_VoteEnd)
	{
		char item[PLATFORM_MAX_PATH], display[64];
		float percent, limit;
		int votes, totalVotes;

		GetMenuVoteInfo(param2, votes, totalVotes);
		menu.GetItem(param1, item, sizeof(item), _, display, sizeof(display));
		
		if (strcmp(item, VOTE_NO) == 0 && param1 == 1)
		{
			votes = totalVotes - votes; // Reverse the votes to be in relation to the Yes option.
		}
		
		percent = float(votes) / float(totalVotes);
		
		if (g_voteType != VoteType_Question)
		{
			limit = g_Cvar_Limits[g_voteType].FloatValue;
		}
		
		// A multi-argument vote is "always successful", but have to check if its a Yes/No vote.
		if ((strcmp(item, VOTE_YES) == 0 && FloatCompare(percent,limit) < 0 && param1 == 0) || (strcmp(item, VOTE_NO) == 0 && param1 == 1))
		{
			/* :TODO: g_voteTarget should be used here and set to -1 if not applicable.
			 */
			LogAction(-1, -1, "Vote failed. %d%% vote required. (Received \"%d\"% of %d votes)", RoundToNearest(100.0*limit), RoundToNearest(100.0*percent), totalVotes);
			PrintToChatAll("[SM] %t", "Vote Failed", RoundToNearest(100.0*limit), RoundToNearest(100.0*percent), totalVotes);
			
			// Call OnVoteEnded forward for failed votes
			if (g_voteType != VoteType_Question)
			{
				int voteTarget = GetClientOfUserId(g_voteTarget);
				Forward_OnVoteEnded(view_as<SBPP_VoteType>(g_voteType), SBPP_VoteResult_Failed, voteTarget, 
								   g_voteInfo[VOTE_NAME], g_voteInfo[VOTE_AUTHID], g_voteArg, 
								   votes, totalVotes - votes, totalVotes, percent);
			}
		}
		else
		{
			LogAction(-1, -1, "Vote successful. (Received \"%d\"% of %d votes)", RoundToNearest(100.0*percent), totalVotes);
			PrintToChatAll("[SM] %t", "Vote Successful", RoundToNearest(100.0*percent), totalVotes);
			
			switch (g_voteType)
			{
				case VoteType_Question:
				{
					if (strcmp(item, VOTE_NO) == 0 || strcmp(item, VOTE_YES) == 0)
					{
						strcopy(item, sizeof(item), display);
					}

					LogAction(-1, -1, "The answer to %s is: %s.", g_voteArg, item);
					PrintToChatAll("[SM] %t", "Vote End", g_voteArg, item);
				}
				
				case VoteType_Map:
				{
					// single-vote items don't use the display item
					char displayName[PLATFORM_MAX_PATH];
					GetMapDisplayName(item, displayName, sizeof(displayName));
					LogAction(-1, -1, "Changing map to %s due to vote.", item);
					PrintToChatAll("[SM] %t", "Changing map", displayName);
					DataPack dp;
					CreateDataTimer(5.0, Timer_ChangeMap, dp);
					dp.WriteString(item);		
				}
					
				case VoteType_Kick:
				{
					int voteTarget;
					if((voteTarget = GetClientOfUserId(g_voteTarget)) == 0)
					{
						LogAction(-1, -1, "Vote kick failed, unable to kick \"%s\" (reason \"%s\")", g_voteInfo[VOTE_NAME], "Player no longer available");
					}
					else
					{
						if (g_voteArg[0] == '\0')
						{
							strcopy(g_voteArg, sizeof(g_voteArg), "Votekicked");
						}
						
						// Call OnVoteEnded forward
						Forward_OnVoteEnded(SBPP_VoteType_Kick, SBPP_VoteResult_Success, voteTarget, 
										   g_voteInfo[VOTE_NAME], "", g_voteArg, 
										   votes, totalVotes - votes, totalVotes, percent);
						
						// Call OnVoteActionExecute forward
						Action result = Forward_OnVoteActionExecute(SBPP_VoteType_Kick, voteTarget, 
																	g_voteInfo[VOTE_NAME], "", g_voteArg, -1);
						
						if (result == Plugin_Continue)
						{
							PrintToChatAll("[SM] %t", "Kicked target", "_s", g_voteInfo[VOTE_NAME]);					
							LogAction(-1, voteTarget, "Vote kick successful, kicked \"%L\" (reason \"%s\")", voteTarget, g_voteArg);
							
							ServerCommand("kickid %d \"%s\"", g_voteTarget, g_voteArg);
							
							// Call OnVoteActionExecute_Post forward
							Forward_OnVoteActionExecute_Post(SBPP_VoteType_Kick, voteTarget, 
															g_voteInfo[VOTE_NAME], "", g_voteArg, -1);
						}
					}
				}
					
				case VoteType_Ban:
				{
					if (g_voteArg[0] == '\0')
					{
						strcopy(g_voteArg, sizeof(g_voteArg), "Votebanned");
					}
					
					int minutes = g_Cvar_Voteban.IntValue;
					int voteTarget;
					voteTarget = GetClientOfUserId(g_voteTarget);
					
					// Call OnVoteEnded forward
					Forward_OnVoteEnded(SBPP_VoteType_Ban, SBPP_VoteResult_Success, voteTarget, 
									   g_voteInfo[VOTE_NAME], g_voteInfo[VOTE_AUTHID], g_voteArg, 
									   votes, totalVotes - votes, totalVotes, percent);
					
					// Call OnVoteActionExecute forward
					Action result = Forward_OnVoteActionExecute(SBPP_VoteType_Ban, voteTarget, 
																g_voteInfo[VOTE_NAME], g_voteInfo[VOTE_AUTHID], 
																g_voteArg, minutes);
					
					if (result == Plugin_Continue)
					{
						PrintToChatAll("[SM] %t", "Banned player", g_voteInfo[VOTE_NAME], minutes);
						
						if(voteTarget == 0)
						{
							LogAction(-1, -1, "Vote ban successful, banned \"%s\" (%s) (minutes \"%d\") (reason \"%s\")", g_voteInfo[VOTE_NAME], g_voteInfo[VOTE_AUTHID], minutes, g_voteArg);
							
							// Player disconnected, use stock ban method as SourceBans++ requires valid client
							BanIdentity(g_voteInfo[VOTE_AUTHID],
									  minutes,
									  BANFLAG_AUTHID,
									  g_voteArg,
									  "sm_voteban");
						}
						else
						{
							LogAction(-1, voteTarget, "Vote ban successful, banned \"%L\" (minutes \"%d\") (reason \"%s\")", voteTarget, minutes, g_voteArg);
							
							// Use SourceBans++ to ban the player
							SBPP_BanPlayer(0, voteTarget, minutes, g_voteArg);
						}
						
						// Call OnVoteActionExecute_Post forward
						Forward_OnVoteActionExecute_Post(SBPP_VoteType_Ban, voteTarget, 
														g_voteInfo[VOTE_NAME], g_voteInfo[VOTE_AUTHID], 
														g_voteArg, minutes);
					}
				}
				
				case VoteType_Mute:
				{
					if (g_voteArg[0] == '\0')
					{
						strcopy(g_voteArg, sizeof(g_voteArg), "Votemuted");
					}
					
					int minutes = g_Cvar_Votemute.IntValue;
					int voteTarget;
					voteTarget = GetClientOfUserId(g_voteTarget);
					
					// Call OnVoteEnded forward
					Forward_OnVoteEnded(SBPP_VoteType_Mute, SBPP_VoteResult_Success, voteTarget, 
									   g_voteInfo[VOTE_NAME], "", g_voteArg, 
									   votes, totalVotes - votes, totalVotes, percent);
					
					if(voteTarget == 0)
					{
						LogAction(-1, -1, "Vote mute failed, unable to mute \"%s\" (reason \"%s\")", g_voteInfo[VOTE_NAME], "Player no longer available");
						PrintToChatAll("[SM] Vote mute failed, player no longer available.");
					}
					else
					{
						// Call OnVoteActionExecute forward
						Action result = Forward_OnVoteActionExecute(SBPP_VoteType_Mute, voteTarget, 
																	g_voteInfo[VOTE_NAME], "", g_voteArg, minutes);
						
						if (result == Plugin_Continue)
						{
							LogAction(-1, voteTarget, "Vote mute successful, muted \"%L\" (minutes \"%d\") (reason \"%s\")", voteTarget, minutes, g_voteArg);
							PrintToChatAll("[SM] %t", "Muted target", "_s", g_voteInfo[VOTE_NAME]);
							
							// Use SourceComms to mute the player
							SourceComms_SetClientMute(voteTarget, true, minutes, true, g_voteArg);
							
							// Call OnVoteActionExecute_Post forward
							Forward_OnVoteActionExecute_Post(SBPP_VoteType_Mute, voteTarget, 
															g_voteInfo[VOTE_NAME], "", g_voteArg, minutes);
						}
					}
				}
				
				case VoteType_Gag:
				{
					if (g_voteArg[0] == '\0')
					{
						strcopy(g_voteArg, sizeof(g_voteArg), "Votegagged");
					}
					
					int minutes = g_Cvar_Votegag.IntValue;
					int voteTarget;
					voteTarget = GetClientOfUserId(g_voteTarget);
					
					// Call OnVoteEnded forward
					Forward_OnVoteEnded(SBPP_VoteType_Gag, SBPP_VoteResult_Success, voteTarget, 
									   g_voteInfo[VOTE_NAME], "", g_voteArg, 
									   votes, totalVotes - votes, totalVotes, percent);
					
					if(voteTarget == 0)
					{
						LogAction(-1, -1, "Vote gag failed, unable to gag \"%s\" (reason \"%s\")", g_voteInfo[VOTE_NAME], "Player no longer available");
						PrintToChatAll("[SM] Vote gag failed, player no longer available.");
					}
					else
					{
						// Call OnVoteActionExecute forward
						Action result = Forward_OnVoteActionExecute(SBPP_VoteType_Gag, voteTarget, 
																	g_voteInfo[VOTE_NAME], "", g_voteArg, minutes);
						
						if (result == Plugin_Continue)
						{
							LogAction(-1, voteTarget, "Vote gag successful, gagged \"%L\" (minutes \"%d\") (reason \"%s\")", voteTarget, minutes, g_voteArg);
							PrintToChatAll("[SM] %t", "Gagged target", "_s", g_voteInfo[VOTE_NAME]);
							
							// Use SourceComms to gag the player
							SourceComms_SetClientGag(voteTarget, true, minutes, true, g_voteArg);
							
							// Call OnVoteActionExecute_Post forward
							Forward_OnVoteActionExecute_Post(SBPP_VoteType_Gag, voteTarget, 
															g_voteInfo[VOTE_NAME], "", g_voteArg, minutes);
						}
					}
				}
			}
		}
	}
	
	return 0;
}

/*
void VoteSelect(Menu menu, int param1, int param2 = 0)
{
	if (g_Cvar_VoteShow.IntValue == 1)
	{
		char voter[64], junk[64], choice[64];
		GetClientName(param1, voter, sizeof(voter));
		menu.GetItem(param2, junk, sizeof(junk), _, choice, sizeof(choice));
		PrintToChatAll("[SM] %T", "Vote Select", LANG_SERVER, voter, choice);
	}
}
*/

bool TestVoteDelay(int client)
{
	if (CheckCommandAccess(client, "sm_vote_delay_bypass", ADMFLAG_CONVARS, true))
	{
		return true;
	}
	
 	int delay = CheckVoteDelay();
	
 	if (delay > 0)
 	{
 		if (delay > 60)
 		{
 			ReplyToCommand(client, "[SM] %t", "Vote Delay Minutes", (delay / 60));
 		}
 		else
 		{
 			ReplyToCommand(client, "[SM] %t", "Vote Delay Seconds", delay);
 		}
 		
 		return false;
 	}
 	
	return true;
}

bool CanVoteTarget(int client, int target, const char[] commandName)
{
	AdminId clientAdmin = GetUserAdmin(client);
	AdminId targetAdmin = GetUserAdmin(target);
	
	if (clientAdmin == INVALID_ADMIN_ID && targetAdmin == INVALID_ADMIN_ID)
	{
		return true;
	}
	
	bool isPublic = !CheckCommandAccess(client, commandName, 0, true);
	
	if (isPublic)
	{
		if (targetAdmin != INVALID_ADMIN_ID && clientAdmin == INVALID_ADMIN_ID)
		{
			return false;
		}
	}
	else
	{
		if (!CanUserTarget(client, target))
		{
			return false;
		}
	}
	
	return true;
}

public Action Timer_ChangeMap(Handle timer, DataPack dp)
{
	char mapname[PLATFORM_MAX_PATH];
	
	dp.Reset();
	dp.ReadString(mapname, sizeof(mapname));
	
	ForceChangeLevel(mapname, "sm_votemap Result");
	
	return Plugin_Stop;
}

// ========================================
// Forward Helper Methods
// ========================================

/**
 * Calls the SBPP_OnVoteInitiated forward
 *
 * @param iInitiator    Client index of the initiator
 * @param voteType      Type of vote
 * @param iTarget       Target client index (-1 if not applicable)
 * @param sTargetName   Target's name
 * @param sReason       Reason for the vote
 * @return              Action result from forward
 */
Action Forward_OnVoteInitiated(int iInitiator, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sReason)
{
	Action result = Plugin_Continue;
	Call_StartForward(g_hFwd_OnVoteInitiated);
	Call_PushCell(iInitiator);
	Call_PushCell(voteType);
	Call_PushCell(iTarget);
	Call_PushString(sTargetName);
	Call_PushString(sReason);
	Call_Finish(result);
	return result;
}

/**
 * Calls the SBPP_OnVoteInitiated_Post forward
 */
void Forward_OnVoteInitiated_Post(int iInitiator, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sReason)
{
	Call_StartForward(g_hFwd_OnVoteInitiated_Post);
	Call_PushCell(iInitiator);
	Call_PushCell(voteType);
	Call_PushCell(iTarget);
	Call_PushString(sTargetName);
	Call_PushString(sReason);
	Call_Finish();
}

/**
 * Calls the SBPP_OnPlayerVoted forward
 * Tracks individual player votes via MenuAction_Select in the vote menu callback
 */
void Forward_OnPlayerVoted(int iVoter, SBPP_VoteType voteType, SBPP_VoteChoice choice, const char[] sTargetName)
{
	Call_StartForward(g_hFwd_OnPlayerVoted);
	Call_PushCell(iVoter);
	Call_PushCell(voteType);
	Call_PushCell(choice);
	Call_PushString(sTargetName);
	Call_Finish();
}

/**
 * Calls the SBPP_OnVoteEnded forward
 */
void Forward_OnVoteEnded(SBPP_VoteType voteType, SBPP_VoteResult result, int iTarget, const char[] sTargetName, 
						 const char[] sTargetAuth, const char[] sReason, int iVotesYes, int iVotesNo, 
						 int iVotesTotal, float fPercentage)
{
	Call_StartForward(g_hFwd_OnVoteEnded);
	Call_PushCell(voteType);
	Call_PushCell(result);
	Call_PushCell(iTarget);
	Call_PushString(sTargetName);
	Call_PushString(sTargetAuth);
	Call_PushString(sReason);
	Call_PushCell(iVotesYes);
	Call_PushCell(iVotesNo);
	Call_PushCell(iVotesTotal);
	Call_PushFloat(fPercentage);
	Call_Finish();
}

/**
 * Calls the SBPP_OnVoteActionExecute forward
 *
 * @return              Action result from forward
 */
Action Forward_OnVoteActionExecute(SBPP_VoteType voteType, int iTarget, const char[] sTargetName, 
								   const char[] sTargetAuth, const char[] sReason, int iDuration)
{
	Action result = Plugin_Continue;
	Call_StartForward(g_hFwd_OnVoteActionExecute);
	Call_PushCell(voteType);
	Call_PushCell(iTarget);
	Call_PushString(sTargetName);
	Call_PushString(sTargetAuth);
	Call_PushString(sReason);
	Call_PushCell(iDuration);
	Call_Finish(result);
	return result;
}

/**
 * Calls the SBPP_OnVoteActionExecute_Post forward
 */
void Forward_OnVoteActionExecute_Post(SBPP_VoteType voteType, int iTarget, const char[] sTargetName, 
									  const char[] sTargetAuth, const char[] sReason, int iDuration)
{
	Call_StartForward(g_hFwd_OnVoteActionExecute_Post);
	Call_PushCell(voteType);
	Call_PushCell(iTarget);
	Call_PushString(sTargetName);
	Call_PushString(sTargetAuth);
	Call_PushString(sReason);
	Call_PushCell(iDuration);
	Call_Finish();
}

/**
 * Clears the reason waiting state for a client
 */
void ClearReasonWaiting(int client)
{
	g_bWaitingForReason[client] = false;
	g_iReasonTarget[client] = 0;
	g_eReasonVoteType[client] = SBPP_VoteType_Map;
	
	// Clear timeout timer if it exists
	if (g_hReasonTimeout[client] != null)
	{
		KillTimer(g_hReasonTimeout[client]);
		g_hReasonTimeout[client] = null;
	}
}

/**
 * Timeout timer for reason waiting
 */
public Action Timer_ReasonTimeout(Handle timer, int client)
{
	if (IsClientInGame(client) && g_bWaitingForReason[client])
	{
		PrintToChat(client, "[SM] %t", "Reason timeout");
		ClearReasonWaiting(client);
	}
	
	g_hReasonTimeout[client] = null;
	return Plugin_Stop;
}
