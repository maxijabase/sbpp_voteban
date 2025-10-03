/**
 * SourceBans++ BaseVotes Control Plugin
 * Monitors and logs all vote activity to Discord via webhook
 * 
 * Tracks:
 * - Vote initiations (who started what vote, against whom, and why)
 * - Individual player votes (yes/no with real-time updates)
 * - Vote results (success/failure with full statistics)
 * - Vote actions (when punishments are executed)
 */

#include <sourcemod>
#include "include/sbpp_basevotes.inc"
#include <ripext>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

// Plugin Info
public Plugin myinfo =
{
	name = "SBPP BaseVotes Control",
	author = "ampere",
	description = "Monitors and logs all vote activity to Discord",
	version = PLUGIN_VERSION,
	url = "github.com/maxijabase"
};

// Webhook Integration
ConVar g_cvWebhookURL;
ConVar g_cvEnabled;

// Vote Tracking
int g_iVoteInitiator;
char g_sVoteTargetName[64];
char g_sVoteTargetAuth[64];
char g_sVoteReason[256];
int g_iVoteStartTime;

// Voter Tracking
ArrayList g_VotersYes;    // Stores client indices who voted yes
ArrayList g_VotersNo;     // Stores client indices who voted no
StringMap g_VoterNames;   // Maps client index -> name at time of vote
StringMap g_VoterAuths;   // Maps client index -> SteamID at time of vote

// Color Definitions for Embeds
#define COLOR_VOTE_INITIATED 0x3498DB  // Blue
#define COLOR_VOTE_SUCCESS   0x2ECC71  // Green
#define COLOR_VOTE_FAILED    0xE74C3C  // Red
#define COLOR_VOTE_PLAYER    0x9B59B6  // Purple
#define COLOR_ACTION_EXECUTE 0xE67E22  // Orange

public void OnPluginStart()
{
	// Create ConVars
	g_cvWebhookURL = CreateConVar("sm_basevotes_webhook", "", "Discord webhook URL for vote logging", FCVAR_PROTECTED);
	g_cvEnabled = CreateConVar("sm_basevotes_control_enabled", "1", "Enable/disable vote logging to Discord", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	AutoExecConfig(true, "sbpp_basevotes_control");
	
	// Initialize vote tracking arrays
	g_VotersYes = new ArrayList();
	g_VotersNo = new ArrayList();
	g_VoterNames = new StringMap();
	g_VoterAuths = new StringMap();
}

public void OnPluginEnd()
{
	// Cleanup
	delete g_VotersYes;
	delete g_VotersNo;
	delete g_VoterNames;
	delete g_VoterAuths;
}

// ============================================================================
// Webhook Helper Functions
// ============================================================================

/**
 * Sends a Discord webhook with an embed
 * 
 * @param webhookURL    The Discord webhook URL
 * @param content       Optional message content (can be empty)
 * @param embed         JSONObject representing the embed
 */
void SendDiscordWebhook(const char[] webhookURL, const char[] content, JSONObject embed)
{
	if (strlen(webhookURL) == 0)
	{
		LogError("Cannot send webhook: URL is empty");
		return;
	}
	
	// Build payload
	JSONObject payload = new JSONObject();
	
	// Add content if provided
	if (strlen(content) > 0)
	{
		payload.SetString("content", content);
	}
	
	// Add embed to embeds array
	JSONArray embeds = new JSONArray();
	embeds.Push(embed);
	payload.Set("embeds", embeds);
	
	// Send HTTP POST request
	HTTPRequest request = new HTTPRequest(webhookURL);
	request.Post(payload, OnWebhookResponse, 0);
	
	// Cleanup
	delete embeds;
	delete payload;
}

/**
 * HTTP response callback for webhook requests
 */
void OnWebhookResponse(HTTPResponse response, any data)
{
	if (response.Status == HTTPStatus_NoContent || response.Status == HTTPStatus_OK)
	{
		// Success - Discord typically returns 204 No Content
		return;
	}
	
	// Log errors
	LogError("Webhook delivery failed with HTTP %d", response.Status);
}

/**
 * Creates a basic embed with title, description, color, and timestamp
 * 
 * @return JSONObject representing the embed (must be deleted by caller)
 */
JSONObject CreateEmbed(const char[] title, const char[] description, int color)
{
	JSONObject embed = new JSONObject();
	
	embed.SetString("title", title);
	
	if (strlen(description) > 0)
	{
		embed.SetString("description", description);
	}
	
	embed.SetInt("color", color);
	
	// Add timestamp
	char timestamp[64];
	FormatTime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%S", GetTime());
	Format(timestamp, sizeof(timestamp), "%s.000Z", timestamp);
	embed.SetString("timestamp", timestamp);
	
	return embed;
}

/**
 * Adds a field to an embed
 */
void AddEmbedField(JSONObject embed, const char[] name, const char[] value, bool inline = false)
{
	// Get or create fields array
	JSONArray fields;
	
	if (embed.HasKey("fields"))
	{
		fields = view_as<JSONArray>(embed.Get("fields"));
	}
	else
	{
		fields = new JSONArray();
		embed.Set("fields", fields);
	}
	
	// Create field
	JSONObject field = new JSONObject();
	field.SetString("name", name);
	field.SetString("value", value);
	field.SetBool("inline", inline);
	
	// Add to array
	fields.Push(field);
	
	delete field;
	delete fields;
}

// ============================================================================
// SBPP BaseVotes API Forwards
// ============================================================================

public Action SBPP_OnVoteInitiated(int iInitiator, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sReason)
{
	if (!g_cvEnabled.BoolValue)
		return Plugin_Continue;
	
	char webhookURL[512];
	g_cvWebhookURL.GetString(webhookURL, sizeof(webhookURL));
	if (strlen(webhookURL) == 0)
		return Plugin_Continue;
	
	// Store vote information
	g_iVoteInitiator = iInitiator;
	strcopy(g_sVoteTargetName, sizeof(g_sVoteTargetName), sTargetName);
	strcopy(g_sVoteReason, sizeof(g_sVoteReason), sReason);
	g_iVoteStartTime = GetTime();
	
	// Get target auth if target is valid
	if (iTarget > 0 && iTarget <= MaxClients && IsClientConnected(iTarget))
	{
		GetClientAuthId(iTarget, AuthId_Steam2, g_sVoteTargetAuth, sizeof(g_sVoteTargetAuth));
	}
	else
	{
		strcopy(g_sVoteTargetAuth, sizeof(g_sVoteTargetAuth), "Unknown");
	}
	
	// Clear voter tracking
	g_VotersYes.Clear();
	g_VotersNo.Clear();
	g_VoterNames.Clear();
	g_VoterAuths.Clear();
	
	return Plugin_Continue;
}

public void SBPP_OnVoteInitiated_Post(int iInitiator, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sReason)
{
	if (!g_cvEnabled.BoolValue)
		return;
	
	char webhookURL[512];
	g_cvWebhookURL.GetString(webhookURL, sizeof(webhookURL));
	if (strlen(webhookURL) == 0)
		return;
	
	// Send vote initiated embed
	SendVoteInitiatedEmbed(webhookURL, iInitiator, voteType, iTarget, sTargetName, sReason);
}

public void SBPP_OnPlayerVoted(int iVoter, SBPP_VoteType voteType, SBPP_VoteChoice choice, const char[] sTargetName)
{
	if (!g_cvEnabled.BoolValue)
		return;
	
	if (!IsClientInGame(iVoter))
		return;
	
	// Store voter information
	char voterName[64], voterAuth[64], voterKey[12];
	GetClientName(iVoter, voterName, sizeof(voterName));
	GetClientAuthId(iVoter, AuthId_Steam2, voterAuth, sizeof(voterAuth));
	IntToString(iVoter, voterKey, sizeof(voterKey));
	
	g_VoterNames.SetString(voterKey, voterName);
	g_VoterAuths.SetString(voterKey, voterAuth);
	
	// Add to appropriate list
	if (choice == SBPP_VoteChoice_Yes)
	{
		if (g_VotersYes.FindValue(iVoter) == -1)
			g_VotersYes.Push(iVoter);
	}
	else
	{
		if (g_VotersNo.FindValue(iVoter) == -1)
			g_VotersNo.Push(iVoter);
	}
	
	// Send individual vote notification (optional, can be noisy)
	// Uncomment the following lines if you want real-time vote updates
	/*
	char webhookURL[512];
	g_cvWebhookURL.GetString(webhookURL, sizeof(webhookURL));
	if (strlen(webhookURL) > 0)
	{
		SendPlayerVotedEmbed(webhookURL, iVoter, voteType, choice, sTargetName, voterName, voterAuth);
	}
	*/
}

public void SBPP_OnVoteEnded(SBPP_VoteType voteType, SBPP_VoteResult result, int iTarget, const char[] sTargetName, const char[] sTargetAuth, const char[] sReason, int iVotesYes, int iVotesNo, int iVotesTotal, float fPercentage)
{
	if (!g_cvEnabled.BoolValue)
		return;
	
	char webhookURL[512];
	g_cvWebhookURL.GetString(webhookURL, sizeof(webhookURL));
	if (strlen(webhookURL) == 0)
		return;
	
	// Send comprehensive vote ended embed
	SendVoteEndedEmbed(webhookURL, voteType, result, iTarget, sTargetName, sTargetAuth, sReason, iVotesYes, iVotesNo, iVotesTotal, fPercentage);
}

public Action SBPP_OnVoteActionExecute(SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sTargetAuth, const char[] sReason, int iDuration)
{
	return Plugin_Continue;
}

public void SBPP_OnVoteActionExecute_Post(SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sTargetAuth, const char[] sReason, int iDuration)
{
	if (!g_cvEnabled.BoolValue)
		return;
	
	char webhookURL[512];
	g_cvWebhookURL.GetString(webhookURL, sizeof(webhookURL));
	if (strlen(webhookURL) == 0)
		return;
	
	// Send action execution embed
	SendActionExecuteEmbed(webhookURL, voteType, iTarget, sTargetName, sTargetAuth, sReason, iDuration);
}

// ============================================================================
// Discord Embed Builders
// ============================================================================

void SendVoteInitiatedEmbed(const char[] webhookURL, int iInitiator, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sReason)
{
	// Get vote type name
	char voteTypeName[32];
	GetVoteTypeName(voteType, voteTypeName, sizeof(voteTypeName));
	
	// Create embed
	char title[128];
	FormatEx(title, sizeof(title), "🗳️ Vote Initiated: %s", voteTypeName);
	JSONObject embed = CreateEmbed(title, "", COLOR_VOTE_INITIATED);
	
	// Get initiator information
	char initiatorName[64], initiatorAuth[64];
	if (iInitiator > 0 && IsClientInGame(iInitiator))
	{
		GetClientName(iInitiator, initiatorName, sizeof(initiatorName));
		GetClientAuthId(iInitiator, AuthId_Steam2, initiatorAuth, sizeof(initiatorAuth));
	}
	else
	{
		strcopy(initiatorName, sizeof(initiatorName), "Server/Console");
		strcopy(initiatorAuth, sizeof(initiatorAuth), "CONSOLE");
	}
	
	// Add initiator field
	char initiatorInfo[256];
	FormatEx(initiatorInfo, sizeof(initiatorInfo), "**%s**\n`%s`", initiatorName, initiatorAuth);
	AddEmbedField(embed, "Initiated By", initiatorInfo, true);
	
	// Add vote type field
	AddEmbedField(embed, "Vote Type", voteTypeName, true);
	
	// Add target information (for kick/ban/mute/gag)
	if (voteType != SBPP_VoteType_Map && voteType != SBPP_VoteType_Question)
	{
		char targetInfo[256];
		bool targetConnected = (iTarget > 0 && iTarget <= MaxClients && IsClientConnected(iTarget));
		FormatEx(targetInfo, sizeof(targetInfo), "**%s**\n`%s`\n*Status: %s*", 
			sTargetName, g_sVoteTargetAuth, targetConnected ? "Connected" : "Disconnected");
		AddEmbedField(embed, "Target", targetInfo, false);
	}
	else if (voteType == SBPP_VoteType_Map)
	{
		AddEmbedField(embed, "Map", sTargetName, false);
	}
	
	// Add reason
	if (strlen(sReason) > 0)
	{
		char reasonFormatted[512];
		FormatEx(reasonFormatted, sizeof(reasonFormatted), "```%s```", sReason);
		AddEmbedField(embed, "Reason", reasonFormatted, false);
	}
	else
	{
		AddEmbedField(embed, "Reason", "`No reason provided`", false);
	}
	
	// Add time
	char timeString[64];
	FormatTime(timeString, sizeof(timeString), "%Y-%m-%d %H:%M:%S", GetTime());
	AddEmbedField(embed, "Time", timeString, true);
	
	// Send webhook
	SendDiscordWebhook(webhookURL, "", embed);
	delete embed;
}

void SendVoteEndedEmbed(const char[] webhookURL, SBPP_VoteType voteType, SBPP_VoteResult result, int iTarget, const char[] sTargetName, const char[] sTargetAuth, const char[] sReason, int iVotesYes, int iVotesNo, int iVotesTotal, float fPercentage)
{
	// Get vote type name
	char voteTypeName[32];
	GetVoteTypeName(voteType, voteTypeName, sizeof(voteTypeName));
	
	// Create embed with appropriate color
	char title[128];
	int color;
	if (result == SBPP_VoteResult_Success)
	{
		FormatEx(title, sizeof(title), "✅ Vote Passed: %s", voteTypeName);
		color = COLOR_VOTE_SUCCESS;
	}
	else
	{
		FormatEx(title, sizeof(title), "❌ Vote Failed: %s", voteTypeName);
		color = COLOR_VOTE_FAILED;
	}
	
	JSONObject embed = CreateEmbed(title, "", color);
	
	// Get initiator information
	char initiatorName[64], initiatorAuth[64];
	if (g_iVoteInitiator > 0 && IsClientInGame(g_iVoteInitiator))
	{
		GetClientName(g_iVoteInitiator, initiatorName, sizeof(initiatorName));
		GetClientAuthId(g_iVoteInitiator, AuthId_Steam2, initiatorAuth, sizeof(initiatorAuth));
	}
	else
	{
		strcopy(initiatorName, sizeof(initiatorName), "Server/Console");
		strcopy(initiatorAuth, sizeof(initiatorAuth), "CONSOLE");
	}
	
	char initiatorInfo[256];
	FormatEx(initiatorInfo, sizeof(initiatorInfo), "**%s**\n`%s`", initiatorName, initiatorAuth);
	AddEmbedField(embed, "Initiated By", initiatorInfo, true);
	
	// Add target information
	if (voteType != SBPP_VoteType_Map && voteType != SBPP_VoteType_Question)
	{
		char targetInfo[256];
		bool targetConnected = (iTarget > 0 && iTarget <= MaxClients && IsClientConnected(iTarget));
		FormatEx(targetInfo, sizeof(targetInfo), "**%s**\n`%s`\n*Status: %s*", 
			sTargetName, sTargetAuth, targetConnected ? "Connected" : "Disconnected");
		AddEmbedField(embed, "Target", targetInfo, true);
	}
	else if (voteType == SBPP_VoteType_Map)
	{
		AddEmbedField(embed, "Map", sTargetName, true);
	}
	
	// Vote statistics
	char voteStats[256];
	FormatEx(voteStats, sizeof(voteStats), "**Yes:** %d\n**No:** %d\n**Total:** %d\n**Percentage:** %.1f%%", 
		iVotesYes, iVotesNo, iVotesTotal, fPercentage);
	AddEmbedField(embed, "📊 Results", voteStats, false);
	
	// List voters who voted YES
	char yesVoters[2048] = "";
	int yesCount = g_VotersYes.Length;
	
	if (yesCount > 0)
	{
		for (int i = 0; i < yesCount; i++)
		{
			int client = g_VotersYes.Get(i);
			char key[12], name[64], auth[64];
			IntToString(client, key, sizeof(key));
			
			if (g_VoterNames.GetString(key, name, sizeof(name)) && g_VoterAuths.GetString(key, auth, sizeof(auth)))
			{
				char voterLine[128];
				FormatEx(voterLine, sizeof(voterLine), "%d. **%s** - `%s`\n", i + 1, name, auth);
				StrCat(yesVoters, sizeof(yesVoters), voterLine);
			}
		}
		
		// Truncate if too long (Discord field limit is 1024)
		if (strlen(yesVoters) > 1024)
		{
			yesVoters[1020] = '.';
			yesVoters[1021] = '.';
			yesVoters[1022] = '.';
			yesVoters[1023] = '\0';
		}
	}
	else
	{
		strcopy(yesVoters, sizeof(yesVoters), "*No votes*");
	}
	
	AddEmbedField(embed, "👍 Voted Yes", yesVoters, false);
	
	// List voters who voted NO
	char noVoters[2048] = "";
	int noCount = g_VotersNo.Length;
	
	if (noCount > 0)
	{
		for (int i = 0; i < noCount; i++)
		{
			int client = g_VotersNo.Get(i);
			char key[12], name[64], auth[64];
			IntToString(client, key, sizeof(key));
			
			if (g_VoterNames.GetString(key, name, sizeof(name)) && g_VoterAuths.GetString(key, auth, sizeof(auth)))
			{
				char voterLine[128];
				FormatEx(voterLine, sizeof(voterLine), "%d. **%s** - `%s`\n", i + 1, name, auth);
				StrCat(noVoters, sizeof(noVoters), voterLine);
			}
		}
		
		// Truncate if too long
		if (strlen(noVoters) > 1024)
		{
			noVoters[1020] = '.';
			noVoters[1021] = '.';
			noVoters[1022] = '.';
			noVoters[1023] = '\0';
		}
	}
	else
	{
		strcopy(noVoters, sizeof(noVoters), "*No votes*");
	}
	
	AddEmbedField(embed, "👎 Voted No", noVoters, false);
	
	// Add reason
	if (strlen(sReason) > 0)
	{
		char reasonFormatted[512];
		FormatEx(reasonFormatted, sizeof(reasonFormatted), "```%s```", sReason);
		AddEmbedField(embed, "Reason", reasonFormatted, false);
	}
	
	// Calculate duration
	int duration = GetTime() - g_iVoteStartTime;
	char durationStr[64];
	FormatEx(durationStr, sizeof(durationStr), "%d seconds", duration);
	AddEmbedField(embed, "Duration", durationStr, true);
	
	// Result
	char resultStr[32];
	strcopy(resultStr, sizeof(resultStr), result == SBPP_VoteResult_Success ? "**PASSED** ✅" : "**FAILED** ❌");
	AddEmbedField(embed, "Result", resultStr, true);
	
	// Send webhook
	SendDiscordWebhook(webhookURL, "", embed);
	delete embed;
}

void SendActionExecuteEmbed(const char[] webhookURL, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sTargetAuth, const char[] sReason, int iDuration)
{
	// Get vote type name and action name
	char voteTypeName[32], actionName[32];
	GetVoteTypeName(voteType, voteTypeName, sizeof(voteTypeName));
	GetActionName(voteType, actionName, sizeof(actionName));
	
	// Create embed
	char title[128];
	FormatEx(title, sizeof(title), "⚡ Action Executed: %s", actionName);
	JSONObject embed = CreateEmbed(title, "", COLOR_ACTION_EXECUTE);
	
	// Add target information with connection status
	char targetInfo[256];
	bool targetConnected = (iTarget > 0 && iTarget <= MaxClients && IsClientConnected(iTarget));
	FormatEx(targetInfo, sizeof(targetInfo), "**%s**\n`%s`\n*Status: %s*", 
		sTargetName, sTargetAuth, targetConnected ? "Connected" : "Disconnected");
	AddEmbedField(embed, "Target Player", targetInfo, false);
	
	// Add action type
	AddEmbedField(embed, "Action Type", actionName, true);
	
	// Add duration (for bans/mutes/gags)
	if (voteType == SBPP_VoteType_Ban || voteType == SBPP_VoteType_Mute || voteType == SBPP_VoteType_Gag)
	{
		char durationStr[64];
		if (iDuration == 0)
		{
			strcopy(durationStr, sizeof(durationStr), "Permanent");
		}
		else
		{
			FormatEx(durationStr, sizeof(durationStr), "%d minutes", iDuration);
		}
		AddEmbedField(embed, "Duration", durationStr, true);
	}
	
	// Add reason
	if (strlen(sReason) > 0)
	{
		char reasonFormatted[512];
		FormatEx(reasonFormatted, sizeof(reasonFormatted), "```%s```", sReason);
		AddEmbedField(embed, "Reason", reasonFormatted, false);
	}
	else
	{
		AddEmbedField(embed, "Reason", "`No reason provided`", false);
	}
	
	// Add timestamp
	char timeString[64];
	FormatTime(timeString, sizeof(timeString), "%Y-%m-%d %H:%M:%S", GetTime());
	AddEmbedField(embed, "Executed At", timeString, true);
	
	// Send webhook
	SendDiscordWebhook(webhookURL, "", embed);
	delete embed;
}

void SendPlayerVotedEmbed(const char[] webhookURL, int iVoter, SBPP_VoteType voteType, SBPP_VoteChoice choice, const char[] sTargetName, const char[] voterName, const char[] voterAuth)
{
	// Get vote type name
	char voteTypeName[32];
	GetVoteTypeName(voteType, voteTypeName, sizeof(voteTypeName));
	
	// Create embed
	char title[128];
	FormatEx(title, sizeof(title), "🗳️ Player Voted: %s", choice == SBPP_VoteChoice_Yes ? "Yes" : "No");
	JSONObject embed = CreateEmbed(title, "", COLOR_VOTE_PLAYER);
	
	// Voter information with connection validation
	char voterInfo[256];
	bool voterConnected = (iVoter > 0 && iVoter <= MaxClients && IsClientConnected(iVoter));
	FormatEx(voterInfo, sizeof(voterInfo), "**%s**\n`%s`\n*%s*", 
		voterName, voterAuth, voterConnected ? "Connected" : "Disconnected");
	AddEmbedField(embed, "Voter", voterInfo, true);
	
	// Vote choice
	char voteChoice[32];
	strcopy(voteChoice, sizeof(voteChoice), choice == SBPP_VoteChoice_Yes ? "👍 **Yes**" : "👎 **No**");
	AddEmbedField(embed, "Vote", voteChoice, true);
	
	// Vote type
	AddEmbedField(embed, "Vote Type", voteTypeName, true);
	
	// Target
	AddEmbedField(embed, "Target", sTargetName, true);
	
	// Send webhook
	SendDiscordWebhook(webhookURL, "", embed);
	delete embed;
}

// ============================================================================
// Helper Functions
// ============================================================================

void GetVoteTypeName(SBPP_VoteType voteType, char[] buffer, int maxlen)
{
	switch (voteType)
	{
		case SBPP_VoteType_Map:     strcopy(buffer, maxlen, "Map Vote");
		case SBPP_VoteType_Kick:    strcopy(buffer, maxlen, "Kick Vote");
		case SBPP_VoteType_Ban:     strcopy(buffer, maxlen, "Ban Vote");
		case SBPP_VoteType_Mute:    strcopy(buffer, maxlen, "Mute Vote");
		case SBPP_VoteType_Gag:     strcopy(buffer, maxlen, "Gag Vote");
		case SBPP_VoteType_Question: strcopy(buffer, maxlen, "Question Vote");
		default:                     strcopy(buffer, maxlen, "Unknown Vote");
	}
}

void GetActionName(SBPP_VoteType voteType, char[] buffer, int maxlen)
{
	switch (voteType)
	{
		case SBPP_VoteType_Map:     strcopy(buffer, maxlen, "Map Change");
		case SBPP_VoteType_Kick:    strcopy(buffer, maxlen, "Player Kicked");
		case SBPP_VoteType_Ban:     strcopy(buffer, maxlen, "Player Banned");
		case SBPP_VoteType_Mute:    strcopy(buffer, maxlen, "Player Muted");
		case SBPP_VoteType_Gag:     strcopy(buffer, maxlen, "Player Gagged");
		case SBPP_VoteType_Question: strcopy(buffer, maxlen, "Question Result");
		default:                     strcopy(buffer, maxlen, "Unknown Action");
	}
}

