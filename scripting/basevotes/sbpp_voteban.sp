void DisplayVoteBanMenu(int client, int target)
{
	g_voteTarget = GetClientUserId(target);
	g_voteInitiator = client;

	GetClientName(target, g_voteInfo[VOTE_NAME], sizeof(g_voteInfo[]));
	GetClientAuthId(target, AuthId_Steam2, g_voteInfo[VOTE_AUTHID], sizeof(g_voteInfo[]));
	GetClientIP(target, g_voteInfo[VOTE_IP], sizeof(g_voteInfo[]));

	// Call OnVoteInitiated forward
	Action result = Forward_OnVoteInitiated(client, SBPP_VoteType_Ban, target, g_voteInfo[VOTE_NAME], g_voteArg);
	if (result >= Plugin_Handled)
	{
		return;
	}

	LogAction(client, target, "\"%L\" initiated a ban vote against \"%L\"", client, target);
	ShowActivity2(client, "[SM] ", "%t", "Initiated Vote Ban", g_voteInfo[VOTE_NAME]);

	g_voteType = VoteType_Ban;
	
	g_hVoteMenu = new Menu(Handler_VoteCallback, MENU_ACTIONS_ALL);
	g_hVoteMenu.SetTitle("Vote Action Menu Ban");
	g_hVoteMenu.AddItem(VOTE_YES, "Yes");
	g_hVoteMenu.AddItem(VOTE_NO, "No");
	g_hVoteMenu.ExitButton = false;
	g_hVoteMenu.DisplayVoteToAll(20);
	
	// Call OnVoteInitiated_Post forward
	Forward_OnVoteInitiated_Post(client, SBPP_VoteType_Ban, target, g_voteInfo[VOTE_NAME], g_voteArg);
}

void DisplayBanTargetMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Ban);
	
	char title[100];
	Format(title, sizeof(title), "%T:", "Ban vote", client);
	menu.SetTitle(title);
	menu.ExitBackButton = true;
	
	AddTargetsToMenu2(menu, client, COMMAND_FILTER_NO_IMMUNITY);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public void AdminMenu_VoteBan(TopMenu topmenu, 
							  TopMenuAction action,
							  TopMenuObject object_id,
							  int param,
							  char[] buffer,
							  int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%T", "Ban vote", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		DisplayBanTargetMenu(param);
	}
	else if (action == TopMenuAction_DrawOption)
	{	
		/* disable this option if a vote is already running */
		buffer[0] = !IsNewVoteAllowed() ? ITEMDRAW_IGNORE : ITEMDRAW_DEFAULT;
	}
}

public int MenuHandler_Ban(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
	}
	else if (action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack && hTopMenu)
		{
			hTopMenu.Display(param1, TopMenuPosition_LastCategory);
		}
	}
	else if (action == MenuAction_Select)
	{
		char info[32], name[32];
		int userid, target;
		
		menu.GetItem(param2, info, sizeof(info), _, name, sizeof(name));
		userid = StringToInt(info);

		if ((target = GetClientOfUserId(userid)) == 0)
		{
			PrintToChat(param1, "[SM] %t", "Player no longer available");
		}
		else if (!CanVoteTarget(param1, target, "sm_voteban"))
		{
			PrintToChat(param1, "[SM] %t", "Unable to target");
		}
		else
		{
			// Check if reason requirement is enabled
			if (g_Cvar_RequireReason.BoolValue)
			{
				// Set up reason waiting for menu selection
				g_bWaitingForReason[param1] = true;
				g_iReasonTarget[param1] = GetClientUserId(target);
				g_eReasonVoteType[param1] = SBPP_VoteType_Ban;
				
				// Start timeout timer
				g_hReasonTimeout[param1] = CreateTimer(g_Cvar_ReasonTimeout.FloatValue, Timer_ReasonTimeout, param1);
				
				PrintToChat(param1, "[SM] %t", "Vote reason explanation");
			}
			else
			{
				g_voteArg[0] = '\0';
				DisplayVoteBanMenu(param1, target);
			}
		}
	}

	return 0;
}

public Action Command_Voteban(int client, int args)
{
	if (args < 1)
	{
		// If command is from chat and no args, show menu
		if ((GetCmdReplySource() == SM_REPLY_TO_CHAT) && (client != 0))
		{
			if (IsVoteInProgress())
			{
				ReplyToCommand(client, "[SM] %t", "Vote in Progress");
				return Plugin_Handled;
			}
			
			if (!TestVoteDelay(client))
			{
				return Plugin_Handled;
			}
			
			DisplayBanTargetMenu(client);
		}
		else
		{
			ReplyToCommand(client, "[SM] Usage: sm_voteban <player> [reason]");
		}
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
	
	char text[256], arg[64];
	GetCmdArgString(text, sizeof(text));
	
	int len = BreakString(text, arg, sizeof(arg));
	
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			arg,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_NO_MULTI|COMMAND_FILTER_NO_BOTS,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	int target = target_list[0];
	
	// Check if reason requirement is enabled
	if (g_Cvar_RequireReason.BoolValue)
	{
		// Check if reason was provided in command
		if (len != -1 && strlen(text[len]) > 0)
		{
			// Reason provided, proceed normally
			strcopy(g_voteArg, sizeof(g_voteArg), text[len]);
			DisplayVoteBanMenu(client, target);
		}
		else
		{
			// No reason provided, set up reason waiting
			g_bWaitingForReason[client] = true;
			g_iReasonTarget[client] = GetClientUserId(target);
			g_eReasonVoteType[client] = SBPP_VoteType_Ban;
			
			// Start timeout timer
			g_hReasonTimeout[client] = CreateTimer(g_Cvar_ReasonTimeout.FloatValue, Timer_ReasonTimeout, client);
			
			PrintToChat(client, "[SM] %t", "Vote reason explanation");
		}
	}
	else
	{
		// Reason requirement disabled, proceed normally
		if (len != -1)
		{
			strcopy(g_voteArg, sizeof(g_voteArg), text[len]);
		}
		else
		{
			g_voteArg[0] = '\0';
		}
		
		DisplayVoteBanMenu(client, target);
	}
	
	return Plugin_Handled;
}
