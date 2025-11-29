#include <sourcemod>
#include "include/sbpp_basevotes.inc"
#include <ripext>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.1"

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
int g_iVoteInitiatorUserId;
int g_iVoteTargetUserId;
char g_sVoteTargetName[64];
char g_sVoteTargetAuth[64];  // Fallback Steam2 if target disconnects
int g_iVoteStartTime;

// Voter Tracking - store UserIDs and fallback data
ArrayList g_VotersYes;       // UserIDs of yes voters
ArrayList g_VotersNo;        // UserIDs of no voters
StringMap g_VoterNames;      // UserId -> name (fallback)
StringMap g_VoterAuths;      // UserId -> Steam2 (fallback)

// Color Definitions for Embeds
#define COLOR_VOTE_INITIATED 0x3498DB  // Blue
#define COLOR_VOTE_SUCCESS   0x2ECC71  // Green
#define COLOR_VOTE_FAILED    0xE74C3C  // Red
#define COLOR_ACTION_EXECUTE 0xE67E22  // Orange

public void OnPluginStart()
{
	g_cvWebhookURL = CreateConVar("sm_basevotes_webhook", "", "Discord webhook URL for vote logging", FCVAR_PROTECTED);
	g_cvEnabled = CreateConVar("sm_basevotes_control_enabled", "1", "Enable/disable vote logging to Discord", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	AutoExecConfig(true, "sbpp_basevotes_control");
	
	g_VotersYes = new ArrayList();
	g_VotersNo = new ArrayList();
	g_VoterNames = new StringMap();
	g_VoterAuths = new StringMap();
}

public void OnPluginEnd()
{
	delete g_VotersYes;
	delete g_VotersNo;
	delete g_VoterNames;
	delete g_VoterAuths;
}

// ============================================================================
// Steam Profile Link Helpers
// ============================================================================

/**
 * Formats a player name as a clickable Steam profile link
 * If Steam64 unavailable, returns plain name
 */
void FormatNameAsProfileLink(int client, const char[] name, char[] buffer, int maxlen)
{
	char steamId64[64];
	
	if (GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64)))
	{
		FormatEx(buffer, maxlen, "[%s](https://steamcommunity.com/profiles/%s)", name, steamId64);
	}
	else
	{
		strcopy(buffer, maxlen, name);
	}
}

/**
 * Formats a player name as a clickable Steam profile link using stored UserId
 * If client disconnected, returns plain name
 */
void FormatNameAsProfileLinkFromUserId(int userId, const char[] name, char[] buffer, int maxlen)
{
	int client = GetClientOfUserId(userId);
	
	if (client > 0 && IsClientConnected(client))
	{
		FormatNameAsProfileLink(client, name, buffer, maxlen);
	}
	else
	{
		// Client disconnected - just show name
		strcopy(buffer, maxlen, name);
	}
}

// ============================================================================
// Webhook Helper Functions
// ============================================================================

void SendDiscordWebhook(const char[] webhookURL, const char[] content, JSONObject embed)
{
	if (strlen(webhookURL) == 0)
	{
		LogError("Cannot send webhook: URL is empty");
		return;
	}
	
	JSONObject payload = new JSONObject();
	
	if (strlen(content) > 0)
	{
		payload.SetString("content", content);
	}
	
	JSONArray embeds = new JSONArray();
	embeds.Push(embed);
	payload.Set("embeds", embeds);
	
	HTTPRequest request = new HTTPRequest(webhookURL);
	request.Post(payload, OnWebhookResponse, 0);
	
	delete embeds;
	delete payload;
}

void OnWebhookResponse(HTTPResponse response, any data)
{
	if (response.Status != HTTPStatus_NoContent && response.Status != HTTPStatus_OK)
	{
		LogError("Webhook delivery failed with HTTP %d", response.Status);
	}
}

JSONObject CreateEmbed(const char[] title, const char[] description, int color)
{
	JSONObject embed = new JSONObject();
	
	embed.SetString("title", title);
	
	if (strlen(description) > 0)
	{
		embed.SetString("description", description);
	}
	
	embed.SetInt("color", color);
	
	return embed;
}

void AddEmbedField(JSONObject embed, const char[] name, const char[] value, bool inline = false)
{
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
	
	JSONObject field = new JSONObject();
	field.SetString("name", name);
	field.SetString("value", value);
	field.SetBool("inline", inline);
	
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
	
	// Store UserIDs for later lookup
	g_iVoteInitiatorUserId = (iInitiator > 0 && IsClientConnected(iInitiator)) ? GetClientUserId(iInitiator) : 0;
	g_iVoteTargetUserId = (iTarget > 0 && iTarget <= MaxClients && IsClientConnected(iTarget)) ? GetClientUserId(iTarget) : 0;
	
	strcopy(g_sVoteTargetName, sizeof(g_sVoteTargetName), sTargetName);
	g_iVoteStartTime = GetTime();
	
	// Store fallback Steam2 for target
	if (iTarget > 0 && iTarget <= MaxClients && IsClientConnected(iTarget))
	{
		if (!GetClientAuthId(iTarget, AuthId_Steam2, g_sVoteTargetAuth, sizeof(g_sVoteTargetAuth)))
		{
			strcopy(g_sVoteTargetAuth, sizeof(g_sVoteTargetAuth), "Unknown");
		}
	}
	else
	{
		strcopy(g_sVoteTargetAuth, sizeof(g_sVoteTargetAuth), "Unknown");
	}
	
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
	
	SendVoteInitiatedEmbed(webhookURL, voteType, sTargetName, sReason);
}

public void SBPP_OnPlayerVoted(int iVoter, SBPP_VoteType voteType, SBPP_VoteChoice choice, const char[] sTargetName)
{
	if (!g_cvEnabled.BoolValue)
		return;
	
	if (!IsClientInGame(iVoter))
		return;
	
	int odingUserId = GetClientUserId(iVoter);
	char odingUserIdStr[12], voterName[64], voterAuth[64];
	IntToString(odingUserId, odingUserIdStr, sizeof(odingUserIdStr));
	
	GetClientName(iVoter, voterName, sizeof(voterName));
	
	if (!GetClientAuthId(iVoter, AuthId_Steam2, voterAuth, sizeof(voterAuth)))
	{
		strcopy(voterAuth, sizeof(voterAuth), "Unknown");
	}
	
	g_VoterNames.SetString(odingUserIdStr, voterName);
	g_VoterAuths.SetString(odingUserIdStr, voterAuth);
	
	if (choice == SBPP_VoteChoice_Yes)
	{
		if (g_VotersYes.FindValue(odingUserId) == -1)
			g_VotersYes.Push(odingUserId);
	}
	else
	{
		if (g_VotersNo.FindValue(odingUserId) == -1)
			g_VotersNo.Push(odingUserId);
	}
}

public void SBPP_OnVoteEnded(SBPP_VoteType voteType, SBPP_VoteResult result, int iTarget, const char[] sTargetName, const char[] sTargetAuth, const char[] sReason, int iVotesYes, int iVotesNo, int iVotesTotal, float fPercentage)
{
	if (!g_cvEnabled.BoolValue)
		return;
	
	char webhookURL[512];
	g_cvWebhookURL.GetString(webhookURL, sizeof(webhookURL));
	if (strlen(webhookURL) == 0)
		return;
	
	SendVoteEndedEmbed(webhookURL, voteType, result, sTargetName, sReason, iVotesYes, iVotesNo, iVotesTotal, fPercentage);
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
	
	SendActionExecuteEmbed(webhookURL, voteType, sTargetName, sReason, iDuration);
}

// ============================================================================
// Discord Embed Builders
// ============================================================================

void SendVoteInitiatedEmbed(const char[] webhookURL, SBPP_VoteType voteType, const char[] sTargetName, const char[] sReason)
{
	char voteTypeName[32];
	GetVoteTypeName(voteType, voteTypeName, sizeof(voteTypeName));
	
	char title[128];
	FormatEx(title, sizeof(title), "🗳️ Vote Initiated: %s", voteTypeName);
	JSONObject embed = CreateEmbed(title, "", COLOR_VOTE_INITIATED);
	
	// Initiator info
	char initiatorName[64], initiatorLinked[256];
	int initiatorClient = GetClientOfUserId(g_iVoteInitiatorUserId);
	
	if (initiatorClient > 0 && IsClientInGame(initiatorClient))
	{
		GetClientName(initiatorClient, initiatorName, sizeof(initiatorName));
		FormatNameAsProfileLink(initiatorClient, initiatorName, initiatorLinked, sizeof(initiatorLinked));
	}
	else
	{
		strcopy(initiatorLinked, sizeof(initiatorLinked), "Server/Console");
	}
	
	AddEmbedField(embed, "Initiated By", initiatorLinked, true);
	
	// Target info
	if (voteType != SBPP_VoteType_Map && voteType != SBPP_VoteType_Question)
	{
		char targetLinked[256], targetInfo[512];
		int targetClient = GetClientOfUserId(g_iVoteTargetUserId);
		bool targetConnected = (targetClient > 0 && IsClientConnected(targetClient));
		
		FormatNameAsProfileLinkFromUserId(g_iVoteTargetUserId, sTargetName, targetLinked, sizeof(targetLinked));
		FormatEx(targetInfo, sizeof(targetInfo), "%s\n*Status: %s*", 
			targetLinked, targetConnected ? "Connected" : "Disconnected");
		AddEmbedField(embed, "Target", targetInfo, true);
	}
	else if (voteType == SBPP_VoteType_Map)
	{
		AddEmbedField(embed, "Map", sTargetName, true);
	}
	
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
	
	SendDiscordWebhook(webhookURL, "", embed);
	delete embed;
}

void SendVoteEndedEmbed(const char[] webhookURL, SBPP_VoteType voteType, SBPP_VoteResult result, const char[] sTargetName, const char[] sReason, int iVotesYes, int iVotesNo, int iVotesTotal, float fPercentage)
{
	char voteTypeName[32];
	GetVoteTypeName(voteType, voteTypeName, sizeof(voteTypeName));
	
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
	
	// Initiator info
	char initiatorName[64], initiatorLinked[256];
	int initiatorClient = GetClientOfUserId(g_iVoteInitiatorUserId);
	
	if (initiatorClient > 0 && IsClientInGame(initiatorClient))
	{
		GetClientName(initiatorClient, initiatorName, sizeof(initiatorName));
		FormatNameAsProfileLink(initiatorClient, initiatorName, initiatorLinked, sizeof(initiatorLinked));
	}
	else
	{
		strcopy(initiatorLinked, sizeof(initiatorLinked), "Server/Console");
	}
	
	AddEmbedField(embed, "Initiated By", initiatorLinked, true);
	
	// Target info
	if (voteType != SBPP_VoteType_Map && voteType != SBPP_VoteType_Question)
	{
		char targetLinked[256], targetInfo[512];
		int targetClient = GetClientOfUserId(g_iVoteTargetUserId);
		bool targetConnected = (targetClient > 0 && IsClientConnected(targetClient));
		
		FormatNameAsProfileLinkFromUserId(g_iVoteTargetUserId, sTargetName, targetLinked, sizeof(targetLinked));
		FormatEx(targetInfo, sizeof(targetInfo), "%s\n*Status: %s*", 
			targetLinked, targetConnected ? "Connected" : "Disconnected");
		AddEmbedField(embed, "Target", targetInfo, true);
	}
	else if (voteType == SBPP_VoteType_Map)
	{
		AddEmbedField(embed, "Map", sTargetName, true);
	}
	
	char voteStats[256];
	FormatEx(voteStats, sizeof(voteStats), "**Yes:** %d\n**No:** %d\n**Total:** %d\n**Percentage:** %.1f%%", 
		iVotesYes, iVotesNo, iVotesTotal, fPercentage);
	AddEmbedField(embed, "📊 Results", voteStats, false);
	
	// Yes voters
	char yesVoters[8192] = "";
	int yesCount = g_VotersYes.Length;
	
	if (yesCount > 0)
	{
		for (int i = 0; i < yesCount; i++)
		{
			int odingUserId = g_VotersYes.Get(i);
			char odingUserIdStr[12], name[64], nameLinked[128];
			IntToString(odingUserId, odingUserIdStr, sizeof(odingUserIdStr));
			
			if (g_VoterNames.GetString(odingUserIdStr, name, sizeof(name)))
			{
				FormatNameAsProfileLinkFromUserId(odingUserId, name, nameLinked, sizeof(nameLinked));
				
				char voterLine[192];
				FormatEx(voterLine, sizeof(voterLine), "%d. %s\n", i + 1, nameLinked);
				StrCat(yesVoters, sizeof(yesVoters), voterLine);
			}
		}
	}
	else
	{
		strcopy(yesVoters, sizeof(yesVoters), "*No votes*");
	}
	
	AddEmbedField(embed, "👍 Voted Yes", yesVoters, false);
	
	// No voters
	char noVoters[8192] = "";
	int noCount = g_VotersNo.Length;
	
	if (noCount > 0)
	{
		for (int i = 0; i < noCount; i++)
		{
			int odingUserId = g_VotersNo.Get(i);
			char odingUserIdStr[12], name[64], nameLinked[128];
			IntToString(odingUserId, odingUserIdStr, sizeof(odingUserIdStr));
			
			if (g_VoterNames.GetString(odingUserIdStr, name, sizeof(name)))
			{
				FormatNameAsProfileLinkFromUserId(odingUserId, name, nameLinked, sizeof(nameLinked));
				
				char voterLine[192];
				FormatEx(voterLine, sizeof(voterLine), "%d. %s\n", i + 1, nameLinked);
				StrCat(noVoters, sizeof(noVoters), voterLine);
			}
		}
	}
	else
	{
		strcopy(noVoters, sizeof(noVoters), "*No votes*");
	}
	
	AddEmbedField(embed, "👎 Voted No", noVoters, false);
	
	if (strlen(sReason) > 0)
	{
		char reasonFormatted[512];
		FormatEx(reasonFormatted, sizeof(reasonFormatted), "```%s```", sReason);
		AddEmbedField(embed, "Reason", reasonFormatted, false);
	}
	
	int duration = GetTime() - g_iVoteStartTime;
	char durationStr[64];
	FormatEx(durationStr, sizeof(durationStr), "%d seconds", duration);
	AddEmbedField(embed, "Duration", durationStr, true);
	
	char resultStr[32];
	strcopy(resultStr, sizeof(resultStr), result == SBPP_VoteResult_Success ? "**PASSED** ✅" : "**FAILED** ❌");
	AddEmbedField(embed, "Result", resultStr, true);
	
	SendDiscordWebhook(webhookURL, "", embed);
	delete embed;
}

void SendActionExecuteEmbed(const char[] webhookURL, SBPP_VoteType voteType, const char[] sTargetName, const char[] sReason, int iDuration)
{
	char actionName[32];
	GetActionName(voteType, actionName, sizeof(actionName));
	
	char title[128];
	FormatEx(title, sizeof(title), "⚡ Action Executed: %s", actionName);
	JSONObject embed = CreateEmbed(title, "", COLOR_ACTION_EXECUTE);
	
	char targetLinked[256], targetInfo[512];
	int targetClient = GetClientOfUserId(g_iVoteTargetUserId);
	bool targetConnected = (targetClient > 0 && IsClientConnected(targetClient));
	
	FormatNameAsProfileLinkFromUserId(g_iVoteTargetUserId, sTargetName, targetLinked, sizeof(targetLinked));
	FormatEx(targetInfo, sizeof(targetInfo), "%s\n*Status: %s*", 
		targetLinked, targetConnected ? "Connected" : "Disconnected");
	AddEmbedField(embed, "Target Player", targetInfo, false);
	
	AddEmbedField(embed, "Action Type", actionName, true);
	
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
		case SBPP_VoteType_Map:      strcopy(buffer, maxlen, "Map Vote");
		case SBPP_VoteType_Kick:     strcopy(buffer, maxlen, "Kick Vote");
		case SBPP_VoteType_Ban:      strcopy(buffer, maxlen, "Ban Vote");
		case SBPP_VoteType_Mute:     strcopy(buffer, maxlen, "Mute Vote");
		case SBPP_VoteType_Gag:      strcopy(buffer, maxlen, "Gag Vote");
		case SBPP_VoteType_Question: strcopy(buffer, maxlen, "Question Vote");
		default:                     strcopy(buffer, maxlen, "Unknown Vote");
	}
}

void GetActionName(SBPP_VoteType voteType, char[] buffer, int maxlen)
{
	switch (voteType)
	{
		case SBPP_VoteType_Map:      strcopy(buffer, maxlen, "Map Change");
		case SBPP_VoteType_Kick:     strcopy(buffer, maxlen, "Player Kicked");
		case SBPP_VoteType_Ban:      strcopy(buffer, maxlen, "Player Banned");
		case SBPP_VoteType_Mute:     strcopy(buffer, maxlen, "Player Muted");
		case SBPP_VoteType_Gag:      strcopy(buffer, maxlen, "Player Gagged");
		case SBPP_VoteType_Question: strcopy(buffer, maxlen, "Question Result");
		default:                     strcopy(buffer, maxlen, "Unknown Action");
	}
}
