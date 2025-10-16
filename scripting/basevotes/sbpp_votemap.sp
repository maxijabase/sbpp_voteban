#define MAPS_COUNT 5

Menu g_MapList;
int g_mapCount;

ArrayList g_SelectedMaps;
bool g_VoteMapInUse;

void DisplayVoteMapMenu(int client, int mapCount, char[][] maps)
{
	char maps_list[MAPS_COUNT * (PLATFORM_MAX_PATH + 1)];
	
	for (int i = 0; i < mapCount; i++)
	{
		Format(maps_list, sizeof(maps_list), "%s %s", maps_list, maps[i]);
	}
	
	LogAction(client, -1, "\"%L\" initiated a map vote for%s.", client, maps_list);
	ShowActivity2(client, "[SM] ", "%t", "Initiated Vote Map");
	
	g_voteType = VoteType_Map;
	
	g_hVoteMenu = new Menu(Handler_VoteCallback, MENU_ACTIONS_ALL);
	
	if (mapCount == 1)
	{
		GetMapDisplayName(maps[0], g_voteInfo[VOTE_NAME], sizeof(g_voteInfo[]));
			
		g_hVoteMenu.SetTitle("Change Map To");
		g_hVoteMenu.AddItem(maps[0], "Yes");
		g_hVoteMenu.AddItem(VOTE_NO, "No");
	}
	else
	{
		g_voteInfo[VOTE_NAME][0] = '\0';
		
		g_hVoteMenu.SetTitle("Map Vote");
		for (int i = 0; i < mapCount; i++)
		{
			char displayName[PLATFORM_MAX_PATH];
			GetMapDisplayName(maps[i], displayName, sizeof(displayName));
			g_hVoteMenu.AddItem(maps[i], displayName);
		}	
	}
	
	g_hVoteMenu.ExitButton = false;
	g_hVoteMenu.DisplayVoteToAll(20);		
}

void ResetMenu()
{
	g_VoteMapInUse = false;
	g_SelectedMaps.Clear();
}

void ConfirmVote(int client)
{
	Menu menu = new Menu(MenuHandler_Confirm);
	
	char title[100];
	Format(title, sizeof(title), "%T:", "Confirm Vote", client);
	menu.SetTitle(title);
	menu.ExitBackButton = true;
	
	char itemtext[256];
	Format(itemtext, sizeof(itemtext), "%T", "Start the Vote", client);
	menu.AddItem("Confirm", itemtext);
	
	menu.Display(client, MENU_TIME_FOREVER);	
}

public int MenuHandler_Confirm(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		g_VoteMapInUse = false;
	}
	else if (action == MenuAction_Cancel)
	{
		ResetMenu();
		
		if (param2 == MenuCancel_ExitBack && hTopMenu)
		{
			hTopMenu.Display(param1, TopMenuPosition_LastCategory);
		}
	}
	else if (action == MenuAction_Select)
	{
		char maps[MAPS_COUNT][PLATFORM_MAX_PATH];
		int selectedmaps = g_SelectedMaps.Length;
		
		for (int i = 0; i < selectedmaps; i++)
		{
			g_SelectedMaps.GetString(i, maps[i], sizeof(maps[]));
		}
		
		DisplayVoteMapMenu(param1, selectedmaps, maps);
		
		ResetMenu();
	}

	return 0;
}

public int MenuHandler_Map(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Cancel)
	{		
		if (param2 == MenuCancel_ExitBack && hTopMenu)
		{
			ConfirmVote(param1);
		}
		else // no action was selected.
		{
			/* Re-enable the menu option */
			ResetMenu();
		}
	}
	else if (action == MenuAction_DrawItem)
	{
		char info[PLATFORM_MAX_PATH], name[32];
		
		menu.GetItem(param2, info, sizeof(info), _, name, sizeof(name));
		
		if (g_SelectedMaps.FindString(info) != -1)
		{
			return ITEMDRAW_IGNORE;
		}
		else
		{
			return ITEMDRAW_DEFAULT;
		}
	}
	else if (action == MenuAction_Select)
	{
		char info[PLATFORM_MAX_PATH], name[32];
		
		menu.GetItem(param2, info, sizeof(info), _, name, sizeof(name));
		
		g_SelectedMaps.PushString(info);
		
		/* Redisplay the list */
		if (g_SelectedMaps.Length < MAPS_COUNT)
		{
			g_MapList.Display(param1, MENU_TIME_FOREVER);
		}
		else
		{
			ConfirmVote(param1);
		}
	}
	else if (action == MenuAction_Display)
	{
		char title[128];
		Format(title, sizeof(title), "%T", "Please select a map", param1);

		Panel panel = view_as<Panel>(param2);
		panel.SetTitle(title);
	}
	
	return 0;
}

public void AdminMenu_VoteMap(TopMenu topmenu, 
							  TopMenuAction action,
							  TopMenuObject object_id,
							  int param,
							  char[] buffer,
							  int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%T", "Map vote", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		if (!g_VoteMapInUse)
		{
			ResetMenu();
			g_VoteMapInUse = true;
			g_MapList.Display(param, MENU_TIME_FOREVER);
		}
		else 
		{
			PrintToChat(param, "[SM] %T", "Map Vote In Use", param);
		}
	}
	else if (action == TopMenuAction_DrawOption)
	{	
		/* disable this option if a vote is already running, theres no maps listed or someone else has already acessed this menu */
		buffer[0] = (!IsNewVoteAllowed() || g_mapCount < 1 || g_VoteMapInUse) ? ITEMDRAW_IGNORE : ITEMDRAW_DEFAULT;
	}
}

public Action Command_Votemap(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_votemap <mapname> [mapname2] ... [mapname5]");
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

	char maps[MAPS_COUNT][PLATFORM_MAX_PATH];
	int mapCount;	
	int len, pos;
	
	while (pos != -1 && mapCount < MAPS_COUNT)
	{	
		pos = BreakString(text[len], maps[mapCount], sizeof(maps[]));
		
		if (!IsMapValid(maps[mapCount]))
		{
			ReplyToCommand(client, "[SM] %t", "Map was not found", maps[mapCount]);
			return Plugin_Handled;
		}		

		mapCount++;
		
		if (pos != -1)
		{
			len += pos;
		}	
	}

	DisplayVoteMapMenu(client, mapCount, maps);
	
	return Plugin_Handled;	
}

Handle g_map_array = null;
int g_map_serial = -1;

int LoadMapList(Menu menu)
{
	Handle map_array;
	
	if ((map_array = ReadMapList(g_map_array,
			g_map_serial,
			"sm_votemap menu",
			MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER))
		!= null)
	{
		g_map_array = map_array;
	}
	
	if (g_map_array == null)
	{
		return 0;
	}
	
	menu.RemoveAllItems();
	
	char map_name[PLATFORM_MAX_PATH];
	int map_count = GetArraySize(g_map_array);
	
	for (int i = 0; i < map_count; i++)
	{
		char displayName[PLATFORM_MAX_PATH];
		GetArrayString(g_map_array, i, map_name, sizeof(map_name));
		GetMapDisplayName(map_name, displayName, sizeof(displayName));
		menu.AddItem(map_name, displayName);
	}
	
	return map_count;
}
