#include <clientprefs>
#include <cstrike>
#include <geoip>
#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <multicolors>

#undef REQUIRE_PLUGIN
#tryinclude <ScoreboardCustomLevels>
#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

#define SIZEOF_BOTTAG 3

ConVar g_cvTagMethod = null;
ConVar g_cvBotTags   = null;
ConVar g_cvShowFlags = null;

ArrayList g_aryBotTags     = null;
KeyValues g_kvCountryFlags = null;
Cookie g_hCTagCookie;

char g_sCountryTag[MAXPLAYERS + 1][6];

int  g_iTagMethod = 1;
int m_iOffset = -1;
int m_iLevel[MAXPLAYERS + 1] = { -1, ... };

bool g_bPluginCustomLevels = false;
bool g_bCustomLevelsNative = false;

bool g_bCSGO = false;
bool g_bLateLoad = false;
bool g_bShowFlags = false;

bool g_bCTagEnabled[MAXPLAYERS + 1] = { true,  ... };
bool g_bCheckCompleted[MAXPLAYERS + 1] = { false, ... };

public Plugin myinfo =
{
	name        = "Country Clan Tags",
	author      = "GoD-Tony, Franc1sco franug, maxime1907",
	description = "Assigns clan tags and flags based on the player's country",
	version     = "2.3.2",
	url         = "http://www.sourcemod.net/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("CountryTags");
	MarkNativeAsOptional("SCL_GetLevel");

	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_bCSGO = GetEngineVersion() == Engine_CSGO;

	g_cvTagMethod = CreateConVar("sm_countrytags", "1", "Determines plugin functionality. (0 = Disabled, 1 = Tag all players, 2 = Tag tagless players)", FCVAR_NONE, true, 0.0, true, 2.0);
	g_cvBotTags   = CreateConVar("sm_countrytags_bots", "CAN,USA", "Tags to assign bots. Separate tags by commas.", FCVAR_NONE);
	if (g_bCSGO)
	{
		g_cvShowFlags = CreateConVar("sm_countrytags_showflags", "1", "Show country flags in scoreboard.", FCVAR_NONE, true, 0.0, true, 1.0);
		g_cvShowFlags.AddChangeHook(OnConVarChange);
		g_bShowFlags = g_cvShowFlags.BoolValue;
	}

	g_cvTagMethod.AddChangeHook(OnConVarChange);
	g_cvBotTags.AddChangeHook(OnConVarChange);

	g_iTagMethod = g_cvTagMethod.IntValue;

	char sBuffer[124];
	g_aryBotTags = new ArrayList(SIZEOF_BOTTAG);
	GetConVarString(g_cvBotTags, sBuffer, sizeof(sBuffer));
	ExplodeString_adt(sBuffer, ",", g_aryBotTags, SIZEOF_BOTTAG);

	m_iOffset = FindSendPropInfo("CCSPlayerResource", "m_nPersonaDataPublicLevel");
	g_hCTagCookie = new Cookie("sm_countrytags_cookie", "Enable/Disable country tag!", CookieAccess_Private);

	if (g_iTagMethod != 0)
		SetCookieMenuItem(CookieMenu_CountryTag, INVALID_HANDLE, "CountryTag Settings");

	RegConsoleCmd("sm_ctag", Command_CountryTag, "This allows players to hide their flag");
	RegConsoleCmd("sm_showflag", Command_CountryTag, "This allows players to hide their flag");

	AutoExecConfig(true);
	HookEvent("player_team", Event_PlayerTeam);
}

public void OnAllPluginsLoaded()
{
	g_bPluginCustomLevels = LibraryExists("ScoreboardCustomLevels");
	VerifyNative_CustomLevels();
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "ScoreboardCustomLevels", false) == 0)
	{
		g_bPluginCustomLevels = true;
		VerifyNative_CustomLevels();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "ScoreboardCustomLevels", false) == 0)
	{
		g_bPluginCustomLevels = false;
		VerifyNative_CustomLevels();
	}
}

stock void VerifyNative_CustomLevels()
{
	g_bCustomLevelsNative = g_bPluginCustomLevels && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SCL_GetLevel") == FeatureStatus_Available;
}

public void OnConVarChange(ConVar hCvar, const char[] oldValue, const char[] newValue)
{
	if (hCvar == g_cvTagMethod)
	{
		g_iTagMethod = g_cvTagMethod.IntValue;
	}
	else if (hCvar == g_cvBotTags)
	{
		g_aryBotTags.Clear();
		ExplodeString_adt(newValue, ",", g_aryBotTags, SIZEOF_BOTTAG);
	}
	else if (hCvar == g_cvShowFlags)
	{
		g_bShowFlags = g_cvShowFlags.BoolValue;
	}
}

public void OnClientSettingsChanged(int client)
{
	if(IsClientInGame(client) && TagPlayer(client))
	{
		SetClientClanTagToCountryCode(client);
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcastin)
{
	if (g_iTagMethod <= 0)
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if(g_bCheckCompleted[client])
		return;

	int team = event.GetInt("team");
	if(team == CS_TEAM_NONE || team == CS_TEAM_SPECTATOR)
		return;
	
	g_bCheckCompleted[client] = true;

	if(!g_sCountryTag[client][0])
	{
		CreateTimer(10.0, SetClientClanTag_Timer, GetClientUserId(client));
		return;
	}

	SetClientClanTagToCountryCode(client);
}

public Action SetClientClanTag_Timer(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if(!client)
		return Plugin_Stop;

	if(!IsClientConnected(client))
		return Plugin_Stop;

	SetClientClanTagToCountryCode(client);
	return Plugin_Stop;
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client) || IsClientSourceTV(client))
		return;

	char cookieValue[3];
	g_hCTagCookie.Get(client, cookieValue, sizeof(cookieValue));
	g_bCTagEnabled[client] = (strcmp(cookieValue, "") != 0 && cookieValue[0] == '0') ? false : true;
}

public void OnClientConnected(int client)
{
	if(!IsFakeClient(client) || IsClientSourceTV(client))
		return;

	char code2[3];

	// Disabled tag for bots
	if (g_aryBotTags.Length <= 0)
		return;

	int idx = GetRandomInt(0, g_aryBotTags.Length - 1);
	g_aryBotTags.GetString(idx, code2, SIZEOF_BOTTAG);
	Format(g_sCountryTag[client], sizeof(g_sCountryTag[]), "[%s]", code2);
}

public void OnClientPostAdminCheck(int client)
{
	if(IsFakeClient(client))
		return;

	char ip[16];
	char code2[3];

	m_iLevel[client] = -1;

	if (!GetClientIP(client, ip, sizeof(ip)) || !IsLocalAddress(ip) && !GeoipCode2(ip, code2))
		code2 = "??";

	if (IsLocalAddress(ip))
	{
		char sNetIP[32] = "";

		ConVar g_cvNetPublicAddr = FindConVar("net_public_adr");
		if (g_cvNetPublicAddr != null)
		{
			g_cvNetPublicAddr.GetString(sNetIP, sizeof(sNetIP));
			delete g_cvNetPublicAddr;
		}

		if (!GeoipCode2(sNetIP, code2))
			code2 = "??";
	}
	
	if (g_bCSGO && g_bShowFlags)
	{
		if (g_kvCountryFlags.JumpToKey(code2))
			m_iLevel[client] = g_kvCountryFlags.GetNum("index");

		g_kvCountryFlags.Rewind();
	}

	Format(g_sCountryTag[client], sizeof(g_sCountryTag[]), "[%s]", code2);
}

public void OnClientDisconnect(int client)
{
	m_iLevel[client] = -1;
	g_bCTagEnabled[client] = true;
	g_bCheckCompleted[client] = false;
	g_sCountryTag[client][0] = '\0';
}

public void OnConfigsExecuted()
{
	if (!g_bCSGO || !g_bShowFlags)
		return;

	char sBuffer[PLATFORM_MAX_PATH];
	char m_cFilePath[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, m_cFilePath, sizeof(m_cFilePath), "configs/countryflags.cfg");

	SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, OnThinkPost);

	delete g_kvCountryFlags;
	g_kvCountryFlags = new KeyValues("CountryFlags");
	if(!g_kvCountryFlags.ImportFromFile(m_cFilePath))
	{
		LogError("Could not find country flags config: %s", m_cFilePath);
		delete g_kvCountryFlags;
		return;
	}

	if (!g_kvCountryFlags.GotoFirstSubKey())
	{
		LogError("Could not parse country flags config: %s", m_cFilePath);
		delete g_kvCountryFlags;
		return;
	}

	do
	{
		Format(sBuffer, sizeof(sBuffer), "materials/panorama/images/icons/xp/level%i.png", KvGetNum(g_kvCountryFlags, "index"));
		AddFileToDownloadsTable(sBuffer);
	}
	while (g_kvCountryFlags.GotoNextKey());

	g_kvCountryFlags.Rewind();

	if (g_bLateLoad)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
			{
				if(AreClientCookiesCached(i))
					OnClientCookiesCached(i);
					
				OnClientPostAdminCheck(i);
				SetClientClanTagToCountryCode(i);
			}
		}
		g_bLateLoad = false;
	}
}

public void OnThinkPost(int m_iEntity)
{
	if (!g_bCSGO || !g_bShowFlags)
		return;

	int m_iLevelTemp[MAXPLAYERS + 1] = { 0, ... };
	GetEntDataArray(m_iEntity, m_iOffset, m_iLevelTemp, MAXPLAYERS + 1);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (m_iLevel[i] != -1)
		{
			if (m_iLevel[i] != m_iLevelTemp[i])
			{
			#if defined _ScoreboardCustomLevels_included
				if (g_bCustomLevelsNative && SCL_GetLevel(i) > 0)
					continue;    // dont overwritte other custom level
			#endif

				SetEntData(m_iEntity, m_iOffset + (i * 4), m_iLevel[i]);
			}
		}
	}
}

stock bool TagPlayer(int client)
{
	/* Should we be tagging this player? */
	if(!g_bCTagEnabled[client])
		return false;

	char sClanID[32];
	GetClientInfo(client, "cl_clanid", sClanID, sizeof(sClanID));

	if (g_iTagMethod == 1 || (g_iTagMethod == 2 && StringToInt(sClanID) == 0))
		return true;

	return false;
}

stock void ExplodeString_adt(const char[] text, const char[] split, ArrayList array, int size)
{
	/* Rewritten ExplodeString stock (string.inc) using an adt array. */
	char[] sBuffer = new char[size];
	int idx, reloc_idx;

	while ((idx = SplitString(text[reloc_idx], split, sBuffer, size)) != -1)
	{
		array.PushString(sBuffer);

		reloc_idx += idx;

		if (text[reloc_idx] == '\0')
			break;
	}

	if (text[reloc_idx] != '\0')
	{
		strcopy(sBuffer, size, text[reloc_idx]);
		array.PushString(sBuffer);
	}
}

stock bool IsLocalAddress(const char ip[16])
{
	// 192.168.0.0 - 192.168.255.255 (65,536 IP addresses)
	// 10.0.0.0 - 10.255.255.255 (16,777,216 IP addresses)
	if (StrContains(ip, "192.168", false) > -1 || StrContains(ip, "10.", false) > -1)
	{
		return true;
	}

	// 172.16.0.0 - 172.31.255.255 (1,048,576 IP addresses)
	char octets[4][3];
	if (ExplodeString(ip, ".", octets, 4, 3) == 4)
	{
		if (StrContains(octets[0], "172", false) > -1)
		{
			int octet = StringToInt(octets[1]);

			return (!(octet < 16) || !(octet > 31));
		}
	}

	return false;
}

stock void SetClientClanTagToCountryCode(int client)
{
	if (g_iTagMethod <= 0)
		return;

	if(!g_sCountryTag[client][0])
		return;

	if(!TagPlayer(client))
		return;

	char tag[32];
	CS_GetClientClanTag(client, tag, sizeof(tag));
	if(g_iTagMethod == 2 && tag[0])
		return;

	CS_SetClientClanTag(client, g_sCountryTag[client]);
}

stock void ToggleClientClanTag(int client)
{
	if (g_iTagMethod <= 0)
	{
		CReplyToCommand(client, "{green}[SM] {default}Country Tag functions are currently Disabled.");
		return;
	}
	g_bCTagEnabled[client] = !g_bCTagEnabled[client];
	
	char cookieValue[4];
	FormatEx(cookieValue, sizeof(cookieValue), "%d", g_bCTagEnabled[client]);
	g_hCTagCookie.Set(client, cookieValue);
	
	CReplyToCommand(client, "{green}[SM] {default}You have {olive}%s {default}Country Tag!", (g_bCTagEnabled[client]) ? "Enabled" : "Disabled");
	
	if(g_bCTagEnabled[client])
		SetClientClanTagToCountryCode(client);
	else
	{
		char tag[32];
		CS_GetClientClanTag(client, tag, sizeof(tag));
		if(strcmp(tag, g_sCountryTag[client], false) == 0)
			CS_SetClientClanTag(client, "");
	}
}

public Action Command_CountryTag(int client, int args)
{
	if(!client)
		return Plugin_Handled;
		
	if(!AreClientCookiesCached(client))
	{
		CReplyToCommand(client, "{green}[SM] {default}You have to be authorized to use this command!");
		return Plugin_Handled;
	}

	ToggleClientClanTag(client);	
	return Plugin_Handled;
}

public void CookieMenu_CountryTag(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if(action == CookieMenuAction_SelectOption)
		DisplayCookieMenu(client);
}

stock void DisplayCookieMenu(int client)
{
	Menu menu = new Menu(Menu_CookieHandler);
	menu.SetTitle("CountryTag Settings");

	char item[32];
	Format(item, sizeof(item), "%s Country Tag", (g_bCTagEnabled[client]) ? "Disable" : "Enable");
	menu.AddItem("0", item);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_CookieHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Select:
		{
			ToggleClientClanTag(param1);
			DisplayCookieMenu(param1);
		}
	}

	return 0;
}
